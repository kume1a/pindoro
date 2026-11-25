import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'cards.dart';
import 'constants.dart';
import 'drive_log.dart';
import 'fsrs.dart';
import 'nav_level.dart';
import 'nav_plan.dart';
import 'nav_view.dart';
import 'routes.dart';
import 'stats.dart';

// What a drive teaches and how it shows (SPEC §16.23 items 119–123).

/// Whether [d]'s junction is complex: [LearningConfig.complexWaysOn] or more legal ways on.
bool isComplex(RoadGraph graph, NavDecision d) =>
    graph
        .legalExits(d.junction, approach: d.approach)
        .where((e) => e.id != d.approach?.id)
        .length >=
    LearningConfig.complexWaysOn;

/// The preview's key decisions (item 121), in route order: those not [silent] and the complex
/// junctions, the hardest when there are more than [LearningConfig.keyTurnsMax]; under
/// [LearningConfig.keyTurnsMin], the hardest others join. Hardest is the lowest [recall] by key,
/// a decision without a card first.
List<NavDecision> keyDecisions(
  RoadGraph graph,
  List<NavDecision> decisions, {
  Set<String> silent = const {},
  Map<String, double> recall = const {},
}) {
  double ease(NavDecision d) => recall[d.key] ?? 0;
  final hardest = [...decisions]
    ..sort((a, b) {
      final byEase = ease(a).compareTo(ease(b));
      return byEase != 0 ? byEase : a.index.compareTo(b.index);
    });
  final picked = [
    for (final d in hardest)
      if (!silent.contains(d.key) || isComplex(graph, d)) d,
  ].take(LearningConfig.keyTurnsMax).toList();
  for (final d in hardest) {
    if (picked.length >= LearningConfig.keyTurnsMin) break;
    if (!picked.contains(d)) picked.add(d);
  }
  return picked..sort((a, b) => a.index.compareTo(b.index));
}

/// How a decision on a drive went (the debrief and the review map, board V32-50).
enum TurnMark { good, hard, again, helped, watched }

/// A logged decision's mark: none in a GPS gap ([ok] null); watched only when Guided showed the
/// way; helped after Coached's cue, in a recovery or just after one; on the player's own Good,
/// Hard after a hesitation, Again when it lost the good path.
TurnMark? turnMark({
  required bool? ok,
  required NavHelp help,
  required bool recentHelp,
  required bool hesitated,
}) => switch ((ok, help)) {
  (null, _) => null,
  (_, NavHelp.guided) => TurnMark.watched,
  (_, NavHelp.cue || NavHelp.recovery) => TurnMark.helped,
  _ when recentHelp => TurnMark.helped,
  (false, _) => TurnMark.again,
  _ => hesitated ? TurnMark.hard : TurnMark.good,
};

/// The share of [marks] taken on the player's own (Good or Hard), GPS gaps aside; null with none.
double? ownShare(Iterable<TurnMark?> marks) {
  final counted = marks.nonNulls.toList();
  if (counted.isEmpty) return null;
  return counted.where((m) => m == TurnMark.good || m == TurnMark.hard).length /
      counted.length;
}

/// A decision of the drive log as the debrief sees it: its place in the drive, its J item key,
/// its mark and whether it was a key decision of the drive's plan.
typedef LoggedTurn = ({int seq, String key, TurnMark? mark, bool keyTurn});

/// The debrief's turns (item 121), in drive order: every missed or helped decision and the key
/// ones, at most [LearningConfig.keyTurnsMax] (missed first, then helped, then key), each turn
/// once.
List<LoggedTurn> debriefTurns(List<LoggedTurn> turns) {
  int rank(LoggedTurn t) => switch (t.mark) {
    TurnMark.again => 0,
    TurnMark.helped => 1,
    _ => 2,
  };
  final wanted =
      [
        for (final t in turns)
          if (t.mark == TurnMark.again ||
              t.mark == TurnMark.helped ||
              t.keyTurn)
            t,
      ]..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : a.seq.compareTo(b.seq);
      });
  final seen = <String>{};
  final out = <LoggedTurn>[];
  for (final t in wanted) {
    if (out.length >= LearningConfig.keyTurnsMax) break;
    if (seen.add(t.key)) out.add(t);
  }
  return out..sort((a, b) => a.seq.compareTo(b.seq));
}

