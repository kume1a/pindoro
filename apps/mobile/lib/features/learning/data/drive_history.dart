import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/drive_log.dart';
import 'package:pindoro/features/learning/data/drive_places.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/nav_data.dart';
import 'package:pindoro/features/learning/data/route_book.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// A route's ends as keys (SPEC §16.23 items 120–123): `home`, `work`, a pack place `p:<id>` or
/// a street `s:<id>`; a route is `<from>→<to>`.
const String routeArrow = '→';

/// The end key of a drive at [at]: Home or Work within [LearningConfig.placeNearM], else the
/// pack [place], else the [street].
String? endKey(
  LatLng? at, {
  required ({DriveTarget? home, DriveTarget? work}) anchors,
  required RoadGraph graph,
  String? place,
  String? street,
}) {
  bool near(DriveTarget? t) =>
      at != null &&
      t != null &&
      distanceBetween(at, graph.at(t.junction)) <= LearningConfig.placeNearM;
  if (near(anchors.home)) return 'home';
  if (near(anchors.work)) return 'work';
  if (place != null) return 'p:$place';
  if (street != null) return 's:$street';
  return null;
}

/// The drive log as the drive goal, Progress and Today read it: the drives (latest first), each
/// summed up, and their decisions by drive id.
typedef DriveHistory = ({
  List<DriveRow> drives,
  List<DriveSummary> summaries,
  Map<String, List<DriveDecisionRow>> decisions,
});

/// The drive log with each drive's route keyed by Home and Work as set now. Saving a drive
/// invalidates it.
final driveHistoryProvider = FutureProvider.autoDispose<DriveHistory>((
  ref,
) async {
  final log = ref.watch(driveLogDaoProvider);
  final graphFuture = ref.watch(drivingGraphProvider.future);
  final byNodeFuture = ref.watch(junctionsByNodeProvider.future);
  final streetsFuture = ref.watch(cityStreetsProvider.future);
  final anchorsFuture = ref.watch(drivePlacesProvider.future);
  final drives = await log.all();
  final rows = await log.decisions();
  final graph = await graphFuture;
  final byNode = await byNodeFuture;
  final streets = await streetsFuture;
  final anchors = await anchorsFuture;
  final decisions = <String, List<DriveDecisionRow>>{};
  for (final r in rows) {
    decisions.putIfAbsent(r.driveId, () => []).add(r);
  }
  for (final list in decisions.values) {
    list.sort((a, b) => a.seq.compareTo(b.seq));
  }
  String? key(int? node, {String? place, String? street}) {
    final junction = byNode[node];
    if (graph == null || junction == null) return null;
    return endKey(
      graph.at(junction),
      anchors: anchors,
      graph: graph,
      place: place,
      street:
          street ??
          graph
              .edgesAt(junction)
              .map((e) => streets[e.streetId]?.id)
              .nonNulls
              .firstOrNull,
    );
  }

  return (
    drives: drives,
    decisions: decisions,
    summaries: [
      for (final d in drives)
        () {
          final to = key(
            d.targetNode,
            place: d.targetPlace,
            street: streets[d.targetStreet]?.id ?? d.targetStreet,
          );
          final from = key(d.startNode);
          return (
            startedAt: d.startedAt,
            level: d.level,
            mostHelp: d.mostHelp ?? (d.rescued ? DriveLevel.guided : d.level),
            arrived: d.outcome == DriveOutcome.arrived,
            route: from == null || to == null ? null : '$from$routeArrow$to',
            destination: to,
            stretch: d.stretch,
            recoveries: d.recoveries,
          );
        }(),
    ],
  );
});

/// This week's drive goal (SPEC §16.23 item 122).
final driveWeekProvider = FutureProvider.autoDispose((ref) async {
  final history = await ref.watch(driveHistoryProvider.future);
  return driveWeek(history.summaries, ref.watch(clockProvider)());
});

