import 'package:pindoro_core/pindoro_core.dart';

import 'cards.dart';
import 'constants.dart';
import 'curriculum.dart';
import 'fsrs.dart';
import 'placement.dart';
import 'planner.dart';

/// Known (now), SPEC §8 and §16.17: a success on a day after the intro (or a
/// placement or carried-over card), the last answer not forgotten, and recall
/// still at [LearningConfig.knownMinR] or more. It decays on its own.
bool isKnown(CardState card, DateTime now, {Fsrs fsrs = const Fsrs()}) {
  final memory = card.memory;
  if (memory == null || !(card.lastRating?.isSuccess ?? false)) return false;
  final introAt = card.introAt;
  final laterDay =
      card.priorKnown ||
      introAt == null ||
      startOfDay(memory.lastReview).isAfter(startOfDay(introAt));
  return laterDay &&
      fsrs.retrievability(memory, now) >= LearningConfig.knownMinR;
}

extension CardLabels on CardState {
  /// Solid, SPEC §8: stability of [LearningConfig.solidDays] or more.
  bool get isSolid => (memory?.stability ?? 0) >= LearningConfig.solidDays;
}

/// City memory, SPEC §8: the recall chance summed over the core streets'
/// cards, so "streets you'd place right now"; unseen streets add nothing.
double cityMemory(
  Iterable<CardState> cards,
  DateTime now, {
  required bool Function(String itemId) isCore,
  Fsrs fsrs = const Fsrs(),
}) => cards
    .where((c) => c.memory != null && isCore(c.itemId))
    .fold(0, (sum, c) => sum + fsrs.retrievability(c.memory!, now));

/// The memory bar's states, strongest first (SPEC §8). Every card is at least Seen.
enum MemoryState { mastered, solid, known, seen }

/// Mastered, SPEC §8: stability of [LearningConfig.masteredDays] or more and the last answer a
/// success. Name and ends cards join the rule when they exist.
bool isMastered(CardState card) =>
    (card.memory?.stability ?? 0) >= LearningConfig.masteredDays &&
    (card.lastRating?.isSuccess ?? false);

MemoryState memoryState(
  CardState card,
  DateTime now, {
  Fsrs fsrs = const Fsrs(),
}) => isMastered(card)
    ? MemoryState.mastered
    : card.isSolid
    ? MemoryState.solid
    : isKnown(card, now, fsrs: fsrs)
    ? MemoryState.known
    : MemoryState.seen;

Map<MemoryState, int> memoryCounts(Iterable<CardState> cards, DateTime now) {
  final counts = {for (final s in MemoryState.values) s: 0};
  for (final c in cards) {
    counts.update(memoryState(c, now), (n) => n + 1);
  }
  return counts;
}

/// Recall rate, SPEC §16.18: the share of the last 30 days' due reviews passed; null with none.
double? recallRate(Iterable<LogEntry> log, DateTime now) {
  final since = now.subtract(const Duration(days: 30));
  final reviews = [
    for (final e in log)
      if (e.format == ReviewFormat.review && e.ts.isAfter(since)) e,
  ];
  if (reviews.isEmpty) return null;
  return reviews.where((e) => e.rating.isSuccess).length / reviews.length;
}

/// Reviews due on each of the next [days] days, today first; overdue ones count on today.
List<int> forecast(Iterable<CardState> cards, DateTime now, {int days = 14}) {
  final ends = [
    for (var d = 1; d <= days; d++) startOfDay(now).add(Duration(days: d)),
  ];
  final counts = List.filled(days, 0);
  for (final c in cards) {
    final day = ends.indexWhere((end) => isDueBefore(c, end));
    if (day >= 0) counts[day]++;
  }
  return counts;
}

/// Whole-city date, SPEC §16.19: today plus the unseen core streets at [newPerDay]; null when
/// nothing new comes.
DateTime? wholeCityBy({
  required int unseenCore,
  required int newPerDay,
  required DateTime now,
}) => newPerDay <= 0
    ? null
    : startOfDay(now).add(Duration(days: (unseenCore / newPerDay).ceil()));

/// Whether [entry] moved its card's memory: a guess or a logged Explore answer never does, nor
/// a placement pin that created no card.
bool changesSchedule(LogEntry entry) =>
    entry.format != ReviewFormat.pretest &&
    entry.format != ReviewFormat.exploreLog &&
    !(entry.format == ReviewFormat.placement &&
        !Placement.passes(entry.rating));

