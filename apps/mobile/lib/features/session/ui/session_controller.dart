import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/hold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/cards.dart';
import 'package:pindoro/features/learning/data/day.dart';
import 'package:pindoro/features/learning/data/drive_history.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/route_book.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/learning/data/today_plan.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/session/ui/session_tasks.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:uuid/uuid.dart';

export 'package:pindoro/features/session/ui/session_tasks.dart';

final sessionControllerProvider =
    NotifierProvider.autoDispose<SessionController, SessionState>(
      SessionController.new,
    );

sealed class SessionState {
  const SessionState();
}

final class SessionLoading extends SessionState {
  const SessionLoading();
}

/// Nothing to learn now: no pack, or nothing due and no new streets.
final class SessionEmpty extends SessionState {
  const SessionEmpty();
}

/// A family member's intro chip: its parent and how many children of each
/// kind the parent has.
typedef SessionFamily = ({NamedStreet parent, Map<FamilyKind, int> children});

/// Guess first (SPEC §6.4): a child whose parent the player knows is pinned
/// before its intro; the guess is graded but schedules nothing.
typedef SessionGuess = ({NamedStreet parent, int knownSiblings});

/// A graded pin, as the reveal shows it.
/// A pin step answered: its [grade], the [pin] and the street's [nearest] point; all three
/// null for "I don't know".
typedef SessionReveal = ({
  PinGrade? grade,
  LatLng? pin,
  LatLng? nearest,

  /// Null: back in this session (Again).
  int? nextReviewDays,

  /// The street a Mix-up's pin hit.
  NamedStreet? hit,
});

final class SessionPlaying extends SessionState {
  const SessionPlaying({
    required this.steps,
    required this.index,
    required this.forgotten,
    required this.street,
    required this.area,
    required this.knownNames,
    required this.newIndex,
    required this.newTotal,
    this.task = const PinTask(),
    this.family,
    this.guess,
    this.frame,
    this.pin,
    this.reveal,
    this.contrast,
    this.note,
    this.leech = false,
    this.suspended = false,
  });

  /// The whole session, done steps included; relearns join as Again comes.
  final List<SessionStep> steps;
  final int index;

  /// Step indices answered Again, for the session bar.
  final Set<int> forgotten;

  /// The current step's street.
  final NamedStreet street;

  /// The city: the pin can go anywhere in it.
  final AreaShape area;

  /// Names of the streets the player knows: a place question names them
  /// (SPEC §16.18).
  final Set<String> knownNames;

  /// "New street · [newIndex] of [newTotal]".
  final int newIndex;
  final int newTotal;

  /// What the step asks beyond a pin (name, ends, drills).
  final SessionTask task;
  final SessionFamily? family;

  /// Set while an intro waits for its guess.
  final SessionGuess? guess;

  /// Retrieval 1 frames the street's district; null frames the city.
  final List<LatLng>? frame;
  final LatLng? pin;
  final SessionReveal? reveal;

  /// A leech's intro: the street it is most often mixed up with, shown
  /// beside it, and the player's note.
  final NamedStreet? contrast;
  final String? note;

  /// The intro brings back a suspended leech (SPEC §4).
  final bool leech;

  /// The answer just made the card a leech: suspended until a fresh intro.
  final bool suspended;

  SessionStep get step => steps[index];

  /// The step's answer is in: the reveal or the task's result shows.
  bool get answered => reveal != null || task.result != null;

  /// The answer's tier, for its sound and haptic; a Mix-up is a Miss.
  Tier? get resultTier => switch (reveal) {
    final r? => r.hit == null ? r.grade?.tier ?? Tier.miss : Tier.miss,
    null => task.result,
  };

  /// [pin] is a function so "I don't know" can clear it.
  SessionPlaying copyWith({
    LatLng? Function()? pin,
    SessionReveal? reveal,
    List<SessionStep>? steps,
    Set<int>? forgotten,
    SessionTask? task,
    bool? suspended,
  }) => SessionPlaying(
    steps: steps ?? this.steps,
    index: index,
    forgotten: forgotten ?? this.forgotten,
    street: street,
    area: area,
    knownNames: knownNames,
    newIndex: newIndex,
    newTotal: newTotal,
    task: task ?? this.task,
    family: family,
    guess: guess,
    frame: frame,
    pin: pin == null ? this.pin : pin(),
    reveal: reveal ?? this.reveal,
    contrast: contrast,
    note: note,
    leech: leech,
    suspended: suspended ?? this.suspended,
  );
}

/// What the session did (Session done).
typedef SessionSummary = ({
  int reviews,
  int newStreets,
  int recalledPercent,
  double memoryBefore,
  double memoryAfter,
  List<(NamedStreet, NamedStreet)> mixUps,
  List<NamedStreet> closeTwice,
  int minutes,
  bool cleared,

  /// The round just played, 1-based, of [rounds]: Next round while more are left.
  int round,
  int rounds,
});

final class SessionDone extends SessionState {
  const SessionDone(this.summary);

  final SessionSummary summary;
}

/// What placement found (the placement result).
typedef PlacementSummary = ({
  int passed,
  ({int passed, int of}) mainRoads,
  int raions,

  /// The road class new streets start with, else the neighbourhood.
  RoadBand? startBand,
  District? startIn,
});

final class SessionPlaced extends SessionState {
  const SessionPlaced(this.summary);

  final PlacementSummary summary;
}

/// Plays today's session (docs/learning/SPEC.md §6.4, §7, §16.2, §16.13):
/// intros, pins, name and ends cards and drills graded by pindoro_learning,
/// each answer saved as it comes, relearns slotted in after Again. Leaving
/// keeps everything answered so far.
class SessionController extends Notifier<SessionState> {
  late Map<String, NamedStreet> _streets;
  late Set<NamedStreet> _all;
  late PackRepository _pack;
  late Curriculum _curriculum;
  late Map<String, CardState> _cards;

  /// Whether the pack asks a card: one it doesn't is never due.
  late AsksCard _asks;

  /// Which of [cards] are reviewed now: asked, and not parked (SPEC §16.22).
  AsksCard _reviews(Iterable<CardState> cards) => reviewsOf(
    _asks,
    streets: _streets,
    curriculum: _curriculum,
    cards: cards,
    yours: _yours,
  );

