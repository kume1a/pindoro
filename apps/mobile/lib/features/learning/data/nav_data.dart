import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/location.dart';
import 'package:pindoro/features/learning/data/drive_log.dart';
import 'package:pindoro/features/learning/data/drive_places.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/personal_landmarks.dart';
import 'package:pindoro/features/learning/data/route_book.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// The landmarks navigation may name at a junction (SPEC §16.23 item 117): the pack's
/// junction-item landmarks at their junctions and the player's own, hidden places left out.
final navLandmarksProvider = FutureProvider.autoDispose<List<RouteLandmark>>((
  ref,
) async {
  final pack = await ref.watch(packRepositoryProvider.future);
  final mine = await ref.watch(personalLandmarksProvider.future);
  final hidden = await ref.watch(learningDaoProvider).hiddenPlaces();
  final byId = {for (final l in pack.landmarks()) l.id: l};
  final out = <String, RouteLandmark>{};
  for (final item in pack.junctionItems()) {
    final l = byId[item.landmarkId];
    if (l == null || hidden.contains(l.id)) continue;
    out[l.id] ??= (
      id: l.id,
      name: l.nameKa,
      nameEn: l.nameEn,
      kind: l.kind,
      at: l.at,
      personal: false,
      junction: item.junctionId,
      onLeft: item.landmarkOnLeft,
    );
  }
  return [...out.values, ...personalRouteLandmarks(mine, pack.junctionNodes())];
});

/// The drive log as navigation's history (SPEC §16.23 items 113–114): each decision's last
/// failure and drives on the player's own, and the past drives, latest first.
final navHistoryProvider =
    FutureProvider.autoDispose<
      ({Map<String, DecisionHistory> decisions, List<PastDrive> past})
    >((ref) async {
      final log = ref.watch(driveLogDaoProvider);
      final learning = ref.watch(learningDaoProvider);
      final drives = await log.all();
      final rows = await log.decisions();
      final failures = await learning.lastFailures();
      return navHistory(
        drives: [
          for (final d in drives)
            (
              id: d.id,
              level: d.level,
              stretch: d.stretch,
              recoveries: d.recoveries,
            ),
        ],
        decisions: [
          for (final r in rows)
            (
              driveId: r.driveId,
              key: r.itemKey,
              ok: r.ok,
              help: r.help,
              recentHelp: r.recentHelp,
              at: r.at,
            ),
        ],
        failures: failures,
      );
    });

/// The way navigation plans from [here] to junction [to], from the nearer end of the road
/// [here] is on; null off the road graph or with no way there.
NavPlan? planFrom(
  RoadGraph graph,
  LatLng here,
  int to, {
  required Map<String, NamedStreet> streets,
  required List<RouteLandmark> landmarks,
  required Map<int, int> junctionNodes,
  required int toleranceKmh,
}) {
  final near = graph.edgeNear(here, 4 * LearningConfig.driveSnapM);
  if (near == null) return null;
  final from =
      distanceBetween(here, graph.at(near.from)) <
          distanceBetween(here, graph.at(near.to))
      ? near.from
      : near.to;
  return planNav(
    graph,
    NavCost(streets, toleranceKmh: toleranceKmh),
    from: from,
    to: to,
    streets: streets,
    landmarks: landmarks,
    junctionNodes: junctionNodes,
  );
}

/// Where the phone is (never asking for location) and the minutes from there to Home and Work
/// by the way a drive would take; each null when unknown, unset or out of reach.
final driveHereProvider =
    FutureProvider.autoDispose<({LatLng? here, int? home, int? work})>((
      ref,
    ) async {
      final located = await ref
          .watch(locationServiceProvider)
          .locate(ask: false);
      if (located is! Located) return (here: null, home: null, work: null);
      final here = located.position;
      final places = await ref.watch(drivePlacesProvider.future);
      final graph = await ref.watch(drivingGraphProvider.future);
      if (graph == null || (places.home == null && places.work == null)) {
        return (here: here, home: null, work: null);
      }
      final pack = await ref.watch(packRepositoryProvider.future);
      final streets = await ref.watch(cityStreetsProvider.future);
      final landmarks = await ref.watch(navLandmarksProvider.future);
      final settings = await ref.watch(settingsDaoProvider).read();
      // ponytail: two route plans on the UI isolate; move to an isolate if the tab stutters.
      int? minutes(DriveTarget? place) {
        if (place == null) return null;
        final plan = planFrom(
          graph,
          here,
          place.junction,
          streets: streets,
          landmarks: landmarks,
          junctionNodes: pack.junctionNodes(),
          toleranceKmh: settings.speedToleranceKmh,
        );
        return plan == null ? null : (plan.seconds / 60).ceil();
      }

      return (
        here: here,
        home: minutes(places.home),
        work: minutes(places.work),
      );
    });

/// The junction nearest [at] within [LearningConfig.snapSearchM] that has a road and that
/// [keep] allows; null when none is that near.
int? nearestJunction(
  RoadGraph graph,
  LatLng at, {
  bool Function(int junction)? keep,
}) {
  int? best;
  var bestM = LearningConfig.snapSearchM;
  for (final MapEntry(key: id, value: p) in graph.junctions.entries) {
    final m = distanceBetween(at, p);
    if (m <= bestM &&
        graph.edgesAt(id).isNotEmpty &&
        (keep?.call(id) ?? true)) {
      (best, bestM) = (id, m);
    }
  }
  return best;
}

/// A spot picked on the map as a destination: the nearest junction on a named street.
DriveDest? destNear(
  RoadGraph graph,
  Map<String, NamedStreet> streets,
  LatLng at,
) {
  final j = nearestJunction(
    graph,
    at,
    keep: (j) => streetAt(graph, streets, j) != null,
  );
  return j == null
      ? null
      : (street: streetAt(graph, streets, j), place: null, junction: j);
}

/// The raion [at] lies in, among the pack's [districts].
District? raionAt(List<District> districts, LatLng at) => districts
    .where((d) => d.isRaion && boundaryContains(d.boundary, at))
    .firstOrNull;

/// The smallest district [at] lies in, for district cues and the drive screen.
District? districtAt(List<District> districts, LatLng at) {
  District? best;
  for (final d in districts) {
    if (!boundaryContains(d.boundary, at)) continue;
    if (best == null || d.areaM2 < best.areaM2) best = d;
  }
  return best;
}

/// How many introduced J [cards] turn at a junction inside [raion] (item 114's area check),
/// junctions found by OSM node through [byNode].
int jCardsIn(
  District raion,
  Iterable<CardState> cards,
  Map<int, int> byNode,
  RoadGraph graph,
) {
  var count = 0;
  for (final c in cards) {
    if (c.type != CardType.j) continue;
    final node = RegExp(r':n(\d+):').firstMatch(c.itemId)?.group(1);
    final junction = node == null ? null : byNode[int.parse(node)];
    if (junction == null) continue;
    if (boundaryContains(raion.boundary, graph.at(junction))) count++;
  }
  return count;
}
