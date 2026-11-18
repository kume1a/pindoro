import 'dart:math';

import 'cards.dart';
import 'constants.dart';
import 'drills.dart';
import 'fsrs.dart';

/// What a session step asks (SPEC §6.4, §7). An intro writes no log row. A drill step's item is
/// the P item of its street: the sweep's parent, the crossings drill's street, the bearing's
/// target; [SessionPlan.drills] holds the rest.
enum StepKind {
  intro,
  retrieval1,
  review,
  retrieval2,
  relearn,
  placement,
  familySweep,
  crossings,
  bearing,
}

typedef SessionStep = ({StepKind kind, String itemId});

/// Today's session in rounds, in order, and the numbers Today shows.
class SessionPlan {
  const SessionPlan({
    required this.rounds,
    required this.dueCount,
    required this.backlog,
    required this.reviewCount,
    required this.newCount,
    this.drills = Drills.none,
    this.routeCount = 0,
  });

  /// At most [LearningConfig.roundSteps] steps each; a round closes its own new streets.
  final List<List<SessionStep>> rounds;
  final Drills drills;

  List<SessionStep> get steps => [for (final r in rounds) ...r];

  /// Every card due today, including the ones a backlog leaves for later.
  final int dueCount;

  /// More due than the budget holds: reviews only, most at risk first.
  final bool backlog;
  final int reviewCount;
  final int newCount;

  /// Route items and recitals among the reviews (Today's Turns).
  final int routeCount;
}