  /// The streets of the player's routes, never parked (SPEC §16.23 item 120).
  List<String> _yours = const [];
  late List<(String, String)> _confusions;
  late Map<String, int> _successes;
  late double _memoryBefore;
  late int _seed;
  Drills _drills = Drills.none;
  RouteBook _routes = (
    candidates: const <RouteCandidate>[],
    questions: const <String, RouteQuestion>{},
  );

  /// Recitals (SPEC §5.3): graded on the graph with the player's reported
  /// moves, their runs by id, pack junctions by OSM node and back, and each
  /// R item's task as first built.
  RoadGraph? _graph;
  Map<String, Run> _runs = const {};
  Map<int, int> _byNode = const {};
  Map<int, int> _nodes = const {};
  final Map<String, RecitalTask?> _recitals = {};

  /// Tier C pin cards aim lower while the days run long (SPEC §4).
  bool _tierCRelief = false;

  /// Each leech's top confusion, read before its intro.
  final Map<String, NamedStreet> _contrasts = {};

  /// Set while placing (SPEC §6.2): the run decides which streets come next.
  Placement? _placement;
  late List<String> _anchors;
  String _sessionId = const Uuid().v7();
  final List<SessionAnswer> _answers = [];

  /// Set while an answer saves: a second tap meanwhile is ignored.
  bool _saving = false;

  /// When each intro and answer happened: the session's minutes.
  final List<DateTime> _times = [];
  int _introsDone = 0;
  DateTime _shownAt = DateTime(0);

  @override
  SessionState build() => const SessionLoading();

  LearningDao get _dao => ref.read(learningDaoProvider);
  DateTime _now() => ref.read(clockProvider)();

  /// The day's rounds (SPEC §16.20): one for placement.
  List<List<SessionStep>> _rounds = const [];
  int _round = 0;

  /// The steps of the rounds already played, relearns included: the relearn
  /// cap is per session (SPEC §16.18).
  List<SessionStep> _played = const [];

  /// The round playing, 1-based, of how many.
  ({int index, int count}) get round =>
      (index: _round + 1, count: _rounds.length);

  /// Today's session, with [more] "Learn 10 more", with [placement] the
  /// city's placement, or with [drill] those cards as relearns (a drive's
  /// missed turns, SPEC §16.23 item 121).
  Future<void> start({
    bool placement = false,
    bool more = false,
    List<String>? drill,
  }) async {
    state = const SessionLoading();
    _resetSession();
    // Every read starts before the first await: the screen can go meanwhile.
    final dao = _dao;
    final planFuture = placement || drill != null
        ? null
        : ref.hold((more ? learnMorePlanProvider : todayPlanProvider).future);
    final streetsFuture = ref.read(cityStreetsProvider.future);
    final packFuture = ref.read(packRepositoryProvider.future);
    final curriculumFuture = ref.read(curriculumProvider.future);
    final routesFuture = ref.read(routeBookProvider.future);
    final runsFuture = ref.hold(runsProvider.future);
    final graphFuture = ref.hold(drivingGraphProvider.future);
    final asksFuture = ref.hold(asksCardProvider.future);
    // Learn 10 more restarts in place: the routes read for the day still hold.
    final yoursFuture = more ? null : ref.hold(yourRouteItemsProvider.future);
    final settingsFuture = ref.read(settingsProvider.future);
    final plan = await planFuture;
    final streets = await streetsFuture;
    final pack = await packFuture;
    final curriculum = await curriculumFuture;
    final routes = await routesFuture;
    final runs = await runsFuture;
    final graph = await graphFuture;
    final asks = await asksFuture;
    final yours = (await yoursFuture)?.streets ?? _yours;
    final cards = await dao.cards();
    final confusions = await dao.confusionPairs();
    final log = await dao.log();
    final learnCity = await dao.learnCity(pack.city().id);
    final settings = await settingsFuture;
    final contrasts = <String, NamedStreet>{};
    for (final c in cards.where((c) => c.phase == CardPhase.suspended)) {
      final top = streets[await dao.topConfusion(itemKey(c.itemId)) ?? ''];
      if (top != null) contrasts[c.itemId] = top;
    }
    if (!ref.mounted) return;
    final now = _now();
    if (placement) {
      _placement = Placement(
        curriculum,
        seed: now.microsecondsSinceEpoch,
        carded: {
          for (final c in cards)
            if (c.type == CardType.p) ?streets[itemKey(c.itemId)]?.id,
        },
      );
    }
    final rounds =
        switch (drill) {
          final ids? => [
            [for (final id in ids) (kind: StepKind.relearn, itemId: id)],
          ],
          null => null,
        } ??
        plan?.rounds ??
        [
          [
            for (final id in _placement!.streets)
              (kind: StepKind.placement, itemId: CardType.p.item(id)),
          ],
        ];
    if (rounds.isEmpty) {
      state = const SessionEmpty();
      return;
    }
    _streets = streets;
    _all = streets.values.toSet();
    _pack = pack;
    _curriculum = curriculum;
    _drills = plan?.drills ?? Drills.none;
    _routes = routes;
    _graph = graph;
    _runs = {for (final r in runs) r.id: r};
    _nodes = pack.junctionNodes();
    _byNode = {for (final e in _nodes.entries) e.value: e.key};
    _contrasts.addAll(contrasts);
    _cards = {for (final c in cards) c.itemId: c};
    _asks = asks;
    _yours = yours;
    _confusions = [...confusions];
    _successes = priorSuccesses(log);
    _anchors = [?learnCity?.homeId, ?learnCity?.workId];
    _tierCRelief = tierCRelief(
      log,
      minutesPerDay: settings.minutesPerDay,
      now: now,
    ).on;
    _seed = now.microsecondsSinceEpoch;
    _memoryBefore = _memory(now);
    _rounds = rounds;
    _show(rounds.first, 0, const {});
  }

  /// A fresh session on this controller (Learn 10 more restarts it in place).
  void _resetSession() {
    _sessionId = const Uuid().v7();
    _rounds = const [];
    _round = 0;
    _played = const [];
    _placement = null;
    _recitals.clear();
    _contrasts.clear();
    _resetSummary();
  }

  /// What a round's summary counts starts over.
  void _resetSummary() {
    _answers.clear();
    _times.clear();
    _introsDone = 0;
  }

  /// After a round's summary: the next round, with a summary of its own.
  void nextRound() {
    if (state is! SessionDone || _round + 1 >= _rounds.length) return;
    _resetSummary();
    _memoryBefore = _memory(_now());
    _show(_rounds[++_round], 0, const {});
  }