/// Your routes first (SPEC §16.23 items 119–120): the route book's J items on routes driven
/// [LearningConfig.yourRouteDrives] times in [LearningConfig.yourRouteDays] or between Home and
/// Work, and the other way through habitual corridors; with their streets (ids), the main road
/// first. Empty for a pack without route items.
final yourRouteItemsProvider =
    FutureProvider.autoDispose<({Set<String> routes, List<String> streets})>((
      ref,
    ) async {
      final history = await ref.watch(driveHistoryProvider.future);
      final book = await ref.watch(routeBookProvider.future);
      final now = ref.watch(clockProvider)();
      final keys = <String>{};
      final yours = yourRoutes(history.summaries, now);
      for (final (i, d) in history.drives.indexed) {
        if (!yours.contains(history.summaries[i].route) ||
            now.difference(d.startedAt).inDays >=
                LearningConfig.yourRouteDays) {
          continue;
        }
        for (final r in history.decisions[d.id] ?? const <DriveDecisionRow>[]) {
          if (r.itemKey case final k?) keys.add(k);
        }
      }
      keys.addAll(await _homeWorkKeys(ref));
      final passes = [
        for (final list in history.decisions.values)
          for (final r in list)
            if (r.itemKey case final k?) (key: k, at: r.at),
      ];
      keys.addAll(habitualKeys(passes, now).map(reverseTurn).nonNulls);
      final streets = await ref.watch(cityStreetsProvider.future);
      final mine = [
        for (final c in book.candidates)
          if (keys.contains(c.itemId)) c,
      ];
      final ids = {for (final c in mine) ...c.known};
      return (
        routes: {for (final c in mine) c.itemId},
        streets: ids.toList()
          ..sort((a, b) {
            int rank(String id) => switch (streets[id]) {
              final s? => Curriculum.classRank(s),
              null => RoadBand.values.length,
            };
            final byRank = rank(a).compareTo(rank(b));
            return byRank != 0 ? byRank : a.compareTo(b);
          }),
      );
    });

/// The decisions between Home and Work, both ways, by the routes navigation would take.
Future<Set<String>> _homeWorkKeys(Ref ref) async {
  final anchors = await ref.watch(drivePlacesProvider.future);
  final home = anchors.home, work = anchors.work;
  final graph = await ref.watch(drivingGraphProvider.future);
  if (home == null || work == null || graph == null) return const {};
  final pack = await ref.watch(packRepositoryProvider.future);
  final streets = await ref.watch(cityStreetsProvider.future);
  final settings = await ref.watch(settingsProvider.future);
  final cost = NavCost(streets, toleranceKmh: settings.speedToleranceKmh);
  return {
    for (final (from, to) in [(home, work), (work, home)])
      ...?planNav(
        graph,
        cost,
        from: from.junction,
        to: to.junction,
        streets: streets,
        junctionNodes: pack.junctionNodes(),
      )?.decisions.map((d) => d.key).nonNulls,
  };
}

/// The drive to go through (Today, item 121): the latest drive ended in the last
/// [LearningConfig.debriefOfferHours] and not gone through yet; null without one.
final pendingDebriefProvider = FutureProvider.autoDispose<String?>((ref) async {
  final log = ref.watch(driveLogDaoProvider);
  final now = ref.watch(clockProvider)();
  final latest = (await log.all()).firstOrNull;
  if (latest == null ||
      now.difference(latest.endedAt).inHours >=
          LearningConfig.debriefOfferHours) {
    return null;
  }
  final done = await log.events(DriveEventKind.debrief);
  if (done.any((e) => e.driveId == latest.id)) return null;
  final turns = debriefTurns([
    for (final r in await log.decisionsOf(latest.id))
      if (r.itemKey case final key?)
        (
          seq: r.seq,
          key: key,
          mark: turnMark(
            ok: r.ok,
            help: r.help,
            recentHelp: r.recentHelp,
            hesitated: r.hesitated,
          ),
          keyTurn: r.keyTurn,
        ),
  ]);
  return turns.isEmpty ? null : latest.id;
});

/// A frequent route on Progress and Today (SPEC §16.23 items 122–123): its key, drives and
/// level by month, the level of its last drive, the level it would be suggested now and how
/// many of its turns are the player's.
typedef RouteLevels = ({
  String route,
  int drives,
  RouteMonths months,
  DriveLevel last,
  DriveLevel suggested,
  int yours,
  int turns,
});