abstract final class Planner {
  /// Plans today's session (SPEC §7, §16.2, §16.13). [newCandidates] are item ids in curriculum
  /// order; leeches suspended before today come back first, as intros. [openPlaces] (new OSM
  /// landmarks' L1 items) follow them as intros, [LearningConfig.landmarkNewPerDay] a day less
  /// [placesIntroducedToday], at a new street's time and paused like the route items (§16.18).
  /// [introducedToday] and
  /// [spentTodayS] come from today's earlier sessions. [openSides] (`Curriculum.openSides`) start
  /// after the reviews, as many a day as new streets less [sidesStartedToday], in the minutes
  /// left; [openRoutes] (`openRoutes`) after them, [LearningConfig.routeNewPerDayMax] a
  /// day less [routesStartedToday], paused while the due reviews take more than
  /// [LearningConfig.routePauseFactor] of the minutes (SPEC §7); [openRecitals] (`openRecitals`)
  /// last, [LearningConfig.recitalNewPerDay] a day less [recitalsStartedToday], paused alike. A
  /// recital takes [LearningConfig.tRecitalS]. [drills] go mid-session; a backlog keeps only the
  /// family sweep, whose children leave the reviews. [extraNew] is "Learn 10 more": that many new streets past the daily
  /// number and the minutes, with no name and ends cards. Same inputs and [seed], same session.
  static SessionPlan plan({
    required List<CardState> cards,
    required List<String> newCandidates,
    required int minutesPerDay,
    required DateTime now,
    required int seed,
    int introducedToday = 0,
    int spentTodayS = 0,
    int? extraNew,
    List<String> openSides = const [],
    int sidesStartedToday = 0,
    List<String> openRoutes = const [],
    int routesStartedToday = 0,
    List<String> openPlaces = const [],
    int placesIntroducedToday = 0,
    List<String> openRecitals = const [],
    int recitalsStartedToday = 0,
    Drills drills = Drills.none,
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
    int pendingEarlier(CardType type) => pending
        .where((c) => c.type == type && c.introAt!.isBefore(today))
        .length;
    final retrievability = {
      for (final c in cards)
        if (c.memory != null) c.itemId: fsrs.retrievability(c.memory!, now),
    };
    // A due card with no memory (never retrieved) is the most at risk.
    int mostAtRisk(String a, String b) {
      final byR = (retrievability[a] ?? 0).compareTo(retrievability[b] ?? 0);
      return byR != 0 ? byR : a.compareTo(b);
    }

    final due = [
      for (final c in cards)
        if (isDueBefore(c, midnight)) c.itemId,
    ]..sort(mostAtRisk);
    int cost(String id) => secondsFor(id, tReviewS);
    final dueS = due.fold(0, (sum, id) => sum + cost(id));

    final budget = max(
      0,
      minutesPerDay * 60 - spentTodayS - pending.length * tNewS,
    );
    final backlog = dueS > budget;
    final swept = {...?drills.sweep?.children};
    final dueReviews = [
      for (final id in backlog ? _backlogReviews(due, cost, budget) : due)
        if (!swept.contains(id)) id,
    ];
    final newSlots =
        extraNew ??
        (backlog
            ? 0
            : min(
                max(
                  0,
                  newPerDay - introducedToday - pendingEarlier(CardType.p),
                ),
                (budget - dueS) ~/ tNewS,
              ));
    final leeches = [
      for (final c in cards)
        if (c.phase == CardPhase.suspended &&
            c.memory!.lastReview.isBefore(today))
          c.itemId,
    ]..sort();
    final carded = {for (final c in cards) c.itemId};
    final fresh = [
      ...leeches,
      ...newCandidates.where((id) => !carded.contains(id)),
    ].take(newSlots).toList();
    final routesPaused =
        backlog ||
        extraNew != null ||
        dueS > LearningConfig.routePauseFactor * budget;
    final placeSlots = routesPaused
        ? 0
        : min(
            LearningConfig.landmarkNewPerDay -
                placesIntroducedToday -
                pendingEarlier(CardType.l),
            (budget - dueS - fresh.length * tNewS) ~/ tNewS,
          );
    final places = [
      for (final id in openPlaces)
        if (!carded.contains(id)) id,
    ].take(max(0, placeSlots)).toList();
    final introS = (fresh.length + places.length) * tNewS;
    final sideSlots = backlog || extraNew != null
        ? 0
        : min(
            newPerDay - sidesStartedToday,
            (budget - dueS - introS) ~/ tReviewS,
          );
    final sides = openSides.take(max(0, sideSlots)).toList();
    final routeSlots = routesPaused
        ? 0
        : min(
            LearningConfig.routeNewPerDayMax - routesStartedToday,
            (budget - dueS - sides.length * tReviewS - introS) ~/ tReviewS,
          );
    final routes = openRoutes.take(max(0, routeSlots)).toList();
    final recitalSlots = routesPaused
        ? 0
        : min(
            LearningConfig.recitalNewPerDay - recitalsStartedToday,
            (budget -
                    dueS -
                    (sides.length + routes.length) * tReviewS -
                    introS) ~/
                LearningConfig.tRecitalS,
          );
    final reviews = [
      ...dueReviews,
      ...sides,
      ...routes,
      ...openRecitals.take(max(0, recitalSlots)),
    ];
    final kept = backlog ? Drills(sweep: drills.sweep) : drills;

    final random = Random(seed);
    final rounds = <List<SessionStep>>[];
    for (final (i, round) in _rounds(
      _units(
        fresh: [...fresh, ...places],
        reviews: reviews,
        drills: drillSteps(kept),
      ),
      pending: pending.length,
    ).indexed) {
      rounds.add(
        unstacked(
          _interleave(
            pending: i == 0 ? [for (final c in pending) c.itemId] : const [],
            source: round,
            random: random,
          ),
          after: rounds.lastOrNull?.lastOrNull?.itemId,
        ),
      );
    }
    return SessionPlan(
      rounds: rounds,
      dueCount: due.length,
      backlog: backlog,
      reviewCount: reviews.length,
      newCount: fresh.length,
      drills: kept,
      routeCount:
          places.length +
          reviews
              .where(
                (id) => isRouteItem(id) || CardType.ofItem(id) == CardType.r,
              )
              .length,
    );
  }

  /// A backlog's reviews: the most at-risk of [due] that fit in [budget] ×
  /// [LearningConfig.backlogCapFactor], skipping one that doesn't (a recital), and the first
  /// while any of the budget is left. So a plan empties only once nothing is due or the day's
  /// minutes are spent, when the day counts (SPEC §16.2).
  static List<String> _backlogReviews(
    List<String> due,
    int Function(String id) cost,
    int budget,
  ) {
    var room = budget * LearningConfig.backlogCapFactor;
    final fit = <String>[];
    for (final id in due) {
      if (cost(id) > room) continue;
      room -= cost(id);
      fit.add(id);
    }
    return fit.isEmpty && budget > 0 ? due.take(1).toList() : fit;
  }

  /// [drills] as session steps: the sweep, the crossings drill, then each bearing.
  static List<SessionStep> drillSteps(Drills drills) => [
    if (drills.sweep case final sweep?)
      (kind: StepKind.familySweep, itemId: CardType.p.item(sweep.parentId)),
    if (drills.crossings case final crossings?)
      (kind: StepKind.crossings, itemId: CardType.p.item(crossings.streetId)),
    for (final id in drills.bearings)
      (kind: StepKind.bearing, itemId: CardType.p.item(id)),
  ];

  /// Whether a missed [itemId] comes back again in a session of [steps]: not once it has had
  /// [LearningConfig.relearnMaxPerSession] relearns (SPEC §16.18). It stays due, for the next.
  static bool mayRelearn(List<SessionStep> steps, String itemId) =>
      steps
          .where((s) => s.kind == StepKind.relearn && s.itemId == itemId)
          .length <
      LearningConfig.relearnMaxPerSession;

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
    return unstacked(
      [...remaining]..insert(ownR2 >= 0 ? min(at, ownR2) : at, relearn),
      after: itemId,
    );
  }