  /// Runs [save] unless an answer is still saving: a double tap answers once.
  Future<void> _once(Future<void> Function() save) async {
    if (_saving) return;
    _saving = true;
    try {
      await save();
    } finally {
      _saving = false;
    }
  }

  int _rtMs(DateTime now) => now.difference(_shownAt).inMilliseconds;

  /// The session's steps so far: the rounds played and this one's.
  List<SessionStep> _sessionSteps(SessionPlaying p) => [..._played, ...p.steps];

  /// The intro was read: the street becomes a learning card; a leech comes
  /// back with the player's [note] (SPEC §4).
  Future<void> introDone({String? note}) => _once(() => _introDone(note));

  Future<void> _introDone(String? note) async {
    final p = state;
    if (p is! SessionPlaying || p.step.kind != StepKind.intro) return;
    final now = _now();
    final card = switch (_cards[p.step.itemId]) {
      final leech? when leech.phase == CardPhase.suspended => reintroduce(
        leech,
        now,
        note: _noteOf(note),
      ),
      final carded? => carded,
      null => introduce(p.step.itemId, now),
    };
    _cards[card.itemId] = card;
    _times.add(now);
    if (card.type == CardType.p) _introsDone++;
    final dao = _dao;
    await dao.putCard(card);
    if (!ref.mounted) return;
    _show(p.steps, p.index + 1, p.forgotten);
  }

  static String? _noteOf(String? typed) {
    final note = typed?.trim() ?? '';
    return note.isEmpty ? null : note;
  }

  /// A tap on the map: the pin, or one of the two ends.
  void dropPin(LatLng at) {
    final p = state;
    if (p is! SessionPlaying || p.answered) return;
    if (p.task case ExtentTask(:final pins)) {
      state = p.copyWith(task: ExtentTask(pins: _withEnd(pins, at)));
    } else {
      state = p.copyWith(pin: () => at);
    }
  }

  /// A third tap moves the nearer of the two ends.
  static List<LatLng> _withEnd(List<LatLng> pins, LatLng at) {
    if (pins.length < 2) return [...pins, at];
    final nearFirst =
        distanceBetween(pins[0], at) <= distanceBetween(pins[1], at);
    return nearFirst ? [at, pins[1]] : [pins[0], at];
  }

  /// Grades the pin (or both ends), saves the answer and shows the reveal.
  Future<void> confirm() => _once(_confirm);

  Future<void> _confirm() async {
    final p = state;
    if (p is! SessionPlaying || p.answered) return;
    if (p.task is ExtentTask) return _confirmEnds(p);
    final pin = p.pin;
    if (pin == null) return;
    final now = _now();
    final rtMs = _rtMs(now);
    final step = p.step;
    final target = p.street;
    final grade = Grader.gradePin(
      pin: pin,
      target: target,
      nearby: _all,
      confusable: _confusable(target),
      rtMs: rtMs,
      priorSuccesses: _successes[step.itemId] ?? 0,
    );
    if (p.guess != null) {
      await _saveGuess(step.itemId, grade, now, rtMs);
      if (!ref.mounted) return;
      _show(p.steps, p.index, p.forgotten, guessed: true);
      return;
    }
    if (step.kind == StepKind.placement) {
      await _place(p, grade, pin, now, rtMs);
      return;
    }
    final hit = grade.isMixUp ? _streets[grade.snapStreetId] : null;
    final card = await _review(
      step,
      grade.rating,
      tier: grade.tier,
      format: step.kind.format,
      distanceM: grade.distanceM,
      snapId: grade.snapStreetId,
      rtMs: rtMs,
      mixUp: hit,
    );
    if (card == null) return;
    final (answered, days) = _reviewed(p, card);
    state = answered.copyWith(
      reveal: (
        grade: grade,
        pin: pin,
        nearest: target.nearest(pin).nearestPoint,
        nextReviewDays: days,
        hit: hit,
      ),
    );
  }

  Future<void> _confirmEnds(SessionPlaying p, {bool notKnown = false}) async {
    final task = p.task as ExtentTask;
    if (!notKnown && task.pins.length < 2) return;
    final grade = notKnown
        ? Grader.extentNotKnown(p.street)
        : Grader.gradeExtent(
            pins: (task.pins[0], task.pins[1]),
            street: p.street,
          );
    final card = await _review(
      p.step,
      grade.rating,
      tier: grade.tier,
      format: ReviewFormat.extent,
    );
    if (card == null) return;
    final (answered, days) = _reviewed(p, card);
    state = answered.copyWith(
      task: ExtentTask(
        pins: notKnown ? const [] : task.pins,
        grade: grade,
        nextReviewDays: days,
      ),
    );
  }

  /// Name it: Show name.
  /// Name it: the pick among the six names (SPEC §5.2, §16.13).
  Future<void> pickName(NamedStreet picked) => _once(() => _pickName(picked));

  /// [picked] null: "I don't know".
  Future<void> _pickName(NamedStreet? picked) async {
    final p = state;
    if (p is! SessionPlaying || p.answered) return;
    if (p.task case final NameTask t) {
      final right = picked == p.street;
      final card = await _review(
        p.step,
        picked == null ? Grader.notKnown : Grader.gradeName(knew: right),
        tier: right ? Tier.great : Tier.miss,
        format: ReviewFormat.nameCheck,
        mixUp: right ? null : picked,
      );
      if (card == null) return;
      final (answered, days) = _reviewed(p, card);
      state = answered.copyWith(
        task: t.copyWith(picked: picked, right: right, nextReviewDays: days),
      );
    }
  }

  /// Family sweep: [label]'s street dropped on [lane]; a label already on
  /// that lane goes back to the tray.
  void placeLane(String label, String lane) {
    final p = state;
    if (p is! SessionPlaying) return;
    if (p.task case final SweepTask t when !t.checked) {
      state = p.copyWith(
        task: t.copyWith(
          placed: {
            for (final MapEntry(:key, :value) in t.placed.entries)
              if (key != label && value != lane) key: value,
            label: lane,
          },
        ),
      );
    }
  }

  /// Family sweep: Check. Each label grades its lane's P card: on its own
  /// lane Good, else Again and a mixed-up pair (SPEC §7).
  Future<void> checkSweep() => _once(_checkSweep);

