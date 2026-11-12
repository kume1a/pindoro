import 'dart:math' as math;

import '../geo/geo.dart';
import '../pack/road_graph.dart';
import 'named_street.dart';

/// Straight-line distances between A and B.
abstract final class TripRules {
  static const double lessonMinM = 500;
  static const double lessonMaxM = 1500;
  static const double driveMinM = 800;
  static const double driveMaxM = 2500;

  /// B candidates tried per destination, nearest its middle first.
  static const int destinationTries = 3;

  /// A candidates tried per B (each costs an A* search).
  static const int startTries = 20;

  /// The best drive may be at most this many times the straight line: past
  /// it, A or B sits where only a long loop reaches (a park, a dead end).
  static const double maxDetour = 1.6;
}

/// A road trip: drive from junction [from] (A) to [to] (B), which lies on
/// [destination]; [best] is the shortest drive.
typedef Trip = ({int from, int to, NamedStreet destination, Route best});

/// A trip to one of [destinations] (shuffled): B is a junction on it, its
/// middle first; A a junction on another of the [starts] streets, [minM] to
/// [maxM] from B in a straight line, joined to B by a route at most
/// [TripRules.maxDetour] times as long. Both lie inside [within] when given.
/// Null when nothing qualifies.
Trip? pickTrip(
  RoadGraph graph, {
  required List<NamedStreet> destinations,
  required Iterable<NamedStreet> starts,
  required double minM,
  required double maxM,
  List<List<Polyline>>? within,
  required math.Random random,
}) {
  bool inside(int j) => within == null || boundaryContains(within, graph.at(j));
  Set<int> junctionsOf(NamedStreet s) => {
    for (final p in s.parts) ...graph.junctionsOfPart(p.id),
  };
  final startJunctions = {for (final s in starts) ...junctionsOf(s)}
    ..retainWhere(inside);

  for (final destination in [...destinations]..shuffle(random)) {
    final onDestination = junctionsOf(destination);
    final middle = destination.parts.first.midpoint;
    final ends = onDestination.where(inside).toList()
      ..sort(
        (a, b) => distanceBetween(
          graph.at(a),
          middle,
        ).compareTo(distanceBetween(graph.at(b), middle)),
      );
    for (final b in ends.take(TripRules.destinationTries)) {
      final candidates = [
        for (final a in startJunctions)
          if (!onDestination.contains(a) &&
              _between(distanceBetween(graph.at(a), graph.at(b)), minM, maxM))
            a,
      ]..shuffle(random);
      for (final a in candidates.take(TripRules.startTries)) {
        final best = graph.shortestRoute(a, b);
        final straight = distanceBetween(graph.at(a), graph.at(b));
        if (best != null && best.lengthM <= straight * TripRules.maxDetour) {
          return (from: a, to: b, destination: destination, best: best);
        }
      }
    }
  }
  return null;
}

bool _between(double m, double min, double max) => m >= min && m <= max;

/// A drive being drawn from A towards [goal], one edge at a time.
class RouteDraft {
  RouteDraft(this.graph, int start, this.goal)
    : junctions = [start],
      edges = const [];

  RouteDraft._(this.graph, this.goal, this.junctions, this.edges);

  final RoadGraph graph;
  final int goal;

  /// From A; one more than [edges].
  final List<int> junctions;
  final List<RoadEdge> edges;

  int get start => junctions.first;

  int get end => junctions.last;

  bool get reached => end == goal;

  late final double lengthM = edges.fold(0, (sum, e) => sum + e.lengthM);

  /// Each edge's line in driving order; built once, so a draft keeps one
  /// identity for the map to diff against.
  late final MultiPolyline lines = [
    for (final (i, e) in edges.indexed) e.lineFrom(junctions[i]),
  ];

