import 'dart:math';

import 'cards.dart';
import 'constants.dart';
import 'fsrs.dart';

/// What a session step asks (SPEC §6.4, §7). An intro writes no log row.
enum StepKind { intro, retrieval1, review, retrieval2, relearn, placement }

typedef SessionStep = ({StepKind kind, String itemId});

/// Today's session, in order, and the numbers Today shows.
class SessionPlan {
  const SessionPlan({
    required this.steps,
    required this.dueCount,
    required this.backlog,
    required this.reviewCount,
    required this.newCount,
    required this.estimatedS,
  });

  final List<SessionStep> steps;

  /// Every card due today, including the ones a backlog leaves for later.
  final int dueCount;

  /// More due than the budget holds: reviews only, most at risk first.
  final bool backlog;
  final int reviewCount;
  final int newCount;
  final int estimatedS;
}

abstract final class Planner {
  /// Plans today's session (SPEC §7, §16.2). [newCandidates] are item ids in curriculum order;
  /// [introducedToday] and [spentTodayS] come from today's earlier sessions. Same inputs and
  /// [seed], same session.
  static SessionPlan plan({
    required List<CardState> cards,
    required List<String> newCandidates,
    required int minutesPerDay,
    required DateTime now,
    required int seed,
    int introducedToday = 0,
    int spentTodayS = 0,
    int tReviewS = LearningConfig.tReviewS,
    int tNewS = LearningConfig.tNewS,
    Fsrs fsrs = const Fsrs(),
  }) {
    final newPerDay =
        LearningConfig.newPerDay[minutesPerDay] ??
        (throw ArgumentError.value(minutesPerDay, 'minutesPerDay'));
    final midnight = nextMidnight(now);
    final today = _day(now, 0);

    final pending = [
      for (final c in cards)
        if (c.phase == CardPhase.learning && c.memory == null) c,
    ]..sort((a, b) => a.introAt!.compareTo(b.introAt!));
    final pendingEarlier = pending
        .where((c) => c.introAt!.isBefore(today))
        .length;
    final retrievability = {
      for (final c in cards)
        if (c.memory != null) c.itemId: fsrs.retrievability(c.memory!, now),
    };
    int mostAtRisk(String a, String b) {
      final byR = retrievability[a]!.compareTo(retrievability[b]!);
      return byR != 0 ? byR : a.compareTo(b);
    }

    final due = [
      for (final c in cards)
        if (isDueBefore(c, midnight)) c.itemId,
    ]..sort(mostAtRisk);

    final budget = max(
      0,
      minutesPerDay * 60 - spentTodayS - pending.length * tNewS,
    );
    final backlog = due.length * tReviewS > budget;
    final reviews = backlog
        ? due
              .take(
                (budget * LearningConfig.backlogCapFactor / tReviewS).floor(),
              )
              .toList()
        : due;
    final newSlots = backlog
        ? 0
        : min(
            max(0, newPerDay - introducedToday - pendingEarlier),
            (budget - due.length * tReviewS) ~/ tNewS,
          );
    final carded = {for (final c in cards) c.itemId};
    final fresh = newCandidates
        .where((id) => !carded.contains(id))
        .take(newSlots)
        .toList();

    final steps = _interleave(
      pending: [for (final c in pending) c.itemId],
      fresh: fresh,
      reviews: reviews,
      random: Random(seed),
    );
    return SessionPlan(
      steps: steps,
      dueCount: due.length,
      backlog: backlog,
      reviewCount: reviews.length,
      newCount: fresh.length,
      estimatedS:
          reviews.length * tReviewS + (fresh.length + pending.length) * tNewS,
    );
  }

  /// [remaining] with a relearn of [itemId] after 5–10 other items (SPEC §4): at the end when
  /// fewer are left, and never after the street's own retrieval 2.
  static List<SessionStep> withRelearn(
    List<SessionStep> remaining,
    String itemId,
    Random random,
  ) {
    final gap =
        LearningConfig.relearnGapMin +
        random.nextInt(
          LearningConfig.relearnGapMax - LearningConfig.relearnGapMin + 1,
        );
    final ownR2 = remaining.indexOf((
      kind: StepKind.retrieval2,
      itemId: itemId,
    ));
    final at = remaining.length < LearningConfig.relearnGapMin
        ? remaining.length
        : min(gap, remaining.length);
    final relearn = (kind: StepKind.relearn, itemId: itemId);
    return [...remaining]..insert(ownR2 >= 0 ? min(at, ownR2) : at, relearn);
  }