  /// [notKnown]: nothing placed counts, so every lane is Again.
  Future<void> _checkSweep({bool notKnown = false}) async {
    final p = state;
    if (p is! SessionPlaying || p.task is! SweepTask) return;
    final asked = p.task as SweepTask;
    if (asked.checked ||
        (!notKnown && asked.placed.length < asked.lanes.length)) {
      return;
    }
    final task = notKnown ? asked.copyWith(placed: const {}) : asked;
    final now = _now();
    final dao = _dao;
    final markDay = dayMarker(ref, reviews: _reviews);
    final answers = [
      for (final lane in task.lanes)
        if (task.placed[lane.id] case final on)
          (
            lane: lane,
            right: on == lane.id,
            mixUp: on == lane.id ? null : _streets[on],
            step: (kind: StepKind.familySweep, itemId: _cardOf(lane).itemId),
          ),
    ];
    final applied = [
      for (final a in answers)
        _apply(
          a.step,
          a.right ? Rating.good : Rating.again,
          format: ReviewFormat.familySweep,
          now: now,
          target: a.lane,
        ),
    ];
    // Every lane or none: a sweep is one answer.
    await dao.transaction(() async {
      for (final (i, a) in answers.indexed) {
        await dao.saveAnswer(
          card: applied[i].card,
          log: applied[i].log,
          mixUp: _pairOf(a.lane, a.mixUp),
        );
      }
    });
    await markDay();
    if (!ref.mounted) return;
    for (final (i, a) in answers.indexed) {
      _keep(
        a.step,
        applied[i].card,
        a.right ? Rating.good : Rating.again,
        a.right ? Tier.great : Tier.miss,
        target: a.lane,
        mixUp: a.mixUp,
        now: now,
      );
    }
    final relearn = [
      for (final r in applied)
        if (r.card.phase == CardPhase.relearning) r.card.itemId,
    ];
    state = _answered(p, relearn).copyWith(task: task.copyWith(checked: true));
  }

  /// Crossings drill: the name typed for the next crossing. A name that is
  /// another street's saves the pair; nothing is scheduled (SPEC §7).
  Future<void> nameCrossing(String typed) => _once(() => _nameCrossing(typed));

  Future<void> _nameCrossing(String typed) async {
    final p = state;
    if (p is! SessionPlaying || p.task is! CrossingsTask) return;
    final task = p.task as CrossingsTask;
    if (task.done) return;
    final expected = task.crossings[task.named.length].street;
    final right = nameMatches(typed, expected);
    final named = right ? null : suggestStreet(typed, _all);
    await _logOnly(
      _cardOf(expected).itemId,
      right ? Rating.good : Rating.again,
      ReviewFormat.crossings,
      mixUp: named != null && named != expected && nameMatches(typed, named)
          ? (expected, named)
          : null,
    );
    if (!ref.mounted) return;
    _answers.add((
      kind: StepKind.crossings,
      rating: right ? Rating.good : Rating.again,
      tier: right ? Tier.great : Tier.miss,
      streetId: expected.id,
      mixUp: null,
    ));
    state = p.copyWith(
      task: CrossingsTask(
        from: task.from,
        start: task.start,
        crossings: task.crossings,
        named: [...task.named, right],
      ),
    );
  }

  /// Bearing: the arrow turned to [degrees].
  void turn(double degrees) {
    final p = state;
    if (p is! SessionPlaying) return;
    if (p.task case final BearingTask t when !t.checked) {
      state = p.copyWith(task: t.copyWith(bearing: degrees));
    }
  }

  /// Bearing: Check; only logged (SPEC §7).
  Future<void> checkBearing() => _once(_checkBearing);

  Future<void> _checkBearing({bool notKnown = false}) async {
    final p = state;
    if (p is! SessionPlaying || p.task is! BearingTask) return;
    if ((p.task as BearingTask).checked) return;
    final task = (p.task as BearingTask).copyWith(
      checked: true,
      notKnown: notKnown,
    );
    await _logOnly(
      _cardOf(p.street).itemId,
      Grader.ratingOfTier(task.result!),
      ReviewFormat.bearing,
    );
    if (!ref.mounted) return;
    state = p.copyWith(task: task);
  }

  /// Applies [rating] to [step]'s card, saves it with its log row (and a
  /// mixed-up pair with [mixUp]) and counts the day; the new card, or null
  /// once the session is gone.
  Future<CardState?> _review(
    SessionStep step,
    Rating rating, {
    required Tier tier,
    required ReviewFormat format,
    double? distanceM,
    String? snapId,
    int? rtMs,
    NamedStreet? mixUp,
    NamedStreet? street,
    bool countDay = true,
  }) async {
    final now = _now();
    final markDay = dayMarker(ref, reviews: _reviews);
    final target = street ?? _streets[itemKey(step.itemId)]!;
    final result = _apply(
      step,
      rating,
      format: format,
      now: now,
      target: target,
      distanceM: distanceM,
      snapId: snapId,
      rtMs: rtMs,
    );
    final dao = _dao;
    await dao.saveAnswer(
      card: result.card,
      log: result.log,
      mixUp: _pairOf(target, mixUp),
    );
    if (!ref.mounted) {
      if (countDay) await markDay();
      return null;
    }
    _keep(
      step,
      result.card,
      rating,
      tier,
      target: target,
      mixUp: mixUp,
      now: now,
    );
    if (countDay) await markDay();
    return ref.mounted ? result.card : null;
  }

  /// [rating] applied to [step]'s card at [now]: its new state and log row.
  ({CardState card, LogEntry log}) _apply(
    SessionStep step,
    Rating rating, {
    required ReviewFormat format,
    required DateTime now,
    required NamedStreet target,
    double? distanceM,
    String? snapId,
    int? rtMs,
  }) => applyReview(
    _cards[step.itemId],
    itemId: step.itemId,
    rating: rating,
    now: now,
    format: format,
    source: ReviewSource.session,
    sessionId: _sessionId,
    distanceM: distanceM,
    snapId: snapId,
    rtMs: rtMs ?? _rtMs(now),
    retention: retentionOf(
      CardType.ofItem(step.itemId),
      tierCRelieved:
          _tierCRelief && _curriculum.tierOf(target.id) == StreetTier.c,
    ),
  );

  static ({String target, String hit})? _pairOf(
    NamedStreet target,
    NamedStreet? mixUp,
  ) => mixUp == null ? null : (target: target.id, hit: mixUp.id);

