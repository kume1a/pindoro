import 'dart:collection';

import '../geo/geo.dart';
import '../geo/polyline6.dart';
import 'models.dart';

/// A stretch of one street between two junctions (pack `road_edge`). Edges
/// are undirected: one-way streets are ignored.
class RoadEdge {
  RoadEdge({
    required this.id,
    required this.from,
    required this.to,
    required this.streetId,
    required this.lengthM,
    required Polyline line,
  }) : _line = line,
       _geometry = null;

  /// Keeps the polyline6 and decodes it on first use: a city has thousands
  /// of edges and a trip draws a few dozen.
  RoadEdge.fromRow(PackRow r)
    : id = r['id']! as int,
      from = r['from_junction']! as int,
      to = r['to_junction']! as int,
      streetId = r['street_id']! as String,
      lengthM = (r['length_m']! as num).toDouble(),
      _geometry = r['geometry']! as String;

  final int id;
  final int from;
  final int to;

  /// The street part (pack `street.id`) it belongs to.
  final String streetId;
  final double lengthM;
  final String? _geometry;
  Polyline? _line;

  /// From [from] to [to].
  Polyline get line => _line ??= decodePolyline6(_geometry!);

  /// The far end, driving away from [junction].
  int other(int junction) => junction == from ? to : from;

  /// The line as driven away from [junction].
  Polyline lineFrom(int junction) =>
      junction == from ? line : line.reversed.toList();
}

/// A drive along edges: its junctions from the start, the edges between them
/// and its length.
class Route {
  const Route(this.junctions, this.edges, this.lengthM);

  final List<int> junctions;
  final List<RoadEdge> edges;
  final double lengthM;

  /// Each edge's line in driving order.
  MultiPolyline get lines => [
    for (final (i, e) in edges.indexed) e.lineFrom(junctions[i]),
  ];
}

/// A city's road graph (pack format 3): junctions and the edges at each.
class RoadGraph {
  RoadGraph(this.junctions, Iterable<RoadEdge> edges)
    : edges = List.unmodifiable(edges) {
    for (final e in this.edges) {
      _at.putIfAbsent(e.from, () => []).add(e);
      _at.putIfAbsent(e.to, () => []).add(e);
    }
  }

  final Map<int, LatLng> junctions;
  final List<RoadEdge> edges;
  final Map<int, List<RoadEdge>> _at = {};

  List<RoadEdge> edgesAt(int junction) => _at[junction] ?? const [];

  LatLng at(int junction) => junctions[junction]!;

  /// The shortest drive from [from] to [to] (A* on edge lengths, straight
  /// line as the heuristic); null when they aren't connected.
  Route? shortestRoute(int from, int to) {
    final goal = at(to);
    final cost = <int, double>{from: 0};
    final via = <int, RoadEdge>{};
    double estimate(int j) => cost[j]! + distanceBetween(at(j), goal);
    // Ordered by estimate, then id, so equal estimates stay distinct entries.
    final open = SplayTreeSet<(double, int)>((a, b) {
      final byEstimate = a.$1.compareTo(b.$1);
      return byEstimate != 0 ? byEstimate : a.$2.compareTo(b.$2);
    })..add((estimate(from), from));
    final closed = <int>{};
    while (open.isNotEmpty) {
      final (_, j) = open.first;
      open.remove(open.first);
      if (j == to) return _route(from, to, via, cost[to]!);
      if (!closed.add(j)) continue;
      for (final e in edgesAt(j)) {
        final next = e.other(j);
        final c = cost[j]! + e.lengthM;
        if (closed.contains(next) || c >= (cost[next] ?? double.infinity)) {
          continue;
        }
        if (cost.containsKey(next)) open.remove((estimate(next), next));
        cost[next] = c;
        via[next] = e;
        open.add((estimate(next), next));
      }
    }
    return null;
  }

  Route _route(int from, int to, Map<int, RoadEdge> via, double lengthM) {
    final junctions = [to];
    final edges = <RoadEdge>[];
    for (var j = to; j != from;) {
      final e = via[j]!;
      edges.add(e);
      j = e.other(j);
      junctions.add(j);
    }
    return Route(junctions.reversed.toList(), edges.reversed.toList(), lengthM);
  }
}