  /// [steps] with no street asked twice in a row while another step can go between (SPEC
  /// §16.18): the nearest later step about another street moves up between the two, else the
  /// nearest earlier one moves down. Steps of one street keep their order. [after] is the item
  /// asked just before [steps].
  static List<SessionStep> unstacked(List<SessionStep> steps, {String? after}) {
    final out = [...steps];
    String? before(int i) => i == 0 ? after : out[i - 1].itemId;
    // A street's pin, name and ends cards and its drills all share its key.
    bool same(String? a, String b) => a != null && itemKey(a) == itemKey(b);
    bool mayCross(int from, int to, String id) =>
        !out.sublist(from, to).any((s) => same(s.itemId, id));
    for (var i = 0; i < out.length; i++) {
      final id = out[i].itemId;
      if (!same(before(i), id)) continue;
      final up = [
        for (var j = i + 1; j < out.length; j++)
          if (!same(id, out[j].itemId) && mayCross(i, j, out[j].itemId)) j,
      ].firstOrNull;
      final down = [
        for (var k = i - 2; k >= 0; k--)
          if (!same(id, out[k].itemId) &&
              mayCross(k + 1, i, out[k].itemId) &&
              !same(before(k), out[k + 1].itemId))
            k,
      ].firstOrNull;
      if (up != null) {
        out.insert(i, out.removeAt(up));
      } else if (down != null) {
        out.insert(i - 1, out.removeAt(down));
      }
    }
    return out;
  }

  // What stays together in a round: each group of new streets with the block of reviews after
  // it, every other review on its own, and the drills, half-way.
  static List<List<SessionStep>> _units({
    required List<String> fresh,
    required List<String> reviews,
    required List<SessionStep> drills,
  }) {
    final units = <List<SessionStep>>[];
    final reviewQueue = [...reviews];
    for (var i = 0; i < fresh.length; i += LearningConfig.groupSize) {
      final block = reviewQueue.take(LearningConfig.reviewsPerBlock).toList();
      reviewQueue.removeRange(0, block.length);
      units.add([
        for (final id in fresh.skip(i).take(LearningConfig.groupSize))
          (kind: StepKind.intro, itemId: id),
        for (final id in block) (kind: StepKind.review, itemId: id),
      ]);
    }
    units.addAll([
      for (final id in reviewQueue) [(kind: StepKind.review, itemId: id)],
    ]);
    if (drills.isNotEmpty) units.insert(units.length ~/ 2, drills);
    return units;
  }

  // [units] in as few rounds of at most [LearningConfig.roundSteps] steps as they fit, as
  // even as they cut (SPEC §16.20): the smallest cap that needs no more rounds. A new street
  // takes three steps (its intro and both retrievals), each of the [pending] two, in round 1.
  static List<List<SessionStep>> _rounds(
    List<List<SessionStep>> units, {
    required int pending,
  }) {
    if (units.isEmpty && pending == 0) return [];
    int cost(List<SessionStep> unit) =>
        unit.fold(0, (sum, s) => sum + (s.kind == StepKind.intro ? 3 : 1));
    List<List<SessionStep>> cut(int cap) {
      final rounds = <List<SessionStep>>[[]];
      var used = 2 * pending;
      for (final unit in units) {
        if (used > 0 && used + cost(unit) > cap) {
          rounds.add([]);
          used = 0;
        }
        rounds.last.addAll(unit);
        used += cost(unit);
      }
      return rounds;
    }

    var best = cut(LearningConfig.roundSteps);
    for (var cap = LearningConfig.roundSteps - 1; cap > 0; cap--) {
      final tighter = cut(cap);
      if (tighter.length > best.length) break;
      best = tighter;
    }
    return best;
  }