  /// A saved answer's [card] kept for the rest of the session, and the answer counted.
  void _keep(
    SessionStep step,
    CardState card,
    Rating rating,
    Tier tier, {
    required NamedStreet target,
    required NamedStreet? mixUp,
    required DateTime now,
  }) {
    _cards[step.itemId] = card;
    if (rating.isSuccess && CardType.ofItem(step.itemId) == CardType.p) {
      _successes.update(step.itemId, (n) => n + 1, ifAbsent: () => 1);
    }
    if (mixUp != null) _confusions.add((target.id, mixUp.id));
    _answers.add((
      kind: step.kind,
      rating: rating,
      tier: tier,
      streetId: target.id,
      mixUp: mixUp?.id,
    ));
    _times.add(now);
  }

  /// Logs a drill answer that moves no card.
  Future<void> _logOnly(
    String itemId,
    Rating rating,
    ReviewFormat format, {
    (NamedStreet, NamedStreet)? mixUp,
  }) async {
    final now = _now();
    final markDay = dayMarker(ref, reviews: _reviews);
    _times.add(now);
    await _dao.saveAnswer(
      log: LogEntry(
        ts: now,
        itemId: itemId,
        format: format,
        rating: rating,
        source: ReviewSource.session,
        rtMs: _rtMs(now),
        sessionId: _sessionId,
      ),
      mixUp: mixUp == null ? null : (target: mixUp.$1.id, hit: mixUp.$2.id),
    );
    if (mixUp != null) _confusions.add((mixUp.$1.id, mixUp.$2.id));
    _shownAt = now;
    await markDay();
  }

  /// [p] with a relearn for each of [forgotten] 5–10 items on, and its
  /// session bar block marked when any.
  SessionPlaying _answered(SessionPlaying p, List<String> forgotten) {
    final rest = Planner.withRelearns(
      p.steps.sublist(p.index + 1),
      forgotten,
      session: _sessionSteps(p),
      seed: _seed + p.index,
    );
    final missed =
        forgotten.isNotEmpty || _answers.lastOrNull?.rating == Rating.again;
    return p.copyWith(
      steps: [...p.steps.take(p.index + 1), ...rest],
      forgotten: missed ? {...p.forgotten, p.index} : p.forgotten,
      suspended: _cards[p.step.itemId]?.phase == CardPhase.suspended,
    );
  }

  /// [p] answered with its step's new [card]: a relearn after a miss, and the
  /// days to the next review (null: back in this session).
  /// Counted from the review itself: a clock read after the saves would cut a day short.
  (SessionPlaying, int?) _reviewed(SessionPlaying p, CardState card) => (
    _answered(p, [if (card.phase == CardPhase.relearning) p.step.itemId]),
    Planner.nextReviewDays(
      card,
      card.memory?.lastReview ?? _now(),
      _sessionSteps(p),
    ),
  );

  /// [street]'s P card as stored, or the item it would get.
  CardState _cardOf(NamedStreet street) => _cards.values.firstWhere(
    (c) => c.type == CardType.p && _streets[itemKey(c.itemId)] == street,
    orElse: () =>
        CardState(itemId: CardType.p.item(street.id), phase: CardPhase.review),
  );

  Set<String> _confusable(NamedStreet target) => confusablesOf(
    target,
    _all,
    _confusions,
    family: _curriculum.familyOf(target.id),
  );

  /// A placement pin (SPEC §6.2): Good or Easy at first sight makes a review
  /// card known from before; anything else is logged and the street stays
  /// unseen. No relearn, no confused pair.
  Future<void> _place(
    SessionPlaying p,
    PinGrade grade,
    LatLng pin,
    DateTime now,
    int rtMs,
  ) async {
    final step = p.step;
    final placed = Placement.passes(grade.rating);
    final result = applyReview(
      null,
      itemId: step.itemId,
      rating: grade.rating,
      now: now,
      format: ReviewFormat.placement,
      source: ReviewSource.placement,
      sessionId: _sessionId,
      distanceM: grade.distanceM,
      snapId: grade.snapStreetId,
      rtMs: rtMs,
      priorKnown: true,
    );
    final markDay = dayMarker(ref, reviews: _reviews);
    await _dao.saveAnswer(card: placed ? result.card : null, log: result.log);
    await markDay();
    if (!ref.mounted) return;
    if (placed) _cards[step.itemId] = result.card;
    _times.add(now);
    state = p.copyWith(
      steps: _withSweep(p, grade.rating),
      forgotten: grade.rating == Rating.again
          ? {...p.forgotten, p.index}
          : p.forgotten,
      reveal: (
        grade: grade,
        pin: pin,
        nearest: p.street.nearest(pin).nearestPoint,
        nextReviewDays: placed
            ? result.card.dueAt!.difference(now).inDays
            : null,
        hit: null,
      ),
    );
  }

  /// "I don't know this one": the street stays unseen, nothing is logged.
  void skip() {
    final p = state;
    // Not while a Confirm saves: its reveal would land on the next question.
    if (_saving ||
        p is! SessionPlaying ||
        p.reveal != null ||
        p.step.kind != StepKind.placement) {
      return;
    }
    _show(_withSweep(p, null), p.index + 1, p.forgotten);
  }

  /// "I don't know" on any asked step (SPEC §16.24 item 136): a miss, rated Again, with no
  /// pin, pick or mixed-up pair, and the answer shown at once. A guess first only shows the
  /// street; placement keeps its own [skip].
  Future<void> dontKnow() async {
    final p = state;
    if (p is! SessionPlaying || p.answered) return;
    if (p.step.kind == StepKind.placement) return skip();
    switch (p.task) {
      case PinTask() when p.guess != null:
        await _once(() async {
          await _saveGuess(p.step.itemId, null, _now(), _rtMs(_now()));
          if (ref.mounted) _show(p.steps, p.index, p.forgotten, guessed: true);
        });
      case PinTask():
        await _once(() async {
          final card = await _review(
            p.step,
            Grader.notKnown,
            tier: Tier.miss,
            format: p.step.kind.format,
          );
          if (card == null) return;
          final (answered, days) = _reviewed(p, card);
          state = answered.copyWith(
            pin: () => null,
            reveal: (
              grade: null,
              pin: null,
              nearest: null,
              nextReviewDays: days,
              hit: null,
            ),
          );
        });
      case ExtentTask():
        await _once(() => _confirmEnds(p, notKnown: true));
      case NameTask():
        await _once(() => _pickName(null));
      case RouteTask():
        await _once(() => _answerRoute('', notKnown: true));
      case RecitalTask():
        await _once(() => _checkRecital(notKnown: true));
      case SweepTask():
        await _once(() => _checkSweep(notKnown: true));
      case CrossingsTask():
        await _once(() => _nameCrossing(''));
      case BearingTask():
        await _once(() => _checkBearing(notKnown: true));
    }
  }