/// [card]'s memory at [t], replayed from its [log] rows (SPEC §16.20): each row records the
/// memory before it, so the memory after one row is the one the next row saw. Null before the
/// card had any.
Memory? memoryAt(CardState card, Iterable<LogEntry> log, DateTime t) {
  final rows = [
    for (final e in log)
      if (e.itemId == card.itemId && changesSchedule(e)) e,
  ]..sort((a, b) => a.ts.compareTo(b.ts));
  final k = rows.lastIndexWhere((r) => !r.ts.isAfter(t));
  if (k == rows.length - 1 && k >= 0) return card.memory;
  if (k >= 0) return _before(rows[k + 1], lastReview: rows[k].ts);
  final first = rows.firstOrNull;
  if (first == null) {
    final m = card.memory;
    return m != null && !m.lastReview.isAfter(t) ? m : null;
  }
  final elapsed = first.elapsedDays;
  if (elapsed == null) return null;
  final last = first.ts.subtract(
    Duration(microseconds: (elapsed * Duration.microsecondsPerDay).round()),
  );
  return last.isAfter(t) ? null : _before(first, lastReview: last);
}

Memory? _before(LogEntry row, {required DateTime lastReview}) =>
    switch ((row.sBefore, row.dBefore)) {
      (final s?, final d?) => Memory(
        stability: s,
        difficulty: d,
        lastReview: lastReview,
      ),
      _ => null,
    };

/// City memory at an earlier moment [t], replayed from [log] (SPEC §16.20).
double cityMemoryAt(
  Iterable<CardState> cards,
  Iterable<LogEntry> log,
  DateTime t, {
  Fsrs fsrs = const Fsrs(),
}) => _replay(cards, _byItem(log), fsrs)(t);

Map<String, List<LogEntry>> _byItem(Iterable<LogEntry> log) {
  final byItem = <String, List<LogEntry>>{};
  for (final e in log) {
    byItem.putIfAbsent(e.itemId, () => []).add(e);
  }
  return byItem;
}

double Function(DateTime t) _replay(
  Iterable<CardState> cards,
  Map<String, List<LogEntry>> byItem,
  Fsrs fsrs,
) =>
    (t) => cards.fold(0, (sum, c) {
      final m = memoryAt(c, byItem[c.itemId] ?? const [], t);
      return m == null ? sum : sum + fsrs.retrievability(m, t);
    });

/// City memory over time (the Progress chart): 11 points evenly from 10 weeks ago, or from the
/// first answer when that is later, to [now]. One point with no play at all.
({DateTime start, List<double> values}) cityMemoryHistory({
  required Iterable<CardState> cards,
  required Iterable<LogEntry> log,
  required DateTime now,
  required bool Function(String itemId) isCore,
  Fsrs fsrs = const Fsrs(),
}) {
  final core = [
    for (final c in cards)
      if (isCore(c.itemId)) c,
  ];
  final firsts = [
    for (final e in log) e.ts,
    for (final c in core) ?c.memory?.lastReview,
  ];
  if (firsts.isEmpty) return (start: now, values: [0]);
  final first = firsts.reduce((a, b) => a.isBefore(b) ? a : b);
  final tenWeeks = now.subtract(const Duration(days: 70));
  final start = first.isAfter(tenWeeks) ? first : tenWeeks;
  final span = now.difference(start).inMicroseconds;
  final at = _replay(core, _byItem(log), fsrs);
  return (
    start: start,
    values: [
      for (var i = 0; i <= 10; i++)
        at(start.add(Duration(microseconds: span * i ~/ 10))),
    ],
  );
}

/// Raions and neighbourhoods whose every core street is Mastered (SPEC §8),
/// and raions with a Known street, over [streets] and their chunks' raions
/// ([districts]); [cards] are P cards by street id.
({int masteredRaions, int masteredNeighbourhoods, int knownRaions}) areaCounts({
  required Iterable<NamedStreet> streets,
  required Iterable<District> districts,
  required Map<String, CardState> cards,
  required DateTime now,
}) {
  final raionOf = {
    for (final d in districts)
      if (d.kind == DistrictKind.neighbourhood && d.parentId != null)
        d.id: d.parentId!,
  };
  final byChunk = <String, List<NamedStreet>>{};
  final byRaion = <String, List<NamedStreet>>{};
  for (final s in streets.toSet().where(Curriculum.isCore)) {
    final chunk = s.parts.first.chunkId;
    final raion = raionOf[chunk];
    if (chunk == null || raion == null) continue;
    byChunk.putIfAbsent(chunk, () => []).add(s);
    byRaion.putIfAbsent(raion, () => []).add(s);
  }
  bool mastered(List<NamedStreet> area) =>
      area.every((s) => cards[s.id] != null && isMastered(cards[s.id]!));
  return (
    masteredRaions: byRaion.values.where(mastered).length,
    masteredNeighbourhoods: byChunk.values.where(mastered).length,
    knownRaions: byRaion.values
        .where(
          (area) => area.any(
            (s) => switch (cards[s.id]) {
              final c? => isKnown(c, now),
              null => false,
            },
          ),
        )
        .length,
  );
}

/// A street once became a leech and none is left (SPEC §16.8, Clear road).
bool leechesCleared(Iterable<CardState> cards) =>
    cards.any((c) => c.lapses >= LearningConfig.leechLapses) &&
    !cards.any((c) => c.phase == CardPhase.suspended);
