import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/today_plan.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:uuid/uuid.dart';

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
    this.frame,
    this.pin,
    this.reveal,
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

  /// Retrieval 1 frames the street's district; null frames the city.
  final List<LatLng>? frame;
  final LatLng? pin;
  final SessionReveal? reveal;

  SessionStep get step => steps[index];

  SessionPlaying copyWith({
    LatLng? pin,
    SessionReveal? reveal,
    List<SessionStep>? steps,
    Set<int>? forgotten,
  }) => SessionPlaying(
    steps: steps ?? this.steps,
    index: index,
    forgotten: forgotten ?? this.forgotten,
    street: street,
    area: area,
    known: known,
    newIndex: newIndex,
    newTotal: newTotal,
    frame: frame,
    pin: pin ?? this.pin,
    reveal: reveal ?? this.reveal,
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

/// Plays today's session (docs/learning/SPEC.md §6.4, §7, §16.2): intros,
/// pins graded by pindoro_learning, each answer saved as it comes, relearns
/// slotted in after Again. Leaving keeps everything answered so far.
class SessionController extends Notifier<SessionState> {
  late Map<String, NamedStreet> _streets;
  late Set<NamedStreet> _all;
  late PackRepository _pack;
  late Map<String, CardState> _cards;
  late List<(String, String)> _confusions;
  late Map<String, int> _successes;
  late double _memoryBefore;
  late int _seed;
  final String _sessionId = const Uuid().v7();
  final List<({SessionStep step, PinGrade grade, String streetId})> _answers =
      [];

  /// When each intro and answer happened: the session's minutes.
  final List<DateTime> _times = [];
  int _introsDone = 0;
  DateTime _shownAt = DateTime(0);

  @override
  SessionState build() => const SessionLoading();

  LearningDao get _dao => ref.read(learningDaoProvider);
  DateTime _now() => ref.read(clockProvider)();

  Future<void> start() async {
    final dao = _dao;
    // The plan disposes when unwatched: hold it while it loads.
    final planSub = ref.listen(todayPlanProvider.future, (_, _) {});
    final plan = await planSub.read();
    planSub.close();
    final streets = await ref.read(cityStreetsProvider.future);
    final pack = await ref.read(packRepositoryProvider.future);
    final cards = await dao.cards();
    final confusions = await dao.confusionPairs();
    final log = await dao.log();
    if (!ref.mounted) return;
    if (plan.steps.isEmpty) {
      state = const SessionEmpty();
      return;
    }
    _streets = streets;
    _all = streets.values.toSet();
    _pack = pack;
    _cards = {for (final c in cards) c.itemId: c};
    _confusions = [...confusions];
    _successes = {};
    for (final e in log) {
      if (e.type == CardType.p && e.rating.isSuccess) {
        _successes.update(e.itemId, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final now = _now();
    _seed = now.microsecondsSinceEpoch;
    _memoryBefore = _memory(now);
    _show(plan.steps, 0, const {});
  }

  /// The intro was read: the street becomes a learning card.
  Future<void> introDone() async {
    final p = state;
    if (p is! SessionPlaying || p.step.kind != StepKind.intro) return;
    final now = _now();
    final card = introduce(p.step.itemId, now);
    _cards[card.itemId] = card;
    _times.add(now);
    _introsDone++;
    final dao = _dao;
    await dao.putCard(card);
    if (!ref.mounted) return;
    _show(p.steps, p.index + 1, p.forgotten);
  }

  void dropPin(LatLng at) {
    final p = state;
    if (p is SessionPlaying && p.reveal == null) state = p.copyWith(pin: at);
  }

  /// Grades the pin, saves the answer and shows the reveal.
  Future<void> confirm() async {
    final p = state;
    if (p is! SessionPlaying || p.reveal != null) return;
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
      confusable: confusablesOf(target, _all, _confusions),
      rtMs: rtMs,
      priorSuccesses: _successes[step.itemId] ?? 0,
    );
    final result = applyReview(
      _cards[step.itemId],
      itemId: step.itemId,
      rating: grade.rating,
      now: now,
      format: _formatOf(step.kind),
      source: ReviewSource.session,
      sessionId: _sessionId,
      distanceM: grade.distanceM,
      snapId: grade.snapStreetId,
      rtMs: rtMs,
    );
    final hit = grade.isMixUp ? _streets[grade.snapStreetId] : null;
    final dao = _dao;
    await dao.saveAnswer(
      card: result.card,
      log: result.log,
      mixUp: hit == null ? null : (target: target.id, hit: hit.id),
    );
    if (!ref.mounted) return;
    _cards[step.itemId] = result.card;
    if (grade.rating.isSuccess) {
      _successes.update(step.itemId, (n) => n + 1, ifAbsent: () => 1);
    }
    if (hit != null) _confusions.add((target.id, hit.id));
    _answers.add((step: step, grade: grade, streetId: target.id));
    _times.add(now);

    final forgot = grade.rating == Rating.again;
    final rest = p.steps.sublist(p.index + 1);
    state = p.copyWith(
      steps: forgot
          ? [
              ...p.steps.take(p.index + 1),
              ...Planner.withRelearn(
                rest,
                step.itemId,
                Random(_seed + p.index),
              ),
            ]
          : p.steps,
      forgotten: forgot ? {...p.forgotten, p.index} : p.forgotten,
      reveal: (
        grade: grade,
        pin: pin,
        nearest: target.nearest(pin).nearestPoint,
        nextReviewDays: forgot
            ? null
            : result.card.dueAt!.difference(now).inDays,
        hit: hit,
      ),
    );
  }

  /// After the reveal: the next step, or the summary.
  void next() {
    final p = state;
    if (p is SessionPlaying && p.reveal != null) {
      _show(p.steps, p.index + 1, p.forgotten);
    }
  }

  void _show(List<SessionStep> steps, int index, Set<int> forgotten) {
    var i = index;
    // A street that left the pack is skipped.
    while (i < steps.length && _streets[itemKey(steps[i].itemId)] == null) {
      i++;
    }
    if (i >= steps.length) {
      state = SessionDone(_summary());
      return;
    }
    final step = steps[i];
    final street = _streets[itemKey(step.itemId)]!;
    final now = _now();
    _shownAt = now;
    final intros = [
      for (final s in steps)
        if (s.kind == StepKind.intro) s,
    ];
    final city = _pack.city();
    state = SessionPlaying(
      steps: steps,
      index: i,
      forgotten: forgotten,
      street: street,
      area: (bbox: city.bbox, boundary: city.boundary),
      known: _knownNear(street, now),
      newIndex: intros.indexOf(step) + 1,
      newTotal: intros.length,
      frame: step.kind == StepKind.retrieval1 ? _districtFrame(street) : null,
    );
  }

  /// Up to [LearningConfig.knownLabelMax] known streets nearest [street].
  List<NamedStreet> _knownNear(NamedStreet street, DateTime now) {
    final known = {
      for (final c in _cards.values)
        if (c.type == CardType.p && isKnown(c, now))
          ?_streets[itemKey(c.itemId)],
    }..remove(street);
    final at = street.parts.first.midpoint;
    double away(NamedStreet s) => distanceBetween(at, s.parts.first.midpoint);
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

  SessionSummary _summary() {
    final now = _now();
    final graded = _answers.length;
    final passed = _answers.where((a) => a.grade.rating.isSuccess).length;
    final closes = <String, int>{};
    for (final a in _answers.where((a) => a.grade.tier == Tier.close)) {
      closes.update(a.streetId, (n) => n + 1, ifAbsent: () => 1);
    }
    final midnight = nextMidnight(now);
    return (
      reviews: _answers.where((a) => a.step.kind == StepKind.review).length,
      newStreets: _introsDone,
      recalledPercent: graded == 0 ? 0 : (100 * passed / graded).round(),
      memoryBefore: _memoryBefore,
      memoryAfter: _memory(now),
      mixUps: [
        for (final a in _answers)
          if (a.grade.isMixUp)
            (_streets[a.streetId]!, _streets[a.grade.snapStreetId]!),
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

ReviewFormat _formatOf(StepKind kind) => switch (kind) {
  StepKind.retrieval1 => ReviewFormat.retrieval1,
  StepKind.retrieval2 => ReviewFormat.retrieval2,
  StepKind.relearn => ReviewFormat.relearn,
  StepKind.review || StepKind.intro => ReviewFormat.review,
};
