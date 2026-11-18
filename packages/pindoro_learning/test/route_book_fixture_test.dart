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

  test('a chain or a repeated name is told apart by its street', () {
    final places = book.questions.values.whereType<LandmarkQuestion>().where(
      (q) => q.n == 1,
    );
    final chain = places.firstWhere((q) => q.ambiguous);
    expect(chain.street, isNotNull);
    final names = [for (final q in places) q.landmark.name];
    final unique = places.where(
      (q) => names.where((n) => n == q.landmark.name).length == 1,
    );
    expect(unique.where((q) => !q.ambiguous), isNotEmpty);
    final fuel = places.where((q) => q.landmark.kind == 'fuel');
    expect(fuel, isNotEmpty);
    expect(
      fuel.where((q) => !q.ambiguous || q.street == null),
      isEmpty,
      reason: 'every station, a brandless one too, is named with its street',
    );
  });

  test('two places of one name on one street are told apart by their '
      'junction’s other street, with no L2 to give it away', () {
    final places = book.questions.values.whereType<LandmarkQuestion>().where(
      (q) => q.n == 1,
    );
    final twins = places.where((q) => q.crossStreet != null).toList();
    expect(twins, isNotEmpty);
    for (final q in twins) {
      final same = twins.where(
        (o) => o.landmark.name == q.landmark.name && o.street == q.street,
      );
      expect(same, hasLength(greaterThan(1)), reason: q.landmark.name);
      expect(same.map((o) => o.crossStreet).toSet(), hasLength(same.length));
      expect(q.crossStreet, isNot(q.street));
      expect(
        book.questions[RouteIds.landmark(q.landmark.id, 2)],
        isNull,
        reason: q.landmark.name,
      );
      expect(book.questions[RouteIds.landmark(q.landmark.id, 3)], isNotNull);
    }
    expect(
      places.where((q) => q.crossStreet == null && q.ambiguous),
      isNotEmpty,
      reason: 'one of its name on the street needs no corner',
    );
  });
}
