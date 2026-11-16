import 'dart:math' as math;

import '../geo/geo.dart';
import '../pack/road_graph.dart';

/// A drive being drawn from A towards any of [goals], one edge at a time.
class RouteDraft {
  RouteDraft(this.graph, int start, this.goals)
    : junctions = [start],
      edges = const [];

  RouteDraft._(this.graph, this.goals, this.junctions, this.edges);

  final RoadGraph graph;
  final Set<int> goals;

  /// From A; one more than [edges].
  final List<int> junctions;
  final List<RoadEdge> edges;

  int get start => junctions.first;

  int get end => junctions.last;

  bool get reached => goals.contains(end);

  late final double lengthM = edges.fold(0, (sum, e) => sum + e.lengthM);

  /// Each edge's line in driving order; built once, so a draft keeps one
  /// identity for the map to diff against.
  late final MultiPolyline lines = [
    for (final (i, e) in edges.indexed) e.lineFrom(junctions[i]),
  ];

  /// The edge at the route's end nearest the [finger], within [snapM]: the
  /// one being followed. Null off the road, and once a goal is reached.
  RoadEdge? heading(LatLng finger, double snapM) {
    if (reached) return null;
    RoadEdge? best;
    var bestM = snapM;
    for (final e in graph.edgesAt(end)) {
      final m = pointToPolylineDistance(finger, [e.line]).distanceMeters;
      if (m <= bestM) (best, bestM) = (e, m);
    }
    return best;
  }

  /// Walks the route along the [finger]: the edge it follows is taken once
  /// the finger is within [snapM] of its far junction and nearer that than
  /// the route's end; following the last edge back drops it. Several
  /// junctions can pass in one move; it stops at a goal. A fast move is walked in
  /// steps of half [snapM] from where the finger was ([from]), so it can't
  /// jump past a junction.
  RouteDraft follow(LatLng finger, double snapM, {LatLng? from}) {
    if (from == null) return _follow(finger, snapM);
    final steps = math.max(
      1,
      (distanceBetween(from, finger) * 2 / snapM).ceil(),
    );
    var draft = this;
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      draft = draft._follow(
        LatLng(
          from.lat + (finger.lat - from.lat) * t,
          from.lon + (finger.lon - from.lon) * t,
        ),
        snapM,
      );
    }
    return draft;
  }

  RouteDraft _follow(LatLng finger, double snapM) {
    var draft = this;
    // ponytail: bounded walk; one move event never crosses this many junctions.
    for (var i = 0; i < 64 && !draft.reached; i++) {
      final edge = draft.heading(finger, snapM);
      if (edge == null) break;
      final far = graph.at(edge.other(draft.end));
      final toFar = distanceBetween(finger, far);
      if (toFar > snapM ||
          toFar >= distanceBetween(finger, graph.at(draft.end))) {
        break;
      }
      draft = draft.edges.isNotEmpty && draft.edges.last.id == edge.id
          ? draft._back()
          : draft.take(edge);
    }
    return draft;
  }

  /// Drives to a tap at [point]: along the street the tap is on (within
  /// [snapM]) and the streets at the route's end, up to the tapped edge's
  /// end nearest the tap, stopping at a goal. "Along this street, then onto
  /// that one, up to here." Null when no street is near the tap or none of
  /// those streets leads there.
  RouteDraft? driveTo(LatLng point, double snapM) {
    if (reached) return null;
    final tapped = graph.edgeNear(point, snapM);
    if (tapped == null) return null;
    final near =
        distanceBetween(point, graph.at(tapped.from)) <=
            distanceBetween(point, graph.at(tapped.to))
        ? tapped.from
        : tapped.to;
    final target = near == end ? tapped.other(end) : near;
    final streets = {
      tapped.streetId,
      for (final e in graph.edgesAt(end)) e.streetId,
    };
    final route = graph.shortestRoute(end, {
      target,
    }, allow: (e) => streets.contains(e.streetId));
    if (route == null || route.edges.isEmpty) return null;
    var draft = this;
    for (final e in route.edges) {
      if (draft.reached) break;
      draft = draft.take(e);
    }
    return draft;
  }

  /// Adds [edge], which must meet the route's end.
  RouteDraft take(RoadEdge edge) {
    assert(edge.from == end || edge.to == end, 'edge ${edge.id} misses $end');
    return RouteDraft._(
      graph,
      goals,
      [...junctions, edge.other(end)],
      [...edges, edge],
    );
  }

  /// Drops the last street: the edges at the end on the last edge's street.
  RouteDraft undo() {
    var keep = edges.length;
    while (keep > 0 && edges[keep - 1].streetId == edges.last.streetId) {
      keep--;
    }
    return _keep(keep);
  }

  /// Drops the last edge.
  RouteDraft _back() => _keep(edges.length - 1);

  RouteDraft _keep(int count) => count >= edges.length
      ? this
      : RouteDraft._(
          graph,
          goals,
          junctions.sublist(0, count + 1),
          edges.sublist(0, count),
        );

  RouteDraft startOver() => RouteDraft(graph, start, goals);
}
