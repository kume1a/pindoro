import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/features/learning/data/drive_log.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/personal_landmarks.dart';
import 'package:pindoro/features/learning/data/route_book.dart';
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
