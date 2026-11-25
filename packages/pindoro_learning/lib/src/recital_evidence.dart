import 'package:pindoro_core/pindoro_core.dart';

import 'cards.dart';
import 'recital.dart';
import 'routes.dart';

/// What a recital or drive says about the junction cards (SPEC §4 implicit evidence, §5.3 step
/// 7): a right decision is evidence for the J item it drove ([ok]); a wrong one against every J
/// item at that junction from that approach. Only items in [routeItems]; an item met twice keeps
/// its worst outcome. G and B ids name no approach, so they get none.
List<({String itemId, bool ok})> recitalEvidence(
  RecitalResult result,
  Map<int, int> junctionNodes,
  Set<String> routeItems,
) {
  final outcome = <String, bool>{};
  void note(String id, bool ok) => outcome[id] = (outcome[id] ?? true) && ok;
  for (final d in result.decisions) {
    final approach = d.approach;
    if (approach == null) continue;
    final node = junctionNodes[d.junction];
    final from = junctionNodes[approach.other(d.junction)];
    if (node == null || from == null) continue;
    if (d.correct) {
      final exit = junctionNodes[d.exit.other(d.junction)];
      if (exit == null) continue;
      final id = RouteIds.junction(node, from, exit);
      if (routeItems.contains(id)) note(id, true);
    } else {
      final prefix = CardType.j.item('n$node:n$from:');
      for (final id in routeItems) {
        if (id.startsWith(prefix)) note(id, false);
      }
    }
  }
  return [
    for (final MapEntry(:key, :value) in outcome.entries)
      (itemId: key, ok: value),
  ];
}

/// The player's report that [move] on [path] is legal after all ("Wrong? Report this turn",
/// SPEC §15), by OSM nodes: `oneway:n<from>:n<to>` or `turn:n<from>:n<via>:n<to>`.
String moveReport(IllegalMove move, Map<int, int> junctionNodes) {
  String n(int junction) => 'n${junctionNodes[junction]}';
  final to = n(move.edge.other(move.junction));
  return switch (move.approach) {
    final approach? =>
      'turn:${n(approach.other(move.junction))}:${n(move.junction)}:$to',
    null => 'oneway:${n(move.junction)}:$to',
  };
}

/// [graph] with the moves in [reports] ([moveReport]s) let through; a report naming junctions
/// the pack no longer has is skipped.
RoadGraph allowingReports(
  RoadGraph graph,
  Set<String> reports,
  Map<int, int> junctionNodes,
) {
  if (reports.isEmpty) return graph;
  final byNode = {for (final e in junctionNodes.entries) e.value: e.key};
  Iterable<RoadEdge> between(int? a, int? b) => a == null || b == null
      ? const []
      : graph.edgesAt(a).where((e) => e.other(a) == b);
  final twoWay = <int>{};
  final allowed = <(int, int, int)>{};
  for (final report in reports) {
    final [kind, ...nodes] = report.split(':');
    final at = [for (final n in nodes) byNode[int.tryParse(n.substring(1))]];
    if (kind == 'oneway' && at.length == 2) {
      twoWay.addAll(between(at[0], at[1]).map((e) => e.id));
    } else if (kind == 'turn' && at.length == 3 && at[1] != null) {
      for (final from in between(at[1], at[0])) {
        for (final to in between(at[1], at[2])) {
          allowed.add((from.id, at[1]!, to.id));
        }
      }
    }
  }
  return graph.allowing(twoWay: twoWay, allowed: allowed);
}
