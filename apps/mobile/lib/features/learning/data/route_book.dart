import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/features/learning/data/personal_landmarks.dart';
import 'package:pindoro/features/learning/data/today_plan.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// The open pack's route items (SPEC §3, format 5) and the player's own
/// landmarks: what opens each and what each asks; empty for an older pack.
// ponytail: built on the UI isolate (a second or so for Tbilisi's crossings);
// move it to an isolate if Today stutters on a pack change.
final routeBookProvider = FutureProvider<RouteBook>((ref) async {
  final pack = await ref.watch(packRepositoryProvider.future);
  final streets = await ref.watch(cityStreetsProvider.future);
  final curriculum = await ref.watch(curriculumProvider.future);
  final mine = await ref.watch(personalLandmarksProvider.future);
  final graph = pack.roadGraph();
  if (graph == null || pack.junctionItems().isEmpty) {
    return (
      candidates: const <RouteCandidate>[],
      questions: const <String, RouteQuestion>{},
    );
  }
  final nodes = pack.junctionNodes();
  return buildRouteBook(
    graph: graph,
    junctionNodes: nodes,
    items: pack.junctionItems(),
    landmarks: pack.landmarks(),
    bridges: pack.bridges(),
    streets: streets,
    curriculum: curriculum,
    personal: [
      for (final l in mine)
        (
          id: l.id,
          name: l.name,
          kind: l.kind,
          at: LatLng(l.lat, l.lon),
          personal: true,
          junction: junctionOfNode(nodes, int.parse(l.junctionId.substring(1))),
          onLeft: l.side == 'left',
        ),
    ],
  );
});