/// The frequent routes, the most driven first, each with its suggestion from its latest drive's
/// decisions.
final routeLevelsProvider = FutureProvider.autoDispose<List<RouteLevels>>((
  ref,
) async {
  final history = await ref.watch(driveHistoryProvider.future);
  final nav = await ref.watch(navHistoryProvider.future);
  final graph = await ref.watch(drivingGraphProvider.future);
  final byNode = await ref.watch(junctionsByNodeProvider.future);
  final pack = await ref.watch(packRepositoryProvider.future);
  final learning = ref.watch(learningDaoProvider);
  final now = ref.watch(clockProvider)();
  final cards = {
    for (final c in await learning.cards())
      if (c.type == CardType.j) c.itemId: c,
  };
  final out = <RouteLevels>[];
  for (final r in frequentRoutes(history.summaries)) {
    final i = history.summaries.indexWhere((s) => s.route == r.route);
    final drive = history.drives[i];
    final keys = [
      for (final d in history.decisions[drive.id] ?? const <DriveDecisionRow>[])
        if (d.planned) d.itemKey,
    ];
    final target = byNode[drive.targetNode];
    final raion = target == null || graph == null
        ? null
        : raionAt(pack.districts(), graph.at(target));
    final s = routeSuggestion(
      keys: keys,
      cards: cards,
      history: nav.decisions,
      past: nav.past,
      areaJ: raion == null || graph == null
          ? 0
          : jCardsIn(raion, cards.values, byNode, graph),
      now: now,
    );
    out.add((
      route: r.route,
      drives: r.drives,
      months: r.months,
      last: drive.level,
      suggested: s.level,
      yours: keys.where(s.silent.contains).length,
      turns: keys.length,
    ));
  }
  return out;
});

/// This week's line on Progress (item 123): drives without help, new places, and the share of
/// turns taken on the player's own; null before any drive this week.
final driveWeekLineProvider =
    FutureProvider.autoDispose<({int drives, int places, double? own})?>((
      ref,
    ) async {
      final history = await ref.watch(driveHistoryProvider.future);
      final now = ref.watch(clockProvider)();
      final week = weekOf(now);
      final marks = <TurnMark?>[];
      var any = false;
      for (final d in history.drives) {
        if (d.startedAt.isBefore(week)) continue;
        any = true;
        for (final r in history.decisions[d.id] ?? const <DriveDecisionRow>[]) {
          marks.add(
            turnMark(
              ok: r.ok,
              help: r.help,
              recentHelp: r.recentHelp,
              hesitated: r.hesitated,
            ),
          );
        }
      }
      if (!any) return null;
      final goal = driveWeek(history.summaries, now);
      final free = history.summaries
          .where((s) => !s.startedAt.isBefore(week) && withoutHelp(s))
          .length;
      return (drives: free, places: goal.week.newPlaces, own: ownShare(marks));
    });

/// The J cards drives reviewed as a success this month (Progress's City memory line, board
/// V32-70).
final driveReviewsThisMonthProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  final now = ref.watch(clockProvider)().toLocal();
  final log = await ref
      .watch(learningDaoProvider)
      .log(since: DateTime(now.year, now.month));
  return log
      .where((e) => e.source == ReviewSource.drive && e.rating.isSuccess)
      .length;
});

/// This week's planned drives (item 122, "Pick your two drives"): the routes picked, possibly
/// none ("Not this week"); null until planned this week.
typedef DrivePlan = ({DateTime week, List<String> routes});

final drivePlanProvider = FutureProvider.autoDispose<DrivePlan?>((ref) async {
  final settings = await ref.watch(settingsProvider.future);
  final now = ref.watch(clockProvider)();
  final plan = decodeDrivePlan(settings.drivePlan);
  return plan != null && plan.week == weekOf(now) ? plan : null;
});

String encodeDrivePlan(DrivePlan plan) =>
    jsonEncode({'week': plan.week.toIso8601String(), 'routes': plan.routes});

DrivePlan? decodeDrivePlan(String? json) {
  if (json == null) return null;
  return switch (jsonDecode(json)) {
    {'week': final String week, 'routes': final List<Object?> routes} => (
      week: DateTime.parse(week),
      routes: routes.whereType<String>().toList(),
    ),
    _ => null,
  };
}
