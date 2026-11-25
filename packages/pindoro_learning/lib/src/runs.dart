import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'cards.dart';
import 'constants.dart';
import 'route_questions.dart';
import 'routes.dart';
import 'labels.dart';

/// A recital's A → B (SPEC §3 R, §16.7): a route-book run or a weekly [random] pair. Its ends are
/// OSM nodes of pack junctions, so it survives pack rebuilds; [items] are the J items of the book
/// its best route drives. Its card is `R:<id>`.
typedef Run = ({
  String id,
  int fromNode,
  int toNode,
  bool random,
  List<String> items,
  DateTime createdAt,
});

String runId(int fromNode, int toNode) => 'n$fromNode:n$toNode';

/// The book's J items [route] drives: each junction it passes with its way in and out.
List<String> routeItems(
  Route route,
  Map<int, int> junctionNodes,
  RouteBook book,
) => [
  for (var i = 1; i < route.junctions.length - 1; i++)
    if (_turnId(route, i, junctionNodes) case final id?
        when book.questions.containsKey(id))
      id,
];

String? _turnId(Route route, int i, Map<int, int> nodes) {
  final at = route.junctions[i];
  final node = nodes[at];
  final from = nodes[route.junctions[i - 1]];
  final to = nodes[route.junctions[i + 1]];
  return node == null || from == null || to == null
      ? null
      : RouteIds.junction(node, from, to);
}

/// The next route-book run (SPEC §16.7, §16.15): for the first J card (by due date) that is Known
/// and near due and that no run in [existing] drives, from about [LearningConfig.runLeadM] back
/// along its approach street to about as far on along its exit street, on the best legal route.
/// Kept when that route drives the card's turn and at least [LearningConfig.runMinItems] J items
/// of the book, every one Known. Null when no card makes one.
Run? nextBookRun({
  required RoadGraph graph,
  required Map<int, int> junctionNodes,
  required RouteBook book,
  required Map<String, CardState> cards,
  required Iterable<Run> existing,
  required DateTime now,
}) {
  final covered = {for (final r in existing) ...r.items};
  bool known(String id) => switch (cards[id]) {
    final c? => isKnown(c, now),
    null => false,
  };
  final seeds = [
    for (final q in book.questions.values)
      if (q is TurnQuestion &&
          !covered.contains(q.itemId) &&
          known(q.itemId) &&
          isNearDue(cards[q.itemId]!, now))
        q,
  ]..sort((a, b) => cards[a.itemId]!.dueAt!.compareTo(cards[b.itemId]!.dueAt!));
  for (final q in seeds) {
    final into = {...?q.approachStreet?.parts.map((p) => p.id)};
    final onto = {...?q.exitStreet?.parts.map((p) => p.id)};
    final exit = q.exits[q.correct]!;
    final from = _along(graph, q.junction, q.approach, into);
    final to = _along(graph, q.junction, exit, onto);
    final route = graph.shortestRoute(from, {to});
    final fromNode = junctionNodes[from];
    final toNode = junctionNodes[to];
    if (route == null || fromNode == null || toNode == null) continue;
    final items = routeItems(route, junctionNodes, book);
    if (items.contains(q.itemId) &&
        items.length >= LearningConfig.runMinItems &&
        items.every(known)) {
      return (
        id: runId(fromNode, toNode),
        fromNode: fromNode,
        toNode: toNode,
        random: false,
        items: items,
        createdAt: now,
      );
    }
  }
  return null;
}

/// The junction about [LearningConfig.runLeadM] from [junction] along [edge] and on along the
/// street parts [parts], never passing a junction twice.
int _along(RoadGraph graph, int junction, RoadEdge edge, Set<String> parts) {
  var on = edge;
  var at = edge.other(junction);
  var walked = edge.lengthM;
  final seen = {junction, at};
  while (walked < LearningConfig.runLeadM) {
    final next = graph
        .edgesAt(at)
        .where(
          (e) =>
              e.id != on.id &&
              parts.contains(e.streetId) &&
              !seen.contains(e.other(at)),
        )
        .firstOrNull;
    if (next == null) break;
    walked += next.lengthM;
    on = next;
    at = next.other(at);
    seen.add(at);
  }
  return at;
}

