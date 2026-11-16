import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/features/learning/data/day.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/route_book.dart';
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
typedef SessionReveal = ({
  PinGrade grade,
  LatLng pin,
  LatLng nearest,

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
    required this.known,
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

  /// Known streets near this one, named on the intro and the reveal.
  final List<NamedStreet> known;

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
    final r? => r.hit == null ? r.grade.tier : Tier.miss,
    null => task.result,
  };

  SessionPlaying copyWith({
    LatLng? pin,
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
    known: known,
    newIndex: newIndex,
    newTotal: newTotal,
    task: task ?? this.task,
    family: family,
    guess: guess,
    frame: frame,
    pin: pin ?? this.pin,
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

  /// The neighbourhood new streets start in.
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
  late List<(String, String)> _confusions;
  late Map<String, int> _successes;
  late double _memoryBefore;
  late int _seed;
  Drills _drills = Drills.none;
  RouteBook _routes = (
    candidates: const <RouteCandidate>[],
    questions: const <String, RouteQuestion>{},
  );

  /// Name reviews so far, for the every-10th check.
  int _nameReviews = 0;

  /// Each leech's top confusion, read before its intro.
  final Map<String, NamedStreet> _contrasts = {};

  /// Set while placing (SPEC §6.2): the run decides which streets come next.
  Placement? _placement;
  late List<String> _anchors;
  final String _sessionId = const Uuid().v7();
  final List<_Answer> _answers = [];

  /// When each intro and answer happened: the session's minutes.
  final List<DateTime> _times = [];
  int _introsDone = 0;
  DateTime _shownAt = DateTime(0);

  @override
  SessionState build() => const SessionLoading();

  LearningDao get _dao => ref.read(learningDaoProvider);
  DateTime _now() => ref.read(clockProvider)();

  /// The plan's drills, for the screen's estimates.
  Drills get drills => _drills;

  /// Today's session, with [more] "Learn 5 more", or with [placement] the
  /// city's placement.
  Future<void> start({bool placement = false, bool more = false}) async {
    final dao = _dao;
    // The plan disposes when unwatched: hold it while it loads.
    final planSub = placement
        ? null
        : ref.listen(
            (more ? learnMorePlanProvider : todayPlanProvider).future,
            (_, _) {},
          );
    final plan = await planSub?.read();
    planSub?.close();
    final streets = await ref.read(cityStreetsProvider.future);
    final pack = await ref.read(packRepositoryProvider.future);
    final curriculum = await ref.read(curriculumProvider.future);
    final routes = await ref.read(routeBookProvider.future);
    final cards = await dao.cards();
    final confusions = await dao.confusionPairs();
    final log = await dao.log();
    final learnCity = await dao.learnCity(pack.city().id);
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
    final steps =
        plan?.steps ??
        [
          for (final id in _placement!.streets)
            (kind: StepKind.placement, itemId: CardType.p.item(id)),
        ];
    if (steps.isEmpty && !placement) {
      state = const SessionEmpty();
      return;
    }
    _streets = streets;
    _all = streets.values.toSet();
    _pack = pack;
    _curriculum = curriculum;
    _drills = plan?.drills ?? Drills.none;
    _routes = routes;
    _contrasts.addAll(contrasts);
    _cards = {for (final c in cards) c.itemId: c};
    _confusions = [...confusions];
    _successes = {};
    for (final e in log) {
      if (e.type == CardType.p && e.rating.isSuccess && !e.format.logsOnly) {
        _successes.update(e.itemId, (n) => n + 1, ifAbsent: () => 1);
      }
      if (e.type == CardType.n) _nameReviews++;
    }
    _anchors = [?learnCity?.homeId, ?learnCity?.workId];
    _seed = now.microsecondsSinceEpoch;
    _memoryBefore = _memory(now);
    _show(steps, 0, const {});
  }

  /// The intro was read: the street becomes a learning card; a leech comes
  /// back with the player's [note] (SPEC §4).
  Future<void> introDone({String? note}) async {
    final p = state;
    if (p is! SessionPlaying || p.step.kind != StepKind.intro) return;
    final now = _now();
    final leech = _cards[p.step.itemId];
    final card = leech == null
        ? introduce(p.step.itemId, now)
        : reintroduce(leech, now, note: _noteOf(note));
    _cards[card.itemId] = card;
    _times.add(now);
    _introsDone++;
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
      state = p.copyWith(pin: at);
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
  Future<void> confirm() async {
    final p = state;
    if (p is! SessionPlaying || p.answered) return;
    if (p.task is ExtentTask) return _confirmEnds(p);
    final pin = p.pin;
    if (pin == null) return;
    final now = _now();
    final rtMs = now.difference(_shownAt).inMilliseconds;
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
      format: _formatOf(step.kind),
      distanceM: grade.distanceM,
      snapId: grade.snapStreetId,
      rtMs: rtMs,
      mixUp: hit,
    );
    if (card == null) return;
    state = _answered(p, [if (card.phase == CardPhase.relearning) step.itemId])
        .copyWith(
          reveal: (
            grade: grade,
            pin: pin,
            nearest: target.nearest(pin).nearestPoint,
            nextReviewDays: _nextReviewDays(card, now),
            hit: hit,
          ),
        );
  }

  Future<void> _confirmEnds(SessionPlaying p) async {
    final task = p.task as ExtentTask;
    if (task.pins.length < 2) return;
    final grade = Grader.gradeExtent(
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
    state =
        _answered(p, [
          if (card.phase == CardPhase.relearning) p.step.itemId,
        ]).copyWith(
          task: ExtentTask(
            pins: task.pins,
            grade: grade,
            nextReviewDays: _nextReviewDays(card, _now()),
          ),
        );
  }

  /// Name it: Show name.
  void showName() {
    final p = state;
    if (p is! SessionPlaying) return;
    if (p.task case final NameTask t when !t.shown) {
      state = p.copyWith(task: t.copyWith(shown: true));
    }
  }

  /// Name it: Knew it or Forgot (SPEC §5.2); on to the next step.
  Future<void> rateName({required bool knew}) async {
    final p = state;
    if (p is! SessionPlaying || p.task is! NameTask) return;
    final card = await _review(
      p.step,
      Grader.gradeName(knew: knew),
      tier: knew ? Tier.great : Tier.miss,
      format: ReviewFormat.name,
    );
    if (card == null) return;
    _nameReviews++;
    final next = _answered(p, [
      if (card.phase == CardPhase.relearning) p.step.itemId,
    ]);
    _show(next.steps, p.index + 1, next.forgotten);
  }

  /// Name it, checked: the pick among the six names (SPEC §5.2).
  Future<void> pickName(NamedStreet picked) async {
    final p = state;
    if (p is! SessionPlaying || p.answered) return;
    if (p.task case final NameTask t when t.choices != null) {
      final right = picked == p.street;
      final card = await _review(
        p.step,
        Grader.gradeName(knew: right),
        tier: right ? Tier.great : Tier.miss,
        format: ReviewFormat.nameCheck,
        mixUp: right ? null : picked,
      );
      if (card == null) return;
      _nameReviews++;
      state =
          _answered(p, [
            if (card.phase == CardPhase.relearning) p.step.itemId,
          ]).copyWith(
            task: t.copyWith(
              picked: picked,
              right: right,
              nextReviewDays: _nextReviewDays(card, _now()),
            ),
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
  Future<void> checkSweep() async {
    final p = state;
    if (p is! SessionPlaying || p.task is! SweepTask) return;
    final task = p.task as SweepTask;
    if (task.checked || task.placed.length < task.lanes.length) return;
    final relearn = <String>[];
    for (final lane in task.lanes) {
      final on = task.placed[lane.id];
      final right = on == lane.id;
      final step = (kind: StepKind.familySweep, itemId: _cardOf(lane).itemId);
      final card = await _review(
        step,
        right ? Rating.good : Rating.again,
        tier: right ? Tier.great : Tier.miss,
        format: ReviewFormat.familySweep,
        mixUp: right ? null : _streets[on],
      );
      if (card == null) return;
      if (card.phase == CardPhase.relearning) relearn.add(card.itemId);
    }
    state = _answered(p, relearn).copyWith(task: task.copyWith(checked: true));
  }

  /// Crossings drill: the name typed for the next crossing. A name that is
  /// another street's saves the pair; nothing is scheduled (SPEC §7).
  Future<void> nameCrossing(String typed) async {
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
  Future<void> checkBearing() async {
    final p = state;
    if (p is! SessionPlaying || p.task is! BearingTask) return;
    final task = (p.task as BearingTask).copyWith(checked: true);
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
  }) async {
    final now = _now();
    final target = street ?? _streets[itemKey(step.itemId)]!;
    final result = applyReview(
      _cards[step.itemId],
      itemId: step.itemId,
      rating: rating,
      now: now,
      format: format,
      source: ReviewSource.session,
      sessionId: _sessionId,
      distanceM: distanceM,
      snapId: snapId,
      rtMs: rtMs ?? now.difference(_shownAt).inMilliseconds,
    );
    final dao = _dao;
    await dao.saveAnswer(
      card: result.card,
      log: result.log,
      mixUp: mixUp == null ? null : (target: target.id, hit: mixUp.id),
    );
    if (!ref.mounted) return null;
    _cards[step.itemId] = result.card;
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
    await markDayIfCounts(ref);
    return ref.mounted ? result.card : null;
  }

  /// Logs a drill answer that moves no card.
  Future<void> _logOnly(
    String itemId,
    Rating rating,
    ReviewFormat format, {
    (NamedStreet, NamedStreet)? mixUp,
  }) async {
    final now = _now();
    _times.add(now);
    await _dao.saveAnswer(
      log: LogEntry(
        ts: now,
        itemId: itemId,
        format: format,
        rating: rating,
        source: ReviewSource.session,
        rtMs: now.difference(_shownAt).inMilliseconds,
        sessionId: _sessionId,
      ),
      mixUp: mixUp == null ? null : (target: mixUp.$1.id, hit: mixUp.$2.id),
    );
    if (mixUp != null) _confusions.add((mixUp.$1.id, mixUp.$2.id));
    _shownAt = now;
    await markDayIfCounts(ref);
  }

  /// [p] with a relearn for each of [forgotten] 5–10 items on, and its
  /// session bar block marked when any.
  SessionPlaying _answered(SessionPlaying p, List<String> forgotten) {
    var rest = p.steps.sublist(p.index + 1);
    for (final (i, id) in forgotten.indexed) {
      rest = Planner.withRelearn(rest, id, Random(_seed + p.index + i));
    }
    final missed =
        forgotten.isNotEmpty || _answers.lastOrNull?.rating == Rating.again;
    return p.copyWith(
      steps: [...p.steps.take(p.index + 1), ...rest],
      forgotten: missed ? {...p.forgotten, p.index} : p.forgotten,
      suspended: _cards[p.step.itemId]?.phase == CardPhase.suspended,
    );
  }

  /// Days to [card]'s next review; null when it comes back this session.
  static int? _nextReviewDays(CardState card, DateTime now) =>
      card.phase == CardPhase.review
      ? card.dueAt!.difference(now).inDays
      : null;

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
    await _dao.saveAnswer(card: placed ? result.card : null, log: result.log);
    await markDayIfCounts(ref);
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
    if (p is! SessionPlaying ||
        p.reveal != null ||
        p.step.kind != StepKind.placement) {
      return;
    }
    _show(_withSweep(p, null), p.index + 1, p.forgotten);
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
  Future<void> _saveGuess(
    String itemId,
    PinGrade grade,
    DateTime now,
    int rtMs,
  ) {
    _times.add(now);
    return _dao.saveAnswer(
      log: LogEntry(
        ts: now,
        itemId: itemId,
        format: ReviewFormat.pretest,
        rating: grade.rating,
        source: ReviewSource.session,
        distanceM: grade.distanceM,
        snapId: grade.snapStreetId,
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
    SessionTask? task;
    while (i < steps.length) {
      final street = _stepStreet(steps[i]);
      task = street == null ? null : _taskFor(steps[i], street);
      if (task != null) break;
      i++;
    }
    if (i >= steps.length || task == null) {
      if (_placement case final run?) {
        unawaited(_placed(run));
      } else {
        state = SessionDone(_summary());
      }
      return;
    }
    final step = steps[i];
    final street = _stepStreet(step)!;
    final now = _now();
    _shownAt = now;
    final intros = [
      for (final s in steps)
        if (s.kind == StepKind.intro) s,
    ];
    final city = _pack.city();
    final known = {
      for (final c in _cards.values)
        if (c.type == CardType.p && isKnown(c, now))
          ?_streets[itemKey(c.itemId)],
    }..remove(street);
    final family = _curriculum.familyOf(street.id);
    final parent = _streets[_curriculum.parentOf(street.id)];
    final leech = step.kind == StepKind.intro ? _cards[step.itemId] : null;
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
      known: _nearestFirst(street, known, family),
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
        _ when step.kind == StepKind.intro => const PinTask(),
        _ when _routes.questions[step.itemId] != null => RouteTask(
          _routes.questions[step.itemId]!,
        ),
        _ => switch (CardType.ofItem(step.itemId)) {
          CardType.n => NameTask(
            choices: Grader.isNameCheck(_nameReviews)
                ? nameChoices(
                    target: street,
                    streets: _all,
                    confusable: _confusable(street),
                    random: Random(_seed + step.hashCode),
                  )
                : null,
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
        final LandmarkQuestion q => q.approachStreet ?? _nearest(q.landmark.at),
        null => null,
      };

  NamedStreet? _nearest(LatLng at) => _all.fold<NamedStreet?>(
    null,
    (best, s) =>
        best == null ||
            distanceBetween(at, s.parts.first.midpoint) <
                distanceBetween(at, best.parts.first.midpoint)
        ? s
        : best,
  );

  /// What a route card's map frames: a gateway's neighbourhood, a bridge
  /// question's bridges and start; the city otherwise.
  List<LatLng>? _routeFrame(RouteQuestion q) => switch (q) {
    GatewayQuestion(:final chunk) => switch (_pack
        .districts()
        .where((d) => d.id == chunk)
        .firstOrNull
        ?.bbox) {
      final b? => [LatLng(b.minLat, b.minLon), LatLng(b.maxLat, b.maxLon)],
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
      state = p.copyWith(task: t.copyWith(choice: choice));
    }
  }

  /// A route card's Confirm (SPEC §5.2): grades the choice, the pin and the
  /// [typed] street, saves the answer and shows the result.
  Future<void> answerRoute({String typed = ''}) async {
    final p = state;
    if (p is! SessionPlaying || p.answered) return;
    if (p.task case final RouteTask t) {
      final pin = p.pin;
      bool names(NamedStreet? s) =>
          s != null && typed.trim().isNotEmpty && nameMatches(typed, s);
      final (rating, format) = switch (t.question) {
        final TurnQuestion q => (
          RouteGrader.turn(
            exitRight: t.choice == q.correct,
            streetRight: typed.trim().isEmpty ? null : names(q.exitStreet),
            streetAsked: _isKnownStreet(q.exitStreet),
          ),
          ReviewFormat.junction,
        ),
        final GatewayQuestion q when pin != null => (
          RouteGrader.gateway(
            distanceM: distanceBetween(pin, q.at),
            streetRight: names(q.exitStreet),
          ),
          ReviewFormat.gateway,
        ),
        final BridgeQuestion q => (
          t.choice == q.bridge ? Rating.good : Rating.again,
          ReviewFormat.bridge,
        ),
        final ConnectionQuestion q => (
          names(q.to) ? Rating.good : Rating.again,
          ReviewFormat.connection,
        ),
        LandmarkQuestion(n: 1, :final landmark) when pin != null => (
          RouteGrader.point(distanceBetween(pin, landmark.at)).rating,
          ReviewFormat.landmark,
        ),
        final LandmarkQuestion q when q.n > 1 => (
          (q.n == 2 ? t.choice == q.junction : t.choice == q.landmark.name)
              ? Rating.good
              : Rating.again,
          ReviewFormat.landmark,
        ),
        _ => (null, null),
      };
      if (rating == null || format == null) return;
      final card = await _review(
        p.step,
        rating,
        tier: RouteGrader.tierOf(rating),
        format: format,
        street: p.street,
      );
      if (card == null) return;
      state =
          _answered(p, [
            if (card.phase == CardPhase.relearning) p.step.itemId,
          ]).copyWith(
            task: t.copyWith(
              rating: rating,
              nextReviewDays: _nextReviewDays(card, _now()),
            ),
          );
    }
  }

  bool _isKnownStreet(NamedStreet? s) =>
      s != null &&
      _cards.values.any(
        (c) =>
            c.type == CardType.p &&
            _streets[itemKey(c.itemId)] == s &&
            isKnown(c, _now()),
      );

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

  /// Up to [LearningConfig.knownLabelMax] of the [known] streets: [street]'s
  /// [family] first, then the nearest.
  List<NamedStreet> _nearestFirst(
    NamedStreet street,
    Set<NamedStreet> known,
    Set<String> family,
  ) {
    final at = street.parts.first.midpoint;
    double away(NamedStreet s) => family.contains(s.id)
        ? -1
        : distanceBetween(at, s.parts.first.midpoint);
    return (known.toList()..sort((a, b) => away(a).compareTo(away(b))))
        .take(LearningConfig.knownLabelMax)
        .toList();
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
    final b = raions[best]?.bbox;
    return b == null
        ? null
        : [LatLng(b.minLat, b.minLon), LatLng(b.maxLat, b.maxLon)];
  }

  double _memory(DateTime now) => cityMemory(
    _cards.values,
    now,
    isCore: (id) =>
        (_streets[itemKey(id)]?.lengthM ?? 0) >= LearningConfig.coreMinLengthM,
  );

  Future<void> _placed(Placement run) async {
    final city = _pack.city();
    await _dao.markPlaced(city.id, _now());
    if (!ref.mounted) return;
    final cards = {
      for (final c in _cards.values)
        if (c.type == CardType.p) ?_streets[itemKey(c.itemId)]?.id: c,
    };
    final start = _curriculum.chunkSequence(cards, _anchors).firstOrNull;
    state = SessionPlaced((
      passed: run.passed,
      mainRoads: run.mainRoads,
      raions: run.raions,
      startIn: _pack.districts().where((d) => d.id == start).firstOrNull,
    ));
  }

  SessionSummary _summary() {
    final now = _now();
    final graded = [
      for (final a in _answers)
        if (a.kind != StepKind.crossings) a,
    ];
    final passed = graded.where((a) => a.rating.isSuccess).length;
    final closes = <String, int>{};
    for (final a in graded.where((a) => a.tier == Tier.close)) {
      closes.update(a.streetId, (n) => n + 1, ifAbsent: () => 1);
    }
    final midnight = nextMidnight(now);
    return (
      reviews: graded
          .where(
            (a) => a.kind == StepKind.review || a.kind == StepKind.familySweep,
          )
          .length,
      newStreets: _introsDone,
      recalledPercent: graded.isEmpty
          ? 0
          : (100 * passed / graded.length).round(),
      memoryBefore: _memoryBefore,
      memoryAfter: _memory(now),
      mixUps: [
        for (final a in graded)
          if (_streets[a.mixUp] case final hit?) (_streets[a.streetId]!, hit),
      ],
      closeTwice: [
        for (final MapEntry(:key, :value) in closes.entries)
          if (value >= 2) _streets[key]!,
      ],
      minutes: (activeSeconds(_times) / 60).ceil(),
      cleared: !_cards.values.any((c) => isDueBefore(c, midnight)),
    );
  }
}

/// One graded answer of the session, for Session done.
typedef _Answer = ({
  StepKind kind,
  Rating rating,
  Tier tier,
  String streetId,

  /// The street a mix-up confused it with.
  String? mixUp,
});

ReviewFormat _formatOf(StepKind kind) => switch (kind) {
  StepKind.retrieval1 => ReviewFormat.retrieval1,
  StepKind.retrieval2 => ReviewFormat.retrieval2,
  StepKind.relearn => ReviewFormat.relearn,
  StepKind.placement => ReviewFormat.placement,
  _ => ReviewFormat.review,
};
