import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/features/course/data/course_data.dart';
import 'package:pindoro/features/league/data/league_data.dart';
import 'package:pindoro/features/lesson/data/saved_progress.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// Overridden in tests with a seeded Random.
final lessonRandomProvider = Provider<Random>((ref) => Random());

/// What to play: a unit's lesson (or its practice) or the unit's Pit stop.
typedef LessonArgs = ({String unitId, LessonKind kind, int? lesson});

final lessonControllerProvider =
    NotifierProvider.autoDispose<LessonController, LessonState>(
      LessonController.new,
    );

sealed class LessonState {
  const LessonState();
}

final class LessonLoading extends LessonState {
  const LessonLoading();
}

/// The unit, the lesson or the Pit stop's streets are gone: back to the Path.
final class LessonMissing extends LessonState {
  const LessonMissing();
}

final class LessonSaved extends LessonState {
  const LessonSaved(this.resultId);

  final String resultId;
}

/// A lesson being played; [nearest] is set once a pin step is answered,
/// [choice] while a name step has a plate picked and [draft] on a road trip.
/// [firstTrip] shows the road-trip ghost (no trip saved yet).
final class LessonPlaying extends LessonState {
  const LessonPlaying({
    required this.args,
    required this.cityId,
    required this.cityCenter,
    required this.unit,
    required this.shape,
    required this.difficulty,
    required this.startedAt,
    required this.run,
    this.graph,
    this.pin,
    this.nearest,
    this.choice,
    this.draft,
    this.fixesOpen = false,
    this.firstTrip = false,
  });

  final LessonArgs args;
  final String cityId;
  final LatLng cityCenter;
  final CourseUnit unit;
  final AreaShape shape;
  final Difficulty difficulty;
  final DateTime startedAt;
  final LessonRun run;
  final LatLng? pin;
  final LatLng? nearest;
  final int? choice;
  final RoadGraph? graph;
  final RouteDraft? draft;

  /// The road trip's route so far: from A until something is drawn.
  RouteDraft? get route => switch (run.step) {
    TripStep(:final trip) when !run.finished =>
      draft ?? RouteDraft(graph!, trip.from, trip.to),
    _ => null,
  };

  /// The mistakes list was closed with Fix them.
  final bool fixesOpen;
  final bool firstTrip;

  LessonPlaying copyWith({
    LessonRun? run,
    LatLng? pin,
    LatLng? nearest,
    int? choice,
    RouteDraft? draft,
    bool? fixesOpen,
    bool? firstTrip,
    bool clearStep = false,
  }) => LessonPlaying(
    args: args,
    cityId: cityId,
    cityCenter: cityCenter,
    unit: unit,
    shape: shape,
    difficulty: difficulty,
    startedAt: startedAt,
    run: run ?? this.run,
    graph: graph,
    pin: clearStep ? null : pin ?? this.pin,
    nearest: clearStep ? null : nearest ?? this.nearest,
    choice: clearStep ? null : choice ?? this.choice,
    draft: draft ?? (clearStep ? null : this.draft),
    fixesOpen: fixesOpen ?? this.fixesOpen,
    firstTrip: firstTrip ?? this.firstTrip,
  );
}

/// Plays a lesson's step list (pindoro_core `LessonRun`) and saves its result
/// once, when it ends. Until then every step saves where it stands
/// (`saved_lesson`), so an app kill resumes it; leaving drops that.
class LessonController extends Notifier<LessonState> {
  bool _saving = false;

  /// What the saved lesson re-plans from.
  int _seed = 0;
  String _packVersion = '';

  @override
  LessonState build() => const LessonLoading();

  // Leaving disposes this controller: methods take the DAO before their
  // first await and check ref.mounted before touching state again.
  ProgressDao get _dao => ref.read(progressDaoProvider);

