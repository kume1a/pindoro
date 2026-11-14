import 'dart:math' as math;

import '../geo/geo.dart';
import '../pack/road_graph.dart';
import 'named_street.dart';

/// How road trips are picked.
abstract final class TripRules {
  /// Straight-line distances from A to the destination street.
  static const double lessonMinM = 500;
  static const double lessonMaxM = 1500;
  static const double driveMinM = 800;
  static const double driveMaxM = 2500;

  /// A candidates tried per destination (each costs an A* search).
  static const int startTries = 20;

  /// A* searches per pick, across every destination.
  static const int maxSearches = 60;

  /// The best drive may be at most this many times the straight line: past
  /// it, A sits where only a long loop reaches the street (a park, a dead end).
  static const double maxDetour = 1.6;

  /// Turns onto other streets the best drive needs, so a trip is never one
  /// straight road.
  static const int minTurns = 2;
}

/// A road trip: drive from junction [from] (A) to any of [goals], the
/// junctions of [destination]; [best] is the shortest drive there.
typedef Trip = ({
  int from,
  Set<int> goals,
  NamedStreet destination,
  Route best,
});

/// A trip to one of [destinations] (shuffled): A is a junction on another of
/// the [starts] streets, inside [within] when given, [minM] to [maxM] in a
/// straight line from the destination's nearest junction, and joined to it
/// by a drive at most [TripRules.maxDetour] times as long. The first trip
/// whose best drive makes [TripRules.minTurns] turns wins; failing that, the
/// one with the most turns. Null when nothing qualifies.
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
  final startJunctions = {for (final s in starts) ..._junctionsOf(graph, s)}
    ..retainWhere(inside);

  Trip? fallback;
  var fallbackTurns = -1;
  var searches = 0;
  for (final destination in [...destinations]..shuffle(random)) {
    final goals = _junctionsOf(graph, destination);
    if (goals.isEmpty) continue;
    double toStreet(int a) => goals
        .map((g) => distanceBetween(graph.at(a), graph.at(g)))
        .reduce(math.min);
    final candidates = [
      for (final a in startJunctions)
        if (!goals.contains(a) && _between(toStreet(a), minM, maxM)) a,
    ]..shuffle(random);
    for (final a in candidates.take(TripRules.startTries)) {
      if (searches++ >= TripRules.maxSearches) return fallback;
      final best = graph.shortestRoute(a, goals);
      if (best == null || best.lengthM > toStreet(a) * TripRules.maxDetour) {
        continue;
      }
      final trip = (
        from: a,
        goals: goals,
        destination: destination,
        best: best,
      );
      final turns = turnCount(best);
      if (turns >= TripRules.minTurns) return trip;
      if (turns > fallbackTurns) (fallback, fallbackTurns) = (trip, turns);
    }
  }
  return fallback;
}

bool _between(double m, double min, double max) => m >= min && m <= max;

Set<int> _junctionsOf(RoadGraph graph, NamedStreet street) => {
  for (final p in street.parts) ...graph.junctionsOfPart(p.id),
};

/// The turns onto another street along [route]: junctions where it changes
/// street part and bends left or right.
int turnCount(Route route) {
  final lines = route.lines;
  var turns = 0;
  for (var i = 1; i < lines.length; i++) {
    if (route.edges[i].streetId == route.edges[i - 1].streetId) continue;
    final arriving = lines[i - 1], leaving = lines[i];
    final turn = _turn(
      _bearing(leaving[0], leaving[1]) -
          _bearing(arriving[arriving.length - 2], arriving.last),
    );
    if (turn == Turn.left || turn == Turn.right) turns++;
  }
  return turns;
}

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

enum Turn { start, left, straight, right, back }

/// A street to take at the route's end: which way it turns and which way
/// it heads.
typedef TurnOption = ({RoadEdge edge, Turn turn, CompassPoint heading});

/// Within this of straight ahead is straight on; beyond 180 − this, back.
const double _straightDeg = 30;

/// The edges at [draft]'s end as turns, left to right then back.
List<TurnOption> turnsAt(RouteDraft draft) {
  final graph = draft.graph;
  final here = graph.at(draft.end);
  final last = draft.edges.lastOrNull;
  final arriving = last?.lineFrom(draft.junctions[draft.junctions.length - 2]);
  final inBearing = arriving == null
      ? null
      : _bearing(arriving[arriving.length - 2], arriving.last);
  return [
    for (final e in graph.edgesAt(draft.end))
      () {
        final line = e.lineFrom(draft.end);
        return (
          edge: e,
          turn: inBearing == null
              ? Turn.start
              : _turn(_bearing(line[0], line[1]) - inBearing),
          heading: compassPoint(here, graph.at(e.other(draft.end))),
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