  // One round: the [pending] retrieval 1s first, then [source], every retrieval 1 slipping in
  // once its seeded gap of 3–6 other items has passed; the round's retrieval 2s close it.
  static List<SessionStep> _interleave({
    required List<String> pending,
    required List<SessionStep> source,
    required Random random,
  }) {
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
    final closing = [
      ...pending,
      for (final s in source)
        if (s.kind == StepKind.intro) s.itemId,
    ];
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

/// Cards of [types] introduced since the start of [now]'s day: streets come off today's new
/// number, places off today's places.
int introducedToday(
  Iterable<CardState> cards,
  DateTime now, {
  Set<CardType> types = const {CardType.p},
}) {
  final today = _day(now, 0);
  return cards
      .where(
        (c) =>
            types.contains(c.type) &&
            c.introAt != null &&
            !c.introAt!.isBefore(today),
      )
      .length;
}

/// Seconds spent learning since the start of [now]'s day (SPEC §16.9), each
/// session counted with [activeSeconds].
int spentTodayS(Iterable<LogEntry> log, DateTime now) {
  final today = _day(now, 0);
  return spentS(log.where((e) => !e.ts.isBefore(today)));
}

/// Seconds spent on [entries], each session counted with [activeSeconds].
int spentS(Iterable<LogEntry> entries) {
  final bySession = <String?, List<DateTime>>{};
  for (final entry in entries) {
    bySession.putIfAbsent(entry.sessionId, () => []).add(entry.ts);
  }
  return bySession.values.fold(0, (sum, times) => sum + activeSeconds(times));
}

/// Whether today counts towards the streak (SPEC §8, §16.8): something was answered [today] and
/// then either nothing is due before midnight or the day's minutes are spent.
bool dayCounts({
  required Iterable<CardState> cards,
  required List<LogEntry> today,
  required int minutesPerDay,
  required DateTime now,
}) {
  if (!today.any((e) => !e.ts.isBefore(_day(now, 0)))) return false;
  final midnight = nextMidnight(now);
  return !cards.any((c) => isDueBefore(c, midnight)) ||
      spentTodayS(today, now) >= minutesPerDay * 60;
}

/// The session's time estimates from the log (SPEC §16.9): once there are
/// [LearningConfig.timeEstimateMinSamples] reviews, a review takes the median
/// gap before a review answer and a new street the default share of it.
({int tReviewS, int tNewS}) timeEstimates(Iterable<LogEntry> log) {
  final bySession = <String?, List<LogEntry>>{};
  for (final e in log) {
    bySession.putIfAbsent(e.sessionId, () => []).add(e);
  }
  final gaps = <int>[];
  for (final rows in bySession.values) {
    rows.sort((a, b) => a.ts.compareTo(b.ts));
    for (var i = 1; i < rows.length; i++) {
      if (rows[i].format != ReviewFormat.review) continue;
      gaps.add(
        min(
          rows[i].ts.difference(rows[i - 1].ts).inSeconds,
          LearningConfig.answerGapCapS,
        ),
      );
    }
  }
  if (gaps.length < LearningConfig.timeEstimateMinSamples) {
    return (tReviewS: LearningConfig.tReviewS, tNewS: LearningConfig.tNewS);
  }
  gaps.sort();
  final tReview = max(1, gaps[gaps.length ~/ 2]);
  return (
    tReviewS: tReview,
    tNewS: (tReview * LearningConfig.tNewS / LearningConfig.tReviewS).round(),
  );
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

/// What reviewing [itemId] takes: [LearningConfig.tRecitalS] for a recital, else [tReviewS].
int secondsFor(String itemId, int tReviewS) =>
    CardType.ofItem(itemId) == CardType.r ? LearningConfig.tRecitalS : tReviewS;

/// Cards of [types] started since the start of [now]'s day (their first log row is today).
int startedToday(Iterable<LogEntry> log, DateTime now, Set<CardType> types) {
  final today = _day(now, 0);
  return log
      .where(
        (e) =>
            types.contains(e.type) &&
            e.sBefore == null &&
            !e.ts.isBefore(today),
      )
      .map((e) => e.itemId)
      .toSet()
      .length;
}

/// The name and ends cards.
const Set<CardType> sideTypes = {CardType.n, CardType.e};

/// The route cards (SPEC §3): turns, gateways, bridges, connections, landmarks.
const Set<CardType> routeTypes = {
  CardType.j,
  CardType.g,
  CardType.b,
  CardType.c,
  CardType.l,
};

bool isRouteItem(String itemId) => routeTypes.contains(CardType.ofItem(itemId));

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

/// Days of the day's minutes that [dueCount] reviews take (Today's catching
/// up: "About 3 days at 20 min").
int catchUpDays({
  required int dueCount,
  required int minutesPerDay,
  int tReviewS = LearningConfig.tReviewS,
}) => (dueCount * tReviewS / (minutesPerDay * 60)).ceil();
