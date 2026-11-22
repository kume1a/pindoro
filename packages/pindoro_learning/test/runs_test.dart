import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

import 'vake_fixture.dart';

final _now = DateTime.utc(2026, 11, 16, 9);

/// A Known card [dueInH] hours from due, on a 10-day interval.
CardState _known(String itemId, {int dueInH = 1}) => CardState(
  itemId: itemId,
  phase: CardPhase.review,
  memory: Memory(
    stability: 30,
    difficulty: 5,
    lastReview: _now.subtract(const Duration(days: 10)),
  ),
  dueAt: _now.add(Duration(hours: dueInH)),
  lastRating: Rating.good,
  introAt: _now.subtract(const Duration(days: 30)),
);

void main() {
  late Vake vake;
  late Map<String, CardState> allKnown;

  setUpAll(() {
    vake = Vake.load();
    allKnown = {for (final id in vake.book.questions.keys) id: _known(id)};
  });

  Run? bookRun(
    Map<String, CardState> cards, {
    Iterable<Run> existing = const [],
  }) => nextBookRun(
    graph: vake.graph,
    junctionNodes: vake.nodes,
    book: vake.book,
    cards: cards,
    existing: existing,
    now: _now,
  );

  group('route-book runs (SPEC §16.7)', () {
    test('a near-due Known turn seeds a run whose best route drives it and '
        'other Known turns of the book', () {
      final run = bookRun(allKnown)!;
      expect(run.random, isFalse);
      expect(
        run.items.length,
        greaterThanOrEqualTo(LearningConfig.runMinItems),
      );
      expect(run.items.every(vake.book.questions.containsKey), isTrue);
      expect(run.id, runId(run.fromNode, run.toNode));
      final byNode = {for (final e in vake.nodes.entries) e.value: e.key};
      final route = vake.graph.shortestRoute(byNode[run.fromNode]!, {
        byNode[run.toNode]!,
      })!;
      expect(routeItems(route, vake.nodes, vake.book), run.items);
    });

    test('a turn a run already drives seeds no other; none without Known '
        'near-due turns', () {
      final first = bookRun(allKnown)!;
      final second = bookRun(allKnown, existing: [first]);
      expect(second, isNotNull);
      expect(second!.items.toSet().intersection({first.items.first}), isEmpty);
      expect(bookRun(const {}), isNull);
      final farFromDue = {
        for (final id in allKnown.keys) id: _known(id, dueInH: 24 * 20),
      };
      expect(bookRun(farFromDue), isNull);
    });
  });

  group('random pairs (SPEC §3 R)', () {
    Run? randomRun({
      bool gatewayPhase = true,
      Iterable<Run> existing = const [],
    }) => nextRandomRun(
      graph: vake.graph,
      junctionNodes: vake.nodes,
      book: vake.book,
      knownParts: vake.streets.keys.toSet(),
      existing: existing,
      gatewayPhase: gatewayPhase,
      now: _now,
      seed: 7,
    );

    test('weekly once the gateway phase has begun, between Known streets '
        '1.5–5 km apart', () {
      expect(randomRun(gatewayPhase: false), isNull);
      final run = randomRun()!;
      expect(run.random, isTrue);
      final byNode = {for (final e in vake.nodes.entries) e.value: e.key};
      final apart = distanceBetween(
        vake.graph.at(byNode[run.fromNode]!),
        vake.graph.at(byNode[run.toNode]!),
      );
      expect(
        apart,
        inInclusiveRange(
          LearningConfig.randomRunMinM,
          LearningConfig.randomRunMaxM,
        ),
      );
      final recent = (
        id: 'n1:n2',
        fromNode: 1,
        toNode: 2,
        random: true,
        items: const <String>[],
        createdAt: _now.subtract(const Duration(days: 3)),
      );
      expect(randomRun(existing: [recent]), isNull);
      expect(
        randomRun(
          existing: [
            (
              id: recent.id,
              fromNode: 1,
              toNode: 2,
              random: true,
              items: const <String>[],
              createdAt: _now.subtract(const Duration(days: 7)),
            ),
          ],
        ),
        isNotNull,
      );
    });
  });

  test('a run\'s ends: its junctions, the best route and its first and last '
      'streets; a surprise end lies 1.5–5 km off on a Known street', () {
    final run = bookRun(allKnown)!;
    final byNode = {for (final e in vake.nodes.entries) e.value: e.key};
    final ends = runEnds(run, vake.graph, byNode, vake.streets)!;
    expect(vake.nodes[ends.from], run.fromNode);
    expect(ends.best.junctions.last, ends.to);
    expect(ends.fromStreet, vake.streets[ends.best.edges.first.streetId]);
    expect(
      runEnds(
        (
          id: 'n0:n0',
          fromNode: 0,
          toNode: 0,
          random: true,
          items: const [],
          createdAt: _now,
        ),
        vake.graph,
        byNode,
        vake.streets,
      ),
      isNull,
    );
    final from = vake.graph.at(ends.from);
    final surprises = surpriseEnds(
      graph: vake.graph,
      junctionNodes: vake.nodes,
      knownParts: vake.streets.keys.toSet(),
      from: from,
      seed: 3,
    );
    expect(surprises, isNotEmpty);
    for (final end in surprises) {
      expect(
        distanceBetween(from, vake.graph.at(end)),
        inInclusiveRange(
          LearningConfig.randomRunMinM,
          LearningConfig.randomRunMaxM,
        ),
      );
    }
  });

  test('a random pair opens at once, a book run once all its turns are Known, '
      'neither twice', () {
    final run = bookRun(allKnown)!;
    final random = (
      id: 'n1:n2',
      fromNode: 1,
      toNode: 2,
      random: true,
      items: [run.items.first],
      createdAt: _now,
    );
    expect(openRecitals([run, random], cards: const {}, now: _now), [
      CardType.r.item(random.id),
    ]);
    expect(openRecitals([run, random], cards: allKnown, now: _now), [
      CardType.r.item(run.id),
      CardType.r.item(random.id),
    ]);
    expect(
      openRecitals(
        [run],
        cards: {...allKnown, CardType.r.item(run.id): _known('R:${run.id}')},
        now: _now,
      ),
      isEmpty,
    );
  });

  test('implicit evidence: a failure reviews a near-due J card as Again; a '
      'success or a card not near due only logs', () {
    final card = _known('J:n1:n2:n3');
    final failed = implicitReview(
      card,
      ok: false,
      now: _now,
      source: ReviewSource.recital,
    )!;
    expect(failed.log.rating, Rating.again);
    expect(failed.log.format, ReviewFormat.recital);
    expect(failed.card.lapses, 1);
    expect(
      implicitReview(card, ok: true, now: _now, source: ReviewSource.drive),
      isNull,
    );
    expect(
      implicitReview(
        _known('J:n1:n2:n3', dueInH: 24 * 20),
        ok: false,
        now: _now,
        source: ReviewSource.drive,
      ),
      isNull,
    );
    expect(
      implicitReview(null, ok: false, now: _now, source: ReviewSource.drive),
      isNull,
    );
  });
}