  /// [p]'s steps with the sweep its answer earned right after it.
  List<SessionStep> _withSweep(SessionPlaying p, Rating? rating) {
    final sweep = _placement!.answer(p.street.id, rating);
    return [
      ...p.steps.take(p.index + 1),
      for (final id in sweep)
        (kind: StepKind.placement, itemId: CardType.p.item(id)),
      ...p.steps.skip(p.index + 1),
    ];
  }

  /// A guess is logged as a pretest: no card, no confused pair.
  /// A guess first ([grade] null: "I don't know"), logged as a pretest only.
  Future<void> _saveGuess(
    String itemId,
    PinGrade? grade,
    DateTime now,
    int rtMs,
  ) {
    _times.add(now);
    return _dao.saveAnswer(
      log: LogEntry(
        ts: now,
        itemId: itemId,
        format: ReviewFormat.pretest,
        rating: grade?.rating ?? Grader.notKnown,
        source: ReviewSource.session,
        distanceM: grade?.distanceM,
        snapId: grade?.snapStreetId,
        rtMs: rtMs,
        sessionId: _sessionId,
      ),
    );
  }

  /// After the answer: the next step, or the summary.
  void next() {
    final p = state;
    if (p is SessionPlaying && p.answered) {
      _show(p.steps, p.index + 1, p.forgotten);
    }
  }

  void _show(
    List<SessionStep> steps,
    int index,
    Set<int> forgotten, {
    bool guessed = false,
  }) {
    var i = index;
    // A street that left the pack, or a drill that lost its streets, is
    // skipped.
    NamedStreet? shown;
    SessionTask? task;
    while (i < steps.length) {
      shown = _stepStreet(steps[i]);
      task = shown == null ? null : _taskFor(steps[i], shown);
      if (task != null) break;
      i++;
    }
    if (i >= steps.length || task == null || shown == null) {
      if (_placement case final run?) {
        unawaited(_placed(run));
      } else {
        _played = [..._played, ...steps];
        state = SessionDone(_summary());
      }
      return;
    }
    final step = steps[i];
    final street = shown;
    final now = _now();
    _shownAt = now;
    final intros = [
      for (final s in steps)
        if (s.kind == StepKind.intro &&
            CardType.ofItem(s.itemId) == CardType.ofItem(step.itemId))
          s,
    ];
    final city = _pack.city();
    final known = _knownStreets(now)..remove(street);
    final family = _curriculum.familyOf(street.id);
    final parent = _streets[_curriculum.parentOf(street.id)];
    final leech = switch (_cards[step.itemId]) {
      final card?
          when step.kind == StepKind.intro &&
              card.phase == CardPhase.suspended =>
        card,
      _ => null,
    };
    final guess =
        step.kind == StepKind.intro &&
            leech == null &&
            !guessed &&
            known.contains(parent)
        ? (
            parent: parent!,
            knownSiblings: known
                .where((s) => s != parent && family.contains(s.id))
                .length,
          )
        : null;
    state = SessionPlaying(
      steps: steps,
      index: i,
      forgotten: forgotten,
      street: street,
      area: (bbox: city.bbox, boundary: city.boundary),
      knownNames: {for (final s in known) s.name},
      newIndex: intros.indexOf(step) + 1,
      newTotal: intros.length,
      task: task,
      family: _familyOf(street),
      guess: guess,
      frame: switch (task) {
        NameTask() => street.geometry.expand((l) => l).toList(),
        SweepTask(:final lanes) => [
          for (final s in [street, ...lanes]) ...s.geometry.expand((l) => l),
        ],
        CrossingsTask() => street.geometry.expand((l) => l).toList(),
        RouteTask(:final question) => _routeFrame(question),
        _ when step.kind == StepKind.retrieval1 || guess != null =>
          _districtFrame(street),
        _ => null,
      },
      contrast: leech == null ? null : _contrasts[step.itemId],
      note: leech?.note,
      leech: leech != null,
    );
  }

  /// What [step] asks of [street]; null for a drill whose streets are gone.
  SessionTask? _taskFor(SessionStep step, NamedStreet street) =>
      switch (step.kind) {
        StepKind.familySweep => switch ([
          for (final id in _drills.sweep?.children ?? const <String>[])
            ?_streets[itemKey(id)],
        ]) {
          final lanes when lanes.length >= 2 => SweepTask(lanes: lanes),
          _ => null,
        },
        StepKind.crossings => _crossingsTask(street),
        StepKind.bearing => BearingTask(
          trueBearing: bearingDegrees(
            _curriculum.centre,
            street.parts.first.midpoint,
          ),
          distanceM: distanceBetween(
            _curriculum.centre,
            street.parts.first.midpoint,
          ),
        ),
        _ when step.kind == StepKind.intro && !isRouteItem(step.itemId) =>
          const PinTask(),
        _ when CardType.ofItem(step.itemId) == CardType.r => _recitalTask(
          step.itemId,
        ),
        _ when _routes.questions[step.itemId] != null => RouteTask(
          _routes.questions[step.itemId]!,
        ),
        _ => switch (CardType.ofItem(step.itemId)) {
          CardType.n => NameTask(
            choices: nameChoices(
              target: street,
              streets: _all,
              confusable: _confusable(street),
              random: Random(
                _seed + stableSeed('${step.kind.name}:${step.itemId}'),
              ),
            ),
          ),
          CardType.e => const ExtentTask(),
          _ => const PinTask(),
        },
      };

  /// The street a step's plate names: its own, or a route card's street.
  NamedStreet? _stepStreet(SessionStep step) =>
      _streets[itemKey(step.itemId)] ??
      switch (_routes.questions[step.itemId]) {
        final TurnQuestion q => q.approachStreet ?? q.exitStreet,
        final GatewayQuestion q => q.exitStreet ?? _nearest(q.at),
        final BridgeQuestion q => q.approachStreet ?? _nearest(q.at),
        final ConnectionQuestion q => q.street,
        final LandmarkQuestion q =>
          q.street ?? q.approachStreet ?? _nearest(q.landmark.at),
        null => _recitalTask(step.itemId)?.fromStreet,
      };

