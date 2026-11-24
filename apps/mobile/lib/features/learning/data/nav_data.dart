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

extension NavPlanMinutes on NavPlan {
  /// The drive's time in whole minutes, rounded up.
  int get minutes => (seconds / 60).ceil();
}

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

/// The ways navigation offers from [here] to the stops [to] through the stops on the way [via]
/// (up to [count]: the quickest first, both sides of the road when a place has two, items 132,
/// 134), from the nearer end of the road [here] is on; none off the road graph or with no way
/// there.
List<NavPlan> plansFrom(
  RoadGraph graph,
  LatLng here,
  List<NavStop> to, {
  List<NavStop> via = const [],
  required Map<String, NamedStreet> streets,
  required List<RouteLandmark> landmarks,
  required Map<int, int> junctionNodes,
  required int toleranceKmh,
  int count = LearningConfig.navOptions,
}) {
  final near = graph.edgeNear(here, LearningConfig.navPlanFromM);
  if (near == null) return const [];
  final from =
      distanceBetween(here, graph.at(near.from)) <
          distanceBetween(here, graph.at(near.to))
      ? near.from
      : near.to;
  return planStopOptions(
    graph,
    NavCost(streets, toleranceKmh: toleranceKmh),
    from: from,
    stops: to,
    via: via,
    streets: streets,
    landmarks: landmarks,
    junctionNodes: junctionNodes,
    count: count,
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
      if (places.home == null && places.work == null) {
        return (here: here, home: null, work: null);
      }
      final minutes = await _minutesFrom(ref, here);
      return (
        here: here,
        home: minutes(places.home),
        work: minutes(places.work),
      );
    });

/// The minutes from where the phone is to [target] by the way a drive would take (a place
/// tapped on the map, item 132); null when unknown or out of reach.
final driveMinutesProvider = FutureProvider.autoDispose
    .family<int?, DriveTarget>((ref, target) async {
      final here = (await ref.watch(driveHereProvider.future)).here;
      return here == null ? null : (await _minutesFrom(ref, here))(target);
    });

/// The minutes from [here] to a destination by the way a drive would take; null for none.
Future<int? Function(DriveTarget?)> _minutesFrom(Ref ref, LatLng here) async {
  final graph = await ref.watch(drivingGraphProvider.future);
  final pack = await ref.watch(packRepositoryProvider.future);
  final streets = await ref.watch(cityStreetsProvider.future);
  final landmarks = await ref.watch(navLandmarksProvider.future);
  final settings = await ref.watch(settingsDaoProvider).read();
  // ponytail: route plans on the UI isolate; move to an isolate if the tab stutters.
  return (DriveTarget? place) => graph == null || place == null
      ? null
      : plansFrom(
          graph,
          here,
          stopsOf(graph, place),
          streets: streets,
          landmarks: landmarks,
          junctionNodes: pack.junctionNodes(),
          toleranceKmh: settings.speedToleranceKmh,
          count: 1,
        ).firstOrNull?.minutes;
}

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

/// A spot picked on the map as a destination (item 132): the spot itself, named by the street
/// of the road it is by; null with no road within [LearningConfig.navStopReachM].
DriveDest? destNear(
  RoadGraph graph,
  Map<String, NamedStreet> streets,
  LatLng at,
) => switch (resolveDest(graph, streets, (
  street: null,
  place: null,
  junction: null,
  at: at,
))) {
  final t? => (street: t.street, place: null, junction: null, at: at),
  null => null,
};

/// The raion [at] lies in, among the pack's [districts].
District? raionAt(List<District> districts, LatLng at) => districts
    .where((d) => d.isRaion && boundaryContains(d.boundary, at))
    .firstOrNull;

/// The smallest district [at] lies in, to tell a destination found by name apart (the drive's
/// cues use [raionAt]).
District? districtAt(List<District> districts, LatLng at) {
  District? best;
  for (final d in districts) {
    if (!boundaryContains(d.boundary, at)) continue;
    if (best == null || d.areaM2 < best.areaM2) best = d;
  }
  return best;
}

/// A turn's J item id's junction node (`...:n123:...`).
final RegExp _turnNode = RegExp(r':n(\d+):');

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
    final node = _turnNode.firstMatch(c.itemId)?.group(1);
    final junction = node == null ? null : byNode[int.parse(node)];
    if (junction == null) continue;
    if (boundaryContains(raion.boundary, graph.at(junction))) count++;
  }
  return count;
}
