import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

import 'vake_fixture.dart';

void main() {
  late RouteBook book;
  late RoadGraph graph;
  late Map<int, int> nodes;

  setUpAll(() {
    final vake = Vake.load();
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
}