  // Groups of new streets, each followed by a block of reviews; every retrieval 1 slips in once
  // its seeded gap of 3–6 other items has passed; the retrieval 2s close the session.
  static List<SessionStep> _interleave({
    required List<String> pending,
    required List<String> fresh,
    required List<String> reviews,
    required Random random,
  }) {
    final source = <SessionStep>[];
    final reviewQueue = [...reviews];
    for (var i = 0; i < fresh.length; i += LearningConfig.groupSize) {
      source.addAll([
        for (final id in fresh.skip(i).take(LearningConfig.groupSize))
          (kind: StepKind.intro, itemId: id),
      ]);
      final block = reviewQueue.take(LearningConfig.reviewsPerBlock).toList();
      reviewQueue.removeRange(0, block.length);
      source.addAll([
        for (final id in block) (kind: StepKind.review, itemId: id),
      ]);
    }
    source.addAll([
      for (final id in reviewQueue) (kind: StepKind.review, itemId: id),
    ]);

    final out = <SessionStep>[
      for (final id in pending) (kind: StepKind.retrieval1, itemId: id),
    ];
    final waiting = <({String itemId, int target, int since})>[];
    void emit(SessionStep step) {
      out.add(step);
      for (var i = 0; i < waiting.length; i++) {
        final w = waiting[i];
        waiting[i] = (itemId: w.itemId, target: w.target, since: w.since + 1);
      }
    }

    void emitReady() {
      for (var ready = _ready(waiting); ready >= 0; ready = _ready(waiting)) {
        emit((
          kind: StepKind.retrieval1,
          itemId: waiting.removeAt(ready).itemId,
        ));
      }
    }

    for (final step in source) {
      emitReady();
      emit(step);
      if (step.kind == StepKind.intro) {
        final target =
            LearningConfig.retrieval1GapMin +
            random.nextInt(
              LearningConfig.retrieval1GapMax -
                  LearningConfig.retrieval1GapMin +
                  1,
            );
        waiting.add((itemId: step.itemId, target: target, since: 0));
      }
    }
    // The closing retrieval 2s keep spacing the last retrieval 1s; one is forced early only when
    // every step left waits on a retrieval 1.
    final closing = [...pending, ...fresh];
    while (closing.isNotEmpty || waiting.isNotEmpty) {
      emitReady();
      final next = closing.indexWhere(
        (id) => !waiting.any((w) => w.itemId == id),
      );
      if (next >= 0) {
        emit((kind: StepKind.retrieval2, itemId: closing.removeAt(next)));
      } else {
        emit((kind: StepKind.retrieval1, itemId: waiting.removeAt(0).itemId));
      }
    }
    return out;
  }

  static int _ready(List<({String itemId, int target, int since})> waiting) =>
      waiting.indexWhere((w) => w.since >= w.target);
}

/// A reviewed card due before [t] (learning, suspended and unseen are not).
bool isDueBefore(CardState card, DateTime t) =>
    (card.phase == CardPhase.review || card.phase == CardPhase.relearning) &&
    card.dueAt != null &&
    card.dueAt!.isBefore(t);

/// The start of the calendar day after [now], in [now]'s time zone (SPEC §16.3).
DateTime nextMidnight(DateTime now) => _day(now, 1);

/// The start of [now]'s calendar day, in [now]'s time zone (SPEC §16.3).
DateTime startOfDay(DateTime now) => _day(now, 0);

// Midnight [offset] calendar days from [now]'s day; calendar arithmetic keeps DST days right.
DateTime _day(DateTime now, int offset) => now.isUtc
    ? DateTime.utc(now.year, now.month, now.day + offset)
    : DateTime(now.year, now.month, now.day + offset);

/// Streets introduced since the start of [now]'s day: they come off today's new number.
int introducedToday(Iterable<CardState> cards, DateTime now) {
  final today = _day(now, 0);
  return cards
      .where((c) => c.introAt != null && !c.introAt!.isBefore(today))
      .length;
}

/// Seconds spent learning since the start of [now]'s day (SPEC §16.9), each
/// session counted with [activeSeconds].
int spentTodayS(Iterable<LogEntry> log, DateTime now) {
  final today = _day(now, 0);
  final bySession = <String?, List<DateTime>>{};
  for (final entry in log.where((e) => !e.ts.isBefore(today))) {
    bySession.putIfAbsent(entry.sessionId, () => []).add(entry.ts);
  }
  return bySession.values.fold(0, (sum, times) => sum + activeSeconds(times));
}

/// Seconds between consecutive [times] of one session, each gap capped at
/// [LearningConfig.answerGapCapS] (SPEC §16.9).
int activeSeconds(Iterable<DateTime> times) {
  final sorted = times.toList()..sort();
  var seconds = 0;
  for (var i = 1; i < sorted.length; i++) {
    seconds += min(
      sorted[i].difference(sorted[i - 1]).inSeconds,
      LearningConfig.answerGapCapS,
    );
  }
  return seconds;
}

/// Seconds the [steps] left should take at the planner's rates: a review or
/// relearn [tReviewS]; an intro and each of its two retrievals a third of
/// [tNewS] (SPEC §7).
int remainingSeconds(
  Iterable<SessionStep> steps, {
  int tReviewS = LearningConfig.tReviewS,
  int tNewS = LearningConfig.tNewS,
}) => steps.fold(
  0,
  (sum, s) =>
      sum +
      switch (s.kind) {
        StepKind.review || StepKind.relearn => tReviewS,
        StepKind.placement => LearningConfig.placementPinS,
        StepKind.intro ||
        StepKind.retrieval1 ||
        StepKind.retrieval2 => tNewS ~/ 3,
      },
);

/// The session bar's 12 blocks (design system Progress, v3): each covers a
/// twelfth of the [total] steps. Returns one entry per finished block, true
/// when it holds a forgotten answer ([forgotten] are step indices), with
/// [answered] steps done; the next block is the current one.
List<bool> finishedBlocks({
  required int total,
  required int answered,
  required Set<int> forgotten,
}) {
  const blocks = 12;
  final out = <bool>[];
  for (var b = 0; b < blocks; b++) {
    final start = (b * total / blocks).ceil();
    final end = ((b + 1) * total / blocks).ceil();
    if (answered < end) break;
    out.add(forgotten.any((i) => i >= start && i < end));
  }
  return out;
}