  /// R item [itemId]'s recital: its run's ends in this pack, A's and B's
  /// streets from the best route between them; null when the run or a
  /// legal route is gone.
  RecitalTask? _recitalTask(String itemId) => _recitals.putIfAbsent(itemId, () {
    final run = _runs[itemKey(itemId)];
    final graph = _graph;
    final ends = run == null || graph == null
        ? null
        : runEnds(run, graph, _byNode, _streets);
    return ends == null
        ? null
        : RecitalTask(
            run!,
            from: ends.from,
            to: ends.to,
            fromStreet: ends.fromStreet,
            toStreet: ends.toStreet,
            draft: RouteDraft(graph!, ends.from, {ends.to}),
          );
  });

  void _recital(RecitalTask Function(RecitalTask t) change) {
    final p = state;
    if (p is! SessionPlaying || p.answered) return;
    if (p.task case final RecitalTask t) state = p.copyWith(task: change(t));
  }

  void recitalMode(RecitalMode mode) => _recital((t) => t.copyWith(mode: mode));

  /// The turn for the next typed step; again to unpick it.
  void recitalTurn(Turn turn) =>
      _recital((t) => t.copyWith(turn: () => t.turn == turn ? null : turn));

  /// Adds the next typed step: the [suggested] street (a hint, SPEC §5.3
  /// step 5) or the street or landmark [typed] names. False when it names
  /// none.
  bool recitalAdd(String typed, {NamedStreet? suggested}) {
    final p = state;
    if (p is! SessionPlaying || p.task is! RecitalTask) return false;
    final t = p.task as RecitalTask;
    final step = suggested != null
        ? (turn: null, street: suggested, landmark: null)
        : resolveRecital(
            tokenizeRecital(typed),
            streets: _all,
            landmarks: {
              for (final q in _routes.questions.values)
                if (q is LandmarkQuestion) q.landmark.id: q.landmark,
            }.values,
            from: t.steps.lastOrNull?.street ?? t.fromStreet,
          ).firstOrNull;
    if (step == null) return false;
    _recital(
      (t) => t.copyWith(
        steps: [
          ...t.steps,
          (
            turn: t.turn ?? step.turn,
            street: step.street,
            landmark: step.landmark,
          ),
        ],
        turn: () => null,
        hinted: t.hinted || suggested != null,
      ),
    );
    return true;
  }

  void recitalUndo() => _recital(
    (t) => t.copyWith(steps: t.steps.take(t.steps.length - 1).toList()),
  );

  void recitalDraw(RouteDraft draft) =>
      _recital((t) => t.copyWith(draft: draft));

  /// Check my route (SPEC §5.3): grades the typed steps or the drawn route,
  /// reviews the R card, logs every decision as evidence, reviews the
  /// near-due J cards it failed (§4) and adds those J cards to this session.
  Future<void> checkRecital() => _once(_checkRecital);

  /// [notKnown]: a Miss with the best route, and no decision hears of it.
  Future<void> _checkRecital({bool notKnown = false}) async {
    final p = state;
    if (p is! SessionPlaying || p.answered) return;
    if (p.task case final RecitalTask t) {
      final graph = _graph!;
      final graded = switch (t.mode) {
        _ when notKnown => RecitalGrader.notKnown(
          graph,
          from: t.from,
          to: t.to,
        ),
        RecitalMode.type => RecitalGrader.grade(
          graph,
          t.steps,
          from: t.from,
          to: t.to,
          streets: _streets,
          hinted: t.hinted,
        ),
        RecitalMode.draw => RecitalGrader.score(
          graph,
          Route(t.draft.junctions, t.draft.edges, t.draft.lengthM),
          from: t.from,
          to: t.to,
          streets: _streets,
        ),
      };
      final now = _now();
      final (:answer, :evidence, :reviews, :practice) = recitalOutcome(
        graded,
        itemId: p.step.itemId,
        cards: _cards,
        junctionNodes: _nodes,
        routeItems: _routes.questions.keys,
        now: now,
        sessionId: _sessionId,
        rtMs: _rtMs(now),
      );
      final markDay = dayMarker(ref, reviews: _reviews);
      await _dao.saveTest(
        log: answer.log,
        card: answer.card,
        source: ReviewSource.recital,
        at: now,
        evidence: evidence,
        reviews: reviews,
      );
      if (!ref.mounted) return markDay();
      _cards[p.step.itemId] = answer.card;
      for (final r in reviews) {
        _cards[r.card.itemId] = r.card;
      }
      _answers.add((
        kind: p.step.kind,
        rating: graded.rating,
        tier: graded.tier,
        streetId: t.fromStreet.id,
        mixUp: null,
      ));
      _times.add(now);
      await markDay();
      if (!ref.mounted) return;
      state = _answered(p, practice).copyWith(
        task: t.copyWith(
          graded: graded,
          practice: practice,
          // A recital isn't relearned in the session, so it shows its days.
          nextReviewDays: answer.card.dueAt!.difference(now).inDays,
        ),
      );
    }
  }

  /// "Wrong? Report this turn" (SPEC §15): the recital's illegal move is
  /// legal on this phone from now on.
  Future<void> reportMove() async {
    final p = state;
    if (p is! SessionPlaying) return;
    if (p.task case RecitalTask(
      :final graded?,
      reported: false,
    ) when graded.illegal != null && graded.path != null) {
      await _dao.reportMove(moveReport(graded.illegal!, _nodes), _now());
      ref.invalidate(drivingGraphProvider);
      if (!ref.mounted) return;
      final now = state;
      if (now is SessionPlaying && now.task is RecitalTask) {
        state = now.copyWith(
          task: (now.task as RecitalTask).copyWith(reported: true),
        );
      }
    }
  }

  /// "Can't find it?" (SPEC §16.18 item 94): the shown pack place is hidden
  /// on this phone, and its cards leave the session.
  // ponytail: a turn card later this session may still name it; the next
  // session's route book doesn't.
  Future<void> hidePlace() => _once(_hidePlace);