/// Point to home's tier (item 121) for an error of [errorDeg].
Tier pointingTier(double errorDeg) => switch (errorDeg) {
  <= LearningConfig.pointPerfectDeg => Tier.perfect,
  <= LearningConfig.pointGreatDeg => Tier.great,
  <= LearningConfig.pointCloseDeg => Tier.close,
  _ => Tier.miss,
};

/// What a drive decision does to its J [card] (item 119): [driveCredit]'s rating, a failure
/// applied as [implicitReview] does, a success as a drive review of a card with a memory; else
/// why it reviews nothing (the drive log's FSRS effect, item 124).
({({CardState card, LogEntry log})? review, CreditSkip? skip}) driveReview(
  CardState? card, {
  required bool ok,
  required NavHelp help,
  required bool recentHelp,
  required bool hesitated,
  required DateTime now,
  List<DateTime> passes = const [],
  DateTime? lastCredited,
  Fsrs fsrs = const Fsrs(),
}) {
  final credit = driveCredit(
    card: card,
    ok: ok,
    help: help,
    recentHelp: recentHelp,
    hesitated: hesitated,
    now: now,
    passes: passes,
    lastCredited: lastCredited,
    fsrs: fsrs,
  );
  final rating = credit.rating;
  const sessionOnly = (review: null, skip: CreditSkip.sessionOnly);
  if (rating == null || card == null) return (review: null, skip: credit.skip);
  if (rating == Rating.again) {
    final review = implicitReview(
      card,
      ok: false,
      now: now,
      source: ReviewSource.drive,
    );
    return review == null ? sessionOnly : (review: review, skip: null);
  }
  if (card.memory == null || card.phase == CardPhase.suspended) {
    return sessionOnly;
  }
  return (
    review: applyReview(
      card,
      itemId: card.itemId,
      rating: rating,
      now: now,
      format: ReviewFormat.drive,
      source: ReviewSource.drive,
      fsrs: fsrs,
    ),
    skip: null,
  );
}

/// A drive's [decisions] reviewing their J [cards] by item 119 ([hesitated] alike in order):
/// [passes] by key over the last [LearningConfig.habitWindowDays] make a habitual corridor, and a
/// card credited at [lastCredited] waits. Each decision of a route-book turn ([isTurn]) taken
/// without help is [evidence], carded or not (a miss keeps it from going silent, item 113).
/// [effects] holds what each decision did to its card, in order (item 124).
({
  List<({String itemId, bool ok})> evidence,
  List<({CardState card, LogEntry log})> reviews,
  List<String?> effects,
})
creditDrive(
  List<PassedDecision> decisions,
  List<bool> hesitated, {
  required Map<String, CardState> cards,
  required bool Function(String key) isTurn,
  required Map<String, DateTime> lastCredited,
  required Map<String, List<DateTime>> passes,
  required DateTime now,
}) {
  final latest = {...cards};
  final credited = {...lastCredited};
  final evidence = <({String itemId, bool ok})>[];
  final reviews = <({CardState card, LogEntry log})>[];
  final effects = List<String?>.filled(decisions.length, null);
  for (final (i, d) in decisions.indexed) {
    final key = d.key;
    final ok = d.ok;
    if (key == null || ok == null) continue;
    if (isTurn(key) && d.help == NavHelp.none && !d.recentHelp) {
      evidence.add((itemId: key, ok: ok));
    }
    final (:review, :skip) = driveReview(
      latest[key],
      ok: ok,
      help: d.help,
      recentHelp: d.recentHelp,
      hesitated: hesitated[i],
      now: now,
      passes: [...?passes[key], d.at],
      lastCredited: credited[key],
    );
    effects[i] = review?.log.rating.name ?? skip?.name;
    if (review == null) continue;
    reviews.add(review);
    latest[key] = review.card;
    if (review.log.rating.isSuccess) credited[key] = now;
  }
  return (evidence: evidence, reviews: reviews, effects: effects);
}

/// A drive as the weekly goal, Progress and Today see it (items 120–123): when it started, the
/// level chosen and the one with the most help it reached (a Rescue's Guided, the guard's step,
/// a level raised while stopped), whether it arrived, its [route] (where from, where to) and
/// [destination] keys, its stretch and recoveries.
typedef DriveSummary = ({
  DateTime startedAt,
  DriveLevel level,
  DriveLevel mostHelp,
  bool arrived,
  String? route,
  String? destination,
  double? stretch,
  int recoveries,
});