  /// Plays [args], resuming its saved run when the app was killed in it.
  Future<void> start(LessonArgs args) async {
    final dao = _dao;
    final plan = await ref.read(coursePlanProvider.future);
    final graph = await ref.read(roadGraphProvider.future);
    final settings = await ref.read(settingsDaoProvider).read();
    final firstTrip = await dao.roadTrips() == 0;
    final now = DateTime.now();
    var saved = await dao.savedLesson(now);
    if (!ref.mounted) return;
    if (saved != null &&
        (saved.unitId != args.unitId ||
            saved.kind != args.kind ||
            saved.lesson != args.lesson ||
            plan == null ||
            saved.packVersion != packVersion(plan.pack))) {
      saved = null;
      await dao.dropSavedLesson();
      if (!ref.mounted) return;
    }
    final unit = plan?.units.where((u) => u.id == args.unitId).firstOrNull;
    final shape = unit == null
        ? null
        : DistrictsArea({unit.id}).shapeIn(plan!.pack);
    if (plan == null || unit == null || shape == null) {
      state = const LessonMissing();
      return;
    }
    final city = plan.pack.city();
    var streets = <NamedStreet>[];
    var last = const <String, double>{};
    if (args.kind == LessonKind.pitStop) {
      final ids = await dao.unitMistakes(
        city.id,
        unit.id,
        throughLesson: unit.pitStopAfter,
      );
      streets = [for (final id in ids) ?plan.streets[id]];
      last = await dao.lastDistances(city.id, [for (final s in streets) s.id]);
    } else {
      streets =
          unit.lessons
              .where((l) => l.number == args.lesson)
              .firstOrNull
              ?.streets ??
          const [];
    }
    if (!ref.mounted) return;
    if (streets.isEmpty) {
      state = const LessonMissing();
      return;
    }
    _seed = saved?.seed ?? ref.read(lessonRandomProvider).nextInt(1 << 32);
    _packVersion = packVersion(plan.pack);
    // The trip, then the steps: a resumed lesson re-plans in the same order.
    final random = Random(_seed);
    final trip = graph == null || args.kind == LessonKind.pitStop
        ? null
        : pickTrip(
            graph,
            destinations: streets,
            starts: unit.streets,
            minM: TripRules.lessonMinM,
            maxM: TripRules.lessonMaxM,
            random: random,
          );
    final steps = planLesson(
      kind: args.kind,
      streets: streets,
      unitStreets: unit.streets,
      lastDistances: last,
      trip: trip,
      random: random,
    );
    final progress = saved == null ? null : decodeProgress(saved.progress);
    final restored = progress == null
        ? null
        : LessonRun.restore(
            args.kind,
            steps,
            progress.answers,
            progress.index,
          )?.resumeAt();
    if (saved != null && restored == null) {
      await dao.dropSavedLesson();
      if (!ref.mounted) return;
    }
    final playing = LessonPlaying(
      args: args,
      cityId: city.id,
      cityCenter: city.center,
      unit: unit,
      shape: shape,
      difficulty: restored != null ? saved!.difficulty : settings.difficulty,
      // A resumed lesson's clock goes on from where the app died.
      startedAt: restored != null
          ? now.subtract(saved!.savedAt.difference(saved.startedAt))
          : now,
      graph: graph,
      run: restored ?? LessonRun(args.kind, steps),
      firstTrip: firstTrip,
    );
    state = playing;
    if (playing.run.finished) {
      await _save(playing);
    } else if (restored != null) {
      _persist(playing);
    }
  }

  /// Leaving with ✕ drops the saved lesson.
  Future<void> leave() => _dao.dropSavedLesson();

  /// Saves where the lesson stands; the last step's Next saves the result
  /// instead.
  void _persist(LessonPlaying p) {
    if (p.run.finished) return;
    unawaited(
      _dao.saveLesson(
        cityId: p.cityId,
        unitId: p.unit.id,
        kind: p.args.kind,
        lesson: p.args.lesson,
        difficulty: p.difficulty,
        packVersion: _packVersion,
        seed: _seed,
        startedAt: p.startedAt,
        progress: encodeProgress(p.run),
      ),
    );
  }

