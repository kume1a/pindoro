import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/features/drive/ui/drive_controller.dart';
import 'package:pindoro/features/drive/ui/past_drives_screen.dart';
import 'package:pindoro/features/learning/data/cards.dart';
import 'package:pindoro/features/learning/data/drive_log.dart';
import 'package:pindoro/features/learning/data/drive_places.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/nav_data.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// A turn the debrief goes through (SPEC §16.23 item 121, board V32-50): its J key, where it is
/// (the junction and the way in), what the driver did ([done]) and a good way on ([way]), the
/// ways on by direction for the recall's buttons ([exits]; null when two share one), its mark
/// and the landmark that names it.
typedef DebriefTurn = ({
  String key,
  int junction,
  RoadEdge approach,
  RoadEdge done,
  RoadEdge way,
  Map<Turn, RoadEdge>? exits,
  TurnMark? mark,
  RouteLandmark? landmark,
});

/// A drive as its debrief and Past drives show it: the [review] replayed from its track, the
/// turns to go through, every decision's mark on the map, the counts, the streets driven with
/// their cards, the missed turns to drill, whether Point to home is due, and the level the
/// route can try next time ([next], with the route's turns yours) when it has less help.
typedef DriveDebrief = ({
  DriveRow drive,
  DriveReview review,
  List<DebriefTurn> turns,
  List<({LatLng at, TurnMark mark})> marks,
  ({int own, int missed, int helped, int watched}) counts,
  List<({NamedStreet street, CardState? card})> streets,
  List<String> drill,
  bool point,
  bool recalled,
  ({DriveLevel level, int yours, int turns})? next,
});

/// [id]'s debrief; null once its track or destination is gone.
final driveDebriefProvider = FutureProvider.autoDispose
    .family<DriveDebrief?, String>((ref, id) async {
      final review = await ref.watch(pastDriveProvider(id).future);
      final log = ref.watch(driveLogDaoProvider);
      final drive = await log.drive(id);
      final graph = await ref.watch(drivingGraphProvider.future);
      if (review == null || drive == null || graph == null) return null;
      final rows = await log.decisionsOf(id);
      final byNode = await ref.watch(junctionsByNodeProvider.future);
      final streets = await ref.watch(cityStreetsProvider.future);
      final landmarks = await ref.watch(navLandmarksProvider.future);
      final streetCards = await ref.watch(streetCardsProvider.future);
      final learning = ref.watch(learningDaoProvider);
      final anchors = await ref.watch(drivePlacesProvider.future);
      final now = ref.watch(clockProvider)();
      final cards = {for (final c in await learning.cards()) c.itemId: c};
      final target = review.target.junction;

      RoadEdge? between(int a, int b) =>
          graph.edgesAt(a).where((e) => e.other(a) == b).firstOrNull;
      TurnMark? markOf(DriveDecisionRow r) => turnMark(
        ok: r.ok,
        help: r.help,
        recentHelp: r.recentHelp,
        hesitated: r.hesitated,
      );
      final logged = [
        for (final r in rows)
          if (r.itemKey case final key?)
            (seq: r.seq, key: key, mark: markOf(r), keyTurn: r.keyTurn),
      ];
      final turns = <DebriefTurn>[];
      for (final t in debriefTurns(logged)) {
        final nodes = turnNodes(t.key);
        final j = byNode[nodes?.node];
        final from = byNode[nodes?.from];
        final to = byNode[nodes?.to];
        if (j == null || from == null || to == null) continue;
        final approach = between(j, from);
        final done = between(j, to);
        if (approach == null || done == null) continue;
        final way =
            graph
                .shortestRoute(j, {target}, approach: approach)
                ?.edges
                .firstOrNull ??
            done;
        turns.add((
          key: t.key,
          junction: j,
          approach: approach,
          done: done,
          way: t.mark == TurnMark.again ? way : done,
          exits: exitsByTurn(graph, j, approach),
          mark: t.mark,
          landmark: _landmarkAt(graph, j, landmarks),
        ));
      }

      final marks = [
        for (final r in rows)
          if ((byNode[turnNodes(r.itemKey ?? '')?.node], markOf(r)) case (
            final j?,
            final mark?,
          ))
            (at: graph.at(j), mark: mark),
      ];
      int count(Set<TurnMark> kinds) =>
          marks.where((m) => kinds.contains(m.mark)).length;

      final driven = <String, NamedStreet>{};
      for (final e in review.match.path.edges) {
        if (streets[e.streetId] case final s?) {
          driven.putIfAbsent(s.id, () => s);
        }
      }

      final events = await log.events(DriveEventKind.point);
      final earlier = (await log.all()).where(
        (d) =>
            d.startedAt.isBefore(drive.startedAt) &&
            d.targetNode == drive.targetNode &&
            d.outcome == DriveOutcome.arrived,
      );
      final recalls = await log.events(DriveEventKind.debrief);

      return (
        drive: drive,
        review: review,
        turns: turns,
        marks: marks,
        counts: (
          own: count({TurnMark.good, TurnMark.hard}),
          missed: count({TurnMark.again}),
          helped: count({TurnMark.helped}),
          watched: count({TurnMark.watched}),
        ),
        streets: [
          for (final s in driven.values) (street: s, card: streetCards[s.id]),
        ],
        drill: [
          for (final t in turns)
            if (t.mark == TurnMark.again && cards.containsKey(t.key)) t.key,
        ],
        point:
            anchors.home != null &&
            drive.outcome == DriveOutcome.arrived &&
            earlier.isEmpty &&
            !events.any((e) => e.driveId == id),
        recalled: recalls.any((e) => e.driveId == id),
        next: await _next(ref, drive, rows, cards, graph, now),
      );
    });

/// The level the route can try next time (board V32-50 "Next time: try Quiet"): its suggestion
/// now, when that has less help than the drive had.
Future<({DriveLevel level, int yours, int turns})?> _next(
  Ref ref,
  DriveRow drive,
  List<DriveDecisionRow> rows,
  Map<String, CardState> cards,
  RoadGraph graph,
  DateTime now,
) async {
  final keys = [
    for (final r in rows)
      if (r.planned) r.itemKey,
  ];
  if (keys.isEmpty || drive.level == DriveLevel.off) return null;
  final history = await ref.watch(navHistoryProvider.future);
  final byNode = await ref.watch(junctionsByNodeProvider.future);
  final pack = await ref.watch(packRepositoryProvider.future);
  final target = byNode[drive.targetNode];
  final raion = target == null
      ? null
      : raionAt(pack.districts(), graph.at(target));
  final j = {
    for (final c in cards.values)
      if (c.type == CardType.j) c.itemId: c,
  };
  final s = routeSuggestion(
    keys: keys,
    cards: j,
    history: history.decisions,
    past: history.past,
    areaJ: raion == null ? 0 : jCardsIn(raion, j.values, byNode, graph),
    now: now,
  );
  if (s.level.index <= drive.level.index) return null;
  return (
    level: s.level,
    yours: keys.where(s.silent.contains).length,
    turns: keys.length,
  );
}

/// The landmark that names junction [j]: one placed at it, else the nearest within
/// [LearningConfig.landmarkAtM].
RouteLandmark? _landmarkAt(
  RoadGraph graph,
  int j,
  List<RouteLandmark> landmarks,
) {
  RouteLandmark? best;
  var bestM = LearningConfig.landmarkAtM;
  for (final l in landmarks) {
    if (l.junction == j) return l;
    final m = distanceBetween(graph.at(j), l.at);
    if (m <= bestM) (best, bestM) = (l, m);
  }
  return best;
}
