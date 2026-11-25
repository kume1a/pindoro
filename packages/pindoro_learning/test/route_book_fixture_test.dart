import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

import 'vake_fixture.dart';

void main() {
  late RouteBook book;
  late RoadGraph graph;
  late Map<int, int> nodes;
  late Map<String, NamedStreet> streets;

  setUpAll(() {
    final vake = Vake.load();
    (book, graph, nodes, streets) = (
      vake.book,
      vake.graph,
      vake.nodes,
      vake.streets,
    );
  });

  Set<NamedStreet> streetsAt(int junction) => {
    for (final e in graph.edgesAt(junction)) ?streets[e.streetId],
  };
  String label(int junction) => (streetsAt(
    junction,
  ).map((s) => normaliseName(s.name)).toSet().toList()..sort()).join(' × ');
  bool names(String place, NamedStreet street) =>
      nameStems(street).any(normaliseName(place).contains);

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
      'corner, with no L2 to give it away', () {
    final places = book.questions.values
        .whereType<LandmarkQuestion>()
        .where((q) => q.n == 1 && !q.landmark.personal && q.street != null)
        .toList();
    final twins = [
      for (final q in places)
        if (places
                .where(
                  (o) =>
                      normaliseName(o.landmark.name) ==
                          normaliseName(q.landmark.name) &&
                      o.street == q.street,
                )
                .length >
            1)
          q,
    ];
    expect(twins, isNotEmpty);
    for (final q in twins) {
      expect(q.crossStreet, isNotNull, reason: q.landmark.name);
      expect(q.crossStreet, isNot(q.street));
      expect(
        book.questions[RouteIds.landmark(q.landmark.id, 2)],
        isNull,
        reason: q.landmark.name,
      );
    }
    final shown = {
      for (final q in twins) (q.landmark.name, q.street, q.crossStreet),
    };
    expect(shown, hasLength(twins.length), reason: 'no two read the same');
    expect(
      places.where((q) => q.crossStreet == null && q.ambiguous),
      isNotEmpty,
      reason: 'one of its name on the street needs no corner',
    );
  });

  test('a pick offers two or more choices that read apart: junctions by '
      'their streets, places by name', () {
    final picks = book.questions.values
        .whereType<LandmarkQuestion>()
        .where((q) => q.n > 1)
        .toList();
    expect(picks.where((q) => q.n == 2), isNotEmpty);
    expect(picks.where((q) => q.n == 3), isNotEmpty);
    for (final q in picks) {
      final read = q.n == 2
          ? q.junctions.map(label).toList()
          : q.places.map((l) => normaliseName(l.name)).toList();
      expect(read.length, greaterThanOrEqualTo(2), reason: q.itemId);
      expect(read.toSet(), hasLength(read.length), reason: '${q.itemId} $read');
      expect(read, everyElement(isNotEmpty));
      if (q.n == 2) expect(q.junctions, contains(q.junction));
      if (q.n == 3) expect(read, contains(normaliseName(q.landmark.name)));
    }
  });

  test("a place's L cards ask from the turn that carries it", () {
    final carriers = <String, Set<String?>>{};
    for (final q in book.questions.values.whereType<TurnQuestion>()) {
      if (q.landmark case final l?) {
        (carriers[l.id] ??= {}).add(q.approachStreet?.id);
      }
    }
    final cards = [
      for (final q in book.questions.values.whereType<LandmarkQuestion>())
        if (q.n > 1 && carriers.containsKey(q.landmark.id)) q,
    ];
    expect(cards, isNotEmpty);
    for (final q in cards) {
      expect(
        carriers[q.landmark.id],
        contains(q.approachStreet?.id),
        reason: q.itemId,
      );
    }
  });

  test('no card names a place that gives its answer street away', () {
    final named = [
      for (final q in book.questions.values.whereType<LandmarkQuestion>())
        if (q.n == 1 &&
            q.junction != null &&
            streetsAt(q.junction!).any((s) => names(q.landmark.name, s)))
          q,
    ];
    expect(named, isNotEmpty, reason: 'the fixture has a metro so named');
    for (final q in named) {
      expect(
        book.questions[RouteIds.landmark(q.landmark.id, 3)],
        isNull,
        reason: q.landmark.name,
      );
    }
    for (final q in book.questions.values.whereType<TurnQuestion>()) {
      if (q case TurnQuestion(
        :final landmark?,
        :final exitStreet?,
      ) when exitStreet != q.approachStreet) {
        expect(names(landmark.name, exitStreet), isFalse, reason: q.itemId);
      }
    }
  });
}