/// Arrived with no help (item 122): at Quiet or Off the whole way, not rescued.
bool withoutHelp(DriveSummary d) =>
    d.arrived && d.mostHelp.index >= DriveLevel.quiet.index;

/// The Monday, local midnight, that starts the week of [t].
DateTime weekOf(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day - (l.weekday - 1));
}

/// One week of the drive goal: drives without help and new destinations reached without help.
typedef WeekGoal = ({int quietDrives, int newPlaces});

bool weekDone(WeekGoal w) =>
    w.quietDrives >= LearningConfig.weekQuietDrives &&
    w.newPlaces >= LearningConfig.weekNewPlaces;

/// The weekly drive goal (item 122) over [drives] at [now]: this week's and last week's counts,
/// the weeks done (never a streak), and "Back on track" while this week isn't done after a missed
/// week that followed earlier drives. A destination is new until the first drive that arrives
/// there.
({WeekGoal week, WeekGoal lastWeek, int weeksDone, bool backOnTrack}) driveWeek(
  Iterable<DriveSummary> drives,
  DateTime now,
) {
  final sorted = [...drives]
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  final reached = <String>{};
  final weeks = <DateTime, WeekGoal>{};
  for (final d in sorted) {
    final free = withoutHelp(d);
    final destination = d.arrived ? d.destination : null;
    final isNew = destination != null && reached.add(destination);
    final w = weekOf(d.startedAt);
    final c = weeks[w] ?? (quietDrives: 0, newPlaces: 0);
    weeks[w] = (
      quietDrives: c.quietDrives + (free ? 1 : 0),
      newPlaces: c.newPlaces + (free && isNew ? 1 : 0),
    );
  }
  final thisWeek = weekOf(now);
  final previous = weekOf(thisWeek.subtract(const Duration(days: 1)));
  const none = (quietDrives: 0, newPlaces: 0);
  final week = weeks[thisWeek] ?? none;
  final lastWeek = weeks[previous] ?? none;
  return (
    week: week,
    lastWeek: lastWeek,
    weeksDone: weeks.values.where(weekDone).length,
    backOnTrack:
        !weekDone(week) &&
        !weekDone(lastWeek) &&
        sorted.any((d) => d.startedAt.isBefore(previous)),
  );
}

/// A route's level by month (item 123): each month with drives, oldest first, and the level its
/// last drive that month started at.
typedef RouteMonths = List<({DateTime month, DriveLevel level})>;

/// The frequent routes (item 123): routes with at least [LearningConfig.frequentRouteDrives]
/// drives, the most driven first, with their drives and level by month.
List<({String route, int drives, RouteMonths months})> frequentRoutes(
  Iterable<DriveSummary> drives,
) {
  final byRoute = <String, List<DriveSummary>>{};
  for (final d in drives) {
    if (d.route case final r?) byRoute.putIfAbsent(r, () => []).add(d);
  }
  final out = [
    for (final MapEntry(key: route, value: list) in byRoute.entries)
      if (list.length >= LearningConfig.frequentRouteDrives)
        (route: route, drives: list.length, months: _months(list)),
  ];
  return out..sort((a, b) => b.drives.compareTo(a.drives));
}

RouteMonths _months(List<DriveSummary> drives) {
  final sorted = [...drives]
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  final byMonth = <DateTime, DriveLevel>{};
  for (final d in sorted) {
    final l = d.startedAt.toLocal();
    byMonth[DateTime(l.year, l.month)] = d.level;
  }
  return [
    for (final MapEntry(key: month, value: level) in byMonth.entries)
      (month: month, level: level),
  ];
}

/// [months] as runs of one level, oldest first ("Guided in March, Off since June").
List<({DriveLevel level, DateTime from, DateTime to})> levelRuns(
  RouteMonths months,
) {
  final out = <({DriveLevel level, DateTime from, DateTime to})>[];
  for (final m in months) {
    final last = out.lastOrNull;
    if (last != null && last.level == m.level) {
      out.last = (level: last.level, from: last.from, to: m.month);
    } else {
      out.add((level: m.level, from: m.month, to: m.month));
    }
  }
  return out;
}