  /// Sets [next] as the state and saves where it stands.
  void _step(LessonPlaying next) {
    state = next;
    _persist(next);
  }

  /// The road trip's route as drawn so far.
  void drawTo(RouteDraft draft) {
    if (state case final LessonPlaying p
        when p.run.step is TripStep && !p.run.answered) {
      state = p.copyWith(draft: draft);
    }
  }

  /// Scores the road trip once its route reaches B.
  void checkRoute() {
    if (state case LessonPlaying(
      run: final run,
      route: final draft?,
      :final difficulty,
    ) when run.step is TripStep && !run.answered && draft.reached) {
      final best = (run.step as TripStep).trip.best;
      _step(
        (state as LessonPlaying).copyWith(
          run: run.answerTrip(
            scoreRoute(draft.lengthM, best.lengthM, difficulty),
            DateTime.now(),
          ),
          // A retry in Fix them is no longer the first trip ever.
          firstTrip: false,
        ),
      );
    }
  }

  /// Gives the road trip up: a Miss.
  void showRoute() {
    if (state case final LessonPlaying p
        when p.run.step is TripStep && !p.run.answered) {
      _step(
        p.copyWith(
          run: p.run.answerTrip((tier: Tier.miss, xp: 0), DateTime.now()),
          firstTrip: false,
        ),
      );
    }
  }

  void placePin(LatLng pin) {
    if (state case final LessonPlaying p
        when p.run.step is PinStep && !p.run.answered) {
      state = p.copyWith(pin: pin);
    }
  }

  void confirm() {
    if (state case LessonPlaying(
      run: final run,
      pin: final pin?,
      :final difficulty,
    ) when run.step is PinStep && !run.answered) {
      final nearest = run.step.street.nearest(pin);
      final score = scoreAnswer(
        nearest.distanceM,
        nearest.part.roadClass,
        difficulty,
      );
      _step(
        (state as LessonPlaying).copyWith(
          run: run.answerPin(score, nearest.distanceM, DateTime.now()),
          nearest: nearest.nearestPoint,
        ),
      );
    }
  }

  void choose(int option) {
    if (state case final LessonPlaying p
        when p.run.step is NameStep && !p.run.answered) {
      state = p.copyWith(choice: option);
    }
  }

  void check() {
    if (state case final LessonPlaying p
        when p.choice != null && !p.run.answered) {
      final step = p.run.step;
      if (step is! NameStep) return;
      final right = step.options[p.choice!].id == step.street.id;
      _step(
        p.copyWith(
          run: p.run.answerName(right: right, at: DateTime.now()),
        ),
      );
    }
  }

  void openFixes() {
    if (state case final LessonPlaying p) state = p.copyWith(fixesOpen: true);
  }

  /// The next step; after the last one the lesson is saved. A test step
  /// waits for its answer: a quick second tap must not skip the next test.
  Future<void> next() async {
    if (state case final LessonPlaying p
        when !p.run.finished && (p.run.step is CardStep || p.run.answered)) {
      final run = p.run.next();
      _step(p.copyWith(run: run, clearStep: true));
      if (run.finished) await _save(p.copyWith(run: run));
    }
  }

  Future<void> _save(LessonPlaying p) async {
    if (_saving) return;
    _saving = true;
    final dao = _dao;
    try {
      final inPitStop = {
        for (final item in await dao.pitStop(p.cityId)) item.streetId,
      };
      final id = await dao.finishLesson(
        cityId: p.cityId,
        unitId: p.unit.id,
        kind: p.args.kind,
        lesson: p.args.lesson,
        difficulty: p.difficulty,
        run: p.run,
        startedAt: p.startedAt,
        reviews: reviewAnswers(p.run, inPitStop: inPitStop),
      );
      if (!ref.mounted) return;
      state = LessonSaved(id);
      ref.invalidate(standingProvider);
    } finally {
      _saving = false;
    }
  }
}
