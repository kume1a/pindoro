import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/features/course/data/course_data.dart';
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

/// A lesson being played; [nearest] is set once a pin step is answered and
/// [choice] while a name step has a plate picked.
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
    this.pin,
    this.nearest,
    this.choice,
    this.fixesOpen = false,
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

  /// The mistakes list was closed with Fix them.
  final bool fixesOpen;

  LessonPlaying copyWith({
    LessonRun? run,
    LatLng? pin,
    LatLng? nearest,
    int? choice,
    bool? fixesOpen,
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
    pin: clearStep ? null : pin ?? this.pin,
    nearest: clearStep ? null : nearest ?? this.nearest,
    choice: clearStep ? null : choice ?? this.choice,
    fixesOpen: fixesOpen ?? this.fixesOpen,
  );
}

/// Plays a lesson's step list (pindoro_core `LessonRun`) and saves it once,
/// when it ends: leaving before then writes nothing.
class LessonController extends Notifier<LessonState> {
  bool _saving = false;

  @override
  LessonState build() => const LessonLoading();

  // Leaving disposes this controller: methods take the DAO before their
  // first await and check ref.mounted before touching state again.
  ProgressDao get _dao => ref.read(progressDaoProvider);

  Future<void> start(LessonArgs args) async {
    final dao = _dao;
    final plan = await ref.read(coursePlanProvider.future);
    final settings = await ref.read(settingsDaoProvider).read();
    if (!ref.mounted) return;
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
    state = LessonPlaying(
      args: args,
      cityId: city.id,
      cityCenter: city.center,
      unit: unit,
      shape: shape,
      difficulty: settings.difficulty,
      startedAt: DateTime.now(),
      run: LessonRun(
        args.kind,
        planLesson(
          kind: args.kind,
          streets: streets,
          unitStreets: unit.streets,
          lastDistances: last,
          random: ref.read(lessonRandomProvider),
        ),
      ),
    );
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
      state = (state as LessonPlaying).copyWith(
        run: run.answerPin(score, nearest.distanceM, DateTime.now()),
        nearest: nearest.nearestPoint,
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
      state = p.copyWith(
        run: p.run.answerName(right: right, at: DateTime.now()),
      );
    }
  }

  void openFixes() {
    if (state case final LessonPlaying p) state = p.copyWith(fixesOpen: true);
  }

  /// The next step; after the last one the lesson is saved.
  Future<void> next() async {
    if (state case final LessonPlaying p) {
      final run = p.run.next();
      state = p.copyWith(run: run, clearStep: true);
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
      if (ref.mounted) state = LessonSaved(id);
    } finally {
      _saving = false;
    }
  }
}