/// This week's random pair (SPEC §3 R): once the gateway phase has begun ([gatewayPhase]) and the
/// newest random run in [existing] is [LearningConfig.randomRunEveryDays] old, two junctions on
/// the Known streets [knownParts] (part ids) [LearningConfig.randomRunMinM]–
/// [LearningConfig.randomRunMaxM] apart with a legal route between them, seeded by [seed]. Null
/// when it isn't time or no pair is found in [LearningConfig.randomRunTries] draws.
Run? nextRandomRun({
  required RoadGraph graph,
  required Map<int, int> junctionNodes,
  required RouteBook book,
  required Set<String> knownParts,
  required Iterable<Run> existing,
  required bool gatewayPhase,
  required DateTime now,
  required int seed,
}) {
  final last = existing
      .where((r) => r.random)
      .map((r) => r.createdAt)
      .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
  if (!gatewayPhase ||
      (last != null &&
          now.difference(last).inDays < LearningConfig.randomRunEveryDays)) {
    return null;
  }
  final ends = _knownEnds(graph, knownParts, junctionNodes);
  if (ends.length < 2) return null;
  final random = Random(seed);
  for (var i = 0; i < LearningConfig.randomRunTries; i++) {
    final a = ends[random.nextInt(ends.length)];
    final b = ends[random.nextInt(ends.length)];
    final apart = distanceBetween(graph.at(a), graph.at(b));
    if (apart < LearningConfig.randomRunMinM ||
        apart > LearningConfig.randomRunMaxM) {
      continue;
    }
    final route = graph.shortestRoute(a, {b});
    if (route == null) continue;
    final fromNode = junctionNodes[a]!;
    final toNode = junctionNodes[b]!;
    return (
      id: runId(fromNode, toNode),
      fromNode: fromNode,
      toNode: toNode,
      random: true,
      items: routeItems(route, junctionNodes, book),
      createdAt: now,
    );
  }
  return null;
}

/// The junctions on the Known streets [knownParts] that [junctionNodes] names, in id order.
List<int> _knownEnds(
  RoadGraph graph,
  Set<String> knownParts,
  Map<int, int> junctionNodes,
) => {
  for (final part in knownParts) ...graph.junctionsOfPart(part),
}.where(junctionNodes.containsKey).toList()..sort();

/// Surprise destinations (Surprise me), shuffled by [seed]: junctions on the Known streets
/// [knownParts] [LearningConfig.randomRunMinM]–[LearningConfig.randomRunMaxM] from [from]; the
/// drive takes the first whose route is the player's enough (SPEC §16.23 item 122).
List<int> surpriseEnds({
  required RoadGraph graph,
  required Map<int, int> junctionNodes,
  required Set<String> knownParts,
  required LatLng from,
  required int seed,
}) => [
  for (final j in _knownEnds(graph, knownParts, junctionNodes))
    if (distanceBetween(from, graph.at(j)) case final m
        when m >= LearningConfig.randomRunMinM &&
            m <= LearningConfig.randomRunMaxM)
      j,
]..shuffle(Random(seed));

/// A run's ends in a pack: its junctions, the best legal route between them and the first and
/// last named streets on it.
typedef RunEnds = ({
  int from,
  int to,
  Route best,
  NamedStreet fromStreet,
  NamedStreet toStreet,
});

/// [run]'s ends by the pack's junctions by OSM node ([junctionsByNode]) and [streets] by part
/// id; null when the pack lacks an end, a legal route or a named street on it.
RunEnds? runEnds(
  Run run,
  RoadGraph graph,
  Map<int, int> junctionsByNode,
  Map<String, NamedStreet> streets,
) {
  final from = junctionsByNode[run.fromNode];
  final to = junctionsByNode[run.toNode];
  final best = from == null || to == null
      ? null
      : graph.shortestRoute(from, {to});
  if (best == null) return null;
  final named = [for (final e in best.edges) ?streets[e.streetId]];
  if (named.isEmpty) return null;
  return (
    from: from!,
    to: to!,
    best: best,
    fromStreet: named.first,
    toStreet: named.last,
  );
}

/// R items open for their first recital (SPEC §3): a random pair at once, a route-book run once
/// every item it drives is Known; oldest first.
List<String> openRecitals(
  Iterable<Run> runs, {
  required Map<String, CardState> cards,
  required DateTime now,
}) => [
  for (final r
      in runs.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt)))
    if (!cards.containsKey(CardType.r.item(r.id)) &&
        (r.random ||
            r.items.every(
              (id) => switch (cards[id]) {
                final c? => isKnown(c, now),
                null => false,
              },
            )))
      CardType.r.item(r.id),
];