/// The routes driven at least [LearningConfig.yourRouteDrives] times in the
/// [LearningConfig.yourRouteDays] before [now] (item 120).
Set<String> yourRoutes(Iterable<DriveSummary> drives, DateTime now) {
  final counts = <String, int>{};
  for (final d in drives) {
    final route = d.route;
    if (route == null ||
        now.difference(d.startedAt).inDays >= LearningConfig.yourRouteDays) {
      continue;
    }
    counts.update(route, (n) => n + 1, ifAbsent: () => 1);
  }
  return {
    for (final MapEntry(:key, :value) in counts.entries)
      if (value >= LearningConfig.yourRouteDrives) key,
  };
}

/// The decision keys passed at least [LearningConfig.habitPasses] times in the
/// [LearningConfig.habitWindowDays] before [now]: habitual corridors, one way (item 119).
Set<String> habitualKeys(
  Iterable<({String key, DateTime at})> passes,
  DateTime now,
) {
  final counts = <String, int>{};
  for (final p in passes) {
    if (now.difference(p.at).inDays < LearningConfig.habitWindowDays) {
      counts.update(p.key, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  return {
    for (final MapEntry(:key, :value) in counts.entries)
      if (value >= LearningConfig.habitPasses) key,
  };
}

final _turnKey = RegExp(r'n(\d+):n(\d+):n(\d+)$');

/// The J item of the same junction the other way (item 119): in from where [key] leaves, out to
/// where it came from. Null for a key that isn't a turn's.
String? reverseTurn(String key) {
  if (CardType.ofItem(key) != CardType.j) return null;
  final m = _turnKey.firstMatch(key);
  if (m == null) return null;
  return RouteIds.junction(
    int.parse(m.group(1)!),
    int.parse(m.group(3)!),
    int.parse(m.group(2)!),
  );
}

/// The OSM nodes of a turn's J item key: the junction, where it comes from, where it leaves to.
({int node, int from, int to})? turnNodes(String key) {
  final m = _turnKey.firstMatch(key);
  if (m == null) return null;
  return (
    node: int.parse(m.group(1)!),
    from: int.parse(m.group(2)!),
    to: int.parse(m.group(3)!),
  );
}

/// The share of the day's new cards the player's routes may take (SPEC §16.23 item 120), by how
/// City memory grew over the last [LearningConfig.yourRouteDays] and the days before.
double yourRoutesShareOf(
  List<CardState> cards,
  List<LogEntry> log,
  DateTime now,
) {
  double at(int daysAgo) =>
      cityMemoryAt(cards, log, now.subtract(Duration(days: daysAgo)));
  const days = LearningConfig.yourRouteDays;
  final (a, b, c) = (at(0), at(days), at(2 * days));
  return yourRoutesShare(gainNow: a - b, gainBefore: b - c);
}

/// The share of the day's new cards the player's routes may take (item 120): less while City
/// memory gained over the last [LearningConfig.yourRouteDays] ([gainNow]) falls below
/// [LearningConfig.yourRoutesSlowRate] of its gain over the days before ([gainBefore]).
double yourRoutesShare({required double gainNow, required double gainBefore}) =>
    gainBefore > 0 && gainNow < LearningConfig.yourRoutesSlowRate * gainBefore
    ? LearningConfig.yourRoutesSlowShare
    : LearningConfig.yourRoutesShare;

/// Your routes first (item 120): the open route items on the player's routes ([mineRoutes]) to
/// the front of [openRoutes], then the P items of their streets ([mineStreets], the main road
/// first) to the front of [newCandidates], together at most [cap]. [early] holds the route items
/// moved, for Today.
({List<String> newCandidates, List<String> openRoutes, List<String> early})
yourRoutesFirst({
  required List<String> newCandidates,
  required List<String> openRoutes,
  required Set<String> mineRoutes,
  required List<String> mineStreets,
  required int cap,
}) {
  final early = [
    for (final id in openRoutes)
      if (mineRoutes.contains(id)) id,
  ].take(cap).toList();
  final streets = mineStreets.toSet().take(max(0, cap - early.length)).toList();
  return (
    newCandidates: [
      ...streets,
      for (final id in newCandidates)
        if (!streets.contains(id)) id,
    ],
    openRoutes: [
      ...early,
      for (final id in openRoutes)
        if (!early.contains(id)) id,
    ],
    early: early,
  );
}
