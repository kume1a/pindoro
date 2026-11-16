import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

import 'vake_fixture.dart';

void main() {
  late Vake vake;
  late RouteBook book;
  late RoadGraph graph;
  late Map<int, int> nodes;

  setUpAll(() {
    vake = Vake.load();
    (book, graph, nodes) = (vake.book, vake.graph, vake.nodes);
  });

  test('every J card offers only the junction\'s legal exits, the right one '
      'among them (PLAN M5 accept)', () {
    final turns = book.questions.values.whereType<TurnQuestion>().toList();
    expect(turns, isNotEmpty);
    for (final q in turns) {
      final legal = {
        for (final e in graph.legalExits(q.junction, approach: q.approach))
          e.id,
      };
      expect(q.exits.values.every((e) => legal.contains(e.id)), isTrue);
      expect(q.exits[q.correct], isNotNull);
      expect(q.exits.length, greaterThanOrEqualTo(2));
      expect(q.itemId, startsWith('J:n${nodes[q.junction]}:n'));
    }
  });

  test('the book holds gateways, connections and landmark cards, each with '
      'what opens it', () {
    final types = {for (final id in book.questions.keys) CardType.ofItem(id)};
    expect(
      types,
      containsAll([CardType.j, CardType.g, CardType.c, CardType.l]),
    );
    expect(
      book.candidates.map((c) => c.itemId).toSet(),
      book.questions.keys.toSet(),
    );
    final l2 = book.questions.values.whereType<LandmarkQuestion>().firstWhere(
      (q) => q.n == 2,
    );
    expect(l2.junctions, contains(l2.junction));
  });

  test('a photo at a turn\'s approach asks S2 that turn and S3 its place; one '
      'S1 per grid street; a photo off the pack is skipped', () {
    final turns = book.questions.values.whereType<TurnQuestion>().toList();
    SceneImage photo(String id, int junctionNode, int approachNode) =>
        SceneImage(
          id: id,
          junctionNode: junctionNode,
          approachNode: approachNode,
          at: const LatLng(41.71, 44.76),
          heading: 0,
          distanceM: 30,
          source: 'mapillary',
          licence: 'CC BY-SA 4.0',
          author: 'someone',
        );
    final photos = [
      for (final (i, q) in turns.indexed)
        photo('m$i', nodes[q.junction]!, nodes[q.approach.other(q.junction)]!),
      photo('m-off', -1, -2),
    ];
    final scenes = buildRouteBook(
      graph: graph,
      junctionNodes: nodes,
      items: vake.items,
      landmarks: vake.landmarks,
      bridges: const [],
      streets: vake.streets,
      curriculum: vake.curriculum,
      scenes: photos,
    ).questions.values.whereType<SceneQuestion>().toList();
    expect(scenes.where((q) => q.image.id == 'm-off'), isEmpty);
    final s2 = scenes.where((q) => q.n == 2).toList();
    expect(s2, isNotEmpty);
    for (final q in s2) {
      final legal = {
        for (final e in graph.legalExits(q.junction, approach: q.approach))
          e.id,
      };
      expect(legal, contains(q.exits[q.correct]!.id));
      expect(q.destChunk, isNotNull);
    }
    final s1 = scenes.where((q) => q.n == 1).map((q) => q.street!).toList();
    expect(s1, isNotEmpty);
    expect(s1.toSet().length, s1.length);
    expect(
      s1.every((s) => vake.curriculum.tierOf(s.id) != StreetTier.c),
      isTrue,
    );
    expect(scenes.where((q) => q.n == 3).length, greaterThan(s1.length));
  });
}