  /// The edge at the route's end nearest the [finger], within [snapM]: the
  /// one being followed. Null off the road, and once B is reached.
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
  /// the route's end; following the last edge back undoes it. Several
  /// junctions can pass in one move; it stops at B. A fast move is walked in
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
          ? draft.undo()
          : draft.take(edge);
    }
    return draft;
  }

  /// Adds [edge], which must meet the route's end.
  RouteDraft take(RoadEdge edge) {
    assert(edge.from == end || edge.to == end, 'edge ${edge.id} misses $end');
    return RouteDraft._(
      graph,
      goal,
      [...junctions, edge.other(end)],
      [...edges, edge],
    );
  }

  RouteDraft undo() => edges.isEmpty
      ? this
      : RouteDraft._(
          graph,
          goal,
          junctions.sublist(0, junctions.length - 1),
          edges.sublist(0, edges.length - 1),
        );

  RouteDraft startOver() => RouteDraft(graph, start, goal);
}

enum Turn { start, left, straight, right, back }

/// A street to take at the route's end: which way it turns, which way it
/// heads and whether its far end is nearer B.
typedef TurnOption = ({
  RoadEdge edge,
  Turn turn,
  CompassPoint heading,
  bool towardGoal,
});

/// Within this of straight ahead is straight on; beyond 180 − this, back.
const double _straightDeg = 30;

/// The edges at [draft]'s end as turns, left to right then back.
List<TurnOption> turnsAt(RouteDraft draft) {
  final graph = draft.graph;
  final here = graph.at(draft.end);
  final goal = graph.at(draft.goal);
  final last = draft.edges.lastOrNull;
  final arriving = last?.lineFrom(draft.junctions[draft.junctions.length - 2]);
  final inBearing = arriving == null
      ? null
      : _bearing(arriving[arriving.length - 2], arriving.last);
  return [
    for (final e in graph.edgesAt(draft.end))
      () {
        final line = e.lineFrom(draft.end);
        final far = graph.at(e.other(draft.end));
        return (
          edge: e,
          turn: inBearing == null
              ? Turn.start
              : _turn(_bearing(line[0], line[1]) - inBearing),
          heading: compassPoint(here, far),
          towardGoal: distanceBetween(far, goal) < distanceBetween(here, goal),
        );
      }(),
  ]..sort((a, b) => a.turn.index.compareTo(b.turn.index));
}

double _bearing(LatLng from, LatLng to) {
  final (x, y) = LocalProjection(from).project(to);
  return math.atan2(x, y) * 180 / math.pi;
}

Turn _turn(double degrees) {
  final a = (degrees + 540) % 360 - 180;
  if (a.abs() <= _straightDeg) return Turn.straight;
  if (a.abs() >= 180 - _straightDeg) return Turn.back;
  return a > 0 ? Turn.right : Turn.left;
}

/// A stretch of a route on one street: the street (by [routeLegs]' key),
/// where it heads and how long it is.
typedef RouteLeg = ({String streetId, CompassPoint heading, double lengthM});

/// [route] as legs of one street each; [streetOf] maps an edge's street part
/// to the street it belongs to (parts of one street make one leg).
List<RouteLeg> routeLegs(
  Route route, {
  String Function(String partId)? streetOf,
}) {
  final key = streetOf ?? (id) => id;
  final legs = <({String streetId, LatLng from, LatLng to, double lengthM})>[];
  final lines = route.lines;
  for (final (i, e) in route.edges.indexed) {
    final street = key(e.streetId);
    final line = lines[i];
    final last = legs.lastOrNull;
    if (last != null && last.streetId == street) {
      legs.last = (
        streetId: street,
        from: last.from,
        to: line.last,
        lengthM: last.lengthM + e.lengthM,
      );
    } else {
      legs.add((
        streetId: street,
        from: line.first,
        to: line.last,
        lengthM: e.lengthM,
      ));
    }
  }
  return [
    for (final l in legs)
      (
        streetId: l.streetId,
        heading: compassPoint(l.from, l.to),
        lengthM: l.lengthM,
      ),
  ];
}