  Future<void> _hidePlace() async {
    final p = state;
    if (p is! SessionPlaying) return;
    if (p.task case RouteTask(
      question: LandmarkQuestion(:final landmark),
    ) when !landmark.personal) {
      await _dao.hidePlace(landmark.id, _now());
      ref.invalidate(routeBookProvider);
      if (!ref.mounted) return;
      _routes = (
        candidates: _routes.candidates,
        questions: Map.of(_routes.questions)
          ..removeWhere(
            (_, q) => q is LandmarkQuestion && q.landmark.id == landmark.id,
          ),
      );
      if (state case final SessionPlaying now when now.index == p.index) {
        _show(now.steps, now.index + 1, now.forgotten);
      }
    }
  }

  NamedStreet? _nearest(LatLng at) {
    NamedStreet? best;
    var bestM = double.infinity;
    for (final s in _all) {
      final m = distanceBetween(at, s.parts.first.midpoint);
      if (m < bestM) (best, bestM) = (s, m);
    }
    return best;
  }

  /// What a route card's map frames: a gateway's neighbourhood, a bridge
  /// question's bridges and start; the city otherwise.
  List<LatLng>? _routeFrame(RouteQuestion q) => switch (q) {
    GatewayQuestion(:final chunk) => switch (_pack
        .districts()
        .where((d) => d.id == chunk)
        .firstOrNull
        ?.bbox) {
      final b? => b.diagonal,
      null => null,
    },
    BridgeQuestion(:final at, :final options) => [
      at,
      for (final b in options) b.midpoint,
    ],
    _ => null,
  };

  /// A route card: picks the turn, bridge, junction or name before Confirm.
  void choose(Object choice) {
    final p = state;
    if (p is! SessionPlaying || p.answered) return;
    if (p.task case final RouteTask t) {
      state = p.copyWith(task: t.copyWith(choice: () => choice));
    }
  }

  /// A route card's Confirm (SPEC §5.2): grades the choice, the pin and the
  /// [typed] street, saves the answer and shows the result.
  Future<void> answerRoute({String typed = ''}) =>
      _once(() => _answerRoute(typed));

  /// [notKnown]: Again whatever was picked, typed or pinned.
  Future<void> _answerRoute(String typed, {bool notKnown = false}) async {
    final p = state;
    if (p is! SessionPlaying || p.answered) return;
    if (p.task case final RouteTask t) {
      final rating = notKnown
          ? Grader.notKnown
          : t.question.rate(
              choice: t.choice,
              pin: p.pin,
              typed: typed,
              known: _knownStreets(_now()),
            );
      if (rating == null) return;
      final card = await _review(
        p.step,
        rating,
        tier: RouteGrader.tierOf(rating),
        format: t.question.format,
        street: p.street,
      );
      if (card == null) return;
      final (answered, days) = _reviewed(p, card);
      state = answered.copyWith(
        pin: notKnown ? () => null : null,
        task: t.copyWith(
          choice: notKnown ? () => null : null,
          rating: rating,
          nextReviewDays: days,
        ),
      );
    }
  }

  /// The streets whose P card is Known at [now].
  Set<NamedStreet> _knownStreets(DateTime now) => {
    for (final c in _cards.values)
      if (c.type == CardType.p && isKnown(c, now)) ?_streets[itemKey(c.itemId)],
  };

  CrossingsTask? _crossingsTask(NamedStreet street) {
    final drill = _drills.crossings;
    final from = _streets[drill?.fromId];
    if (drill == null || from == null) return null;
    final along = {
      for (final c in crossingsAlong(street, _all)) c.street.id: c,
    };
    final crossings = [
      for (final id in drill.crossings) ?along[_streets[id]?.id],
    ];
    final start = along[from.id]?.at;
    return crossings.isEmpty || start == null
        ? null
        : CrossingsTask(from: from, start: start, crossings: crossings);
  }

  SessionFamily? _familyOf(NamedStreet street) {
    final chip = _curriculum.familyChip(street.id);
    final parent = _streets[chip?.parentId];
    return chip == null || parent == null
        ? null
        : (parent: parent, children: chip.children);
  }

  /// The bounds of the raion holding most of [street]'s length.
  List<LatLng>? _districtFrame(NamedStreet street) {
    final parts = {for (final p in street.parts) p.id};
    final raions = {
      for (final d in _pack.districts())
        if (d.isRaion) d.id: d,
    };
    String? best;
    var bestM = 0.0;
    for (final MapEntry(key: id, value: lengths)
        in _pack.lengthsByDistrict().entries) {
      if (!raions.containsKey(id)) continue;
      final m = lengths.entries
          .where((e) => parts.contains(e.key))
          .fold(0.0, (sum, e) => sum + e.value);
      if (m > bestM) (best, bestM) = (id, m);
    }
    return raions[best]?.bbox.diagonal;
  }

  double _memory(DateTime now) => cityMemory(
    _cards.values,
    now,
    isCore: (id) => switch (_streets[itemKey(id)]) {
      final s? => Curriculum.isCore(s),
      null => false,
    },
  );

  Future<void> _placed(Placement run) async {
    final city = _pack.city();
    await _dao.markPlaced(city.id, _now());
    if (!ref.mounted) return;
    final cards = {
      for (final c in _cards.values)
        if (c.type == CardType.p) ?_streets[itemKey(c.itemId)]?.id: c,
    };
    final band = _curriculum.bandsLeft(cards).firstOrNull;
    final start = _curriculum.chunkSequence(cards, _anchors).firstOrNull;
    state = SessionPlaced((
      passed: run.passed,
      mainRoads: run.mainRoads,
      raions: run.raions,
      startBand: band,
      startIn: band != null
          ? null
          : _pack.districts().where((d) => d.id == start).firstOrNull,
    ));
  }

  SessionSummary _summary() {
    final now = _now();
    final s = summarizeSession(_answers, _times);
    final midnight = nextMidnight(now);
    return (
      reviews: s.reviews,
      newStreets: _introsDone,
      recalledPercent: s.recalledPercent,
      memoryBefore: _memoryBefore,
      memoryAfter: _memory(now),
      mixUps: [
        for (final (id, hit) in s.mixUps)
          if (_streets[hit] case final other?) (_streets[id]!, other),
      ],
      closeTwice: [for (final id in s.closeTwice) _streets[id]!],
      minutes: s.minutes,
      cleared: !_cards.values
          .where(_reviews(_cards.values))
          .any((c) => isDueBefore(c, midnight)),
      round: _round + 1,
      rounds: _rounds.length,
    );
  }
}
