import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'constants.dart';
import 'nav_cost.dart';
import 'nav_stop.dart';
import 'route_questions.dart';
import 'routes.dart';

/// A decision on a planned route (SPEC §16.23 item 112): at [junction], arriving on [approach],
/// leaving on [exit] ([index] in the route's edges), [atM] along the route. [key] is its J item
/// id (direction-specific, whether or not the route book has it), null without OSM nodes.
/// [landmark] stands within [LearningConfig.landmarkAtM]; [signals] when the junction has lights.
typedef NavDecision = ({
  int index,
  int junction,
  RoadEdge? approach,
  RoadEdge exit,
  Turn? turn,
  NamedStreet? street,
  bool newStreet,
  double atM,
  String? key,
  RouteLandmark? landmark,
  bool signals,
});

/// A planned drive: [route] (its first junction where the car is heading), its decisions and
/// its time, to [stop] (a junction stop at the route's end when null) through the stops [via]
/// in order (item 134).
final class NavPlan {
  const NavPlan(
    this.route,
    this.decisions,
    this.seconds, {
    this.stop,
    this.via = const [],
  });

  final Route route;
  final List<NavDecision> decisions;
  final double seconds;
  final NavStop? stop;
  final List<NavStop> via;

  /// [route] to [stop] through [via], having arrived at its first junction on [approach]: its
  /// decisions and its time.
  factory NavPlan.of(
    RoadGraph graph,
    NavCost cost,
    Route route, {
    required NavStop stop,
    List<NavStop> via = const [],
    RoadEdge? approach,
    Map<String, NamedStreet> streets = const {},
    List<RouteLandmark> landmarks = const [],
    Map<int, int> junctionNodes = const {},
  }) => NavPlan(
    route,
    navDecisions(
      graph,
      route,
      approach: approach,
      streets: streets,
      landmarks: landmarks,
      junctionNodes: junctionNodes,
    ),
    cost.secondsTo(route, stop),
    stop: stop,
    via: via,
  );

  /// The stop's metres along [route]: short of its end by the stop's road past it; below 0 when
  /// the stop is on the road the car is on before the route's first junction.
  double get endM => route.lengthM - (stop?.pastM(route.junctions.last) ?? 0);

  /// Each of [via]'s metres along [route], in order: where the route passes it after the one
  /// before; 0 for one it never passes (on the road the car is on before the first junction).
  List<double> get viaM {
    final at = junctionM;
    final out = <double>[];
    var from = 0;
    for (final v in via) {
      final before = out.lastOrNull ?? 0;
      double? found = v.junction != null && v.junction == route.junctions.first
          ? 0
          : null;
      for (var i = from; i < route.edges.length && found == null; i++) {
        final m = switch (v.edge) {
          null when route.junctions[i + 1] == v.junction => at[i + 1],
          null => null,
          final e
              when route.edges[i].id == e.id &&
                  (v.toward == null || route.junctions[i + 1] == v.toward) =>
            at[i] +
                (route.junctions[i] == e.from
                    ? v.alongM
                    : e.lengthM - v.alongM),
          _ => null,
        };
        if (m != null && m >= before) (found, from) = (m, i);
      }
      out.add(found ?? before);
    }
    return out;
  }

  /// The route drawn up to the stop.
  MultiPolyline get lines => switch (slice(0, endM)) {
    final line when line.length > 1 => [line],
    _ => const [],
  };

  /// Each junction's distance along the route.
  List<double> get junctionM {
    final out = [0.0];
    for (final e in route.edges) {
      out.add(out.last + e.lengthM);
    }
    return out;
  }

  /// The route from [fromM] to [toM] metres along it, clamped to it; each edge's metres (its
  /// `lengthM`, as the plan counts them) spread evenly over its line. Empty past its end.
  Polyline slice(double fromM, double toM) {
    final out = <LatLng>[];
    var startM = 0.0;
    for (final (i, e) in route.edges.indexed) {
      final endM = startM + e.lengthM;
      final a = max(fromM, startM);
      final b = min(toM, endM);
      if (a <= b && e.lengthM > 0) {
        final part = linePart(
          e.lineFrom(route.junctions[i]),
          (a - startM) / e.lengthM,
          (b - startM) / e.lengthM,
        );
        // Edges meet at their junction: drop the repeated point.
        out.addAll(out.isEmpty ? part : part.skip(1));
      }
      if (endM >= toM) break;
      startM = endM;
    }
    return out;
  }
}

/// The turn from [approach] onto [exit] at [junction] in degrees, -180 to 180 (right positive).
double turnAngle(RoadEdge approach, RoadEdge exit, int junction) =>
    angleDiffDeg(
      arrivingBearing(approach, junction),
      leavingBearing(exit, junction),
    );

/// The J item id of leaving [junction] on [exit] after [approach], by OSM node ([nodes]); null
/// without an approach or a node.
String? junctionKey(
  Map<int, int> nodes,
  int junction,
  RoadEdge? approach,
  RoadEdge exit,
) => switch ((
  nodes[junction],
  approach == null ? null : nodes[approach.other(junction)],
  nodes[exit.other(junction)],
)) {
  (final node?, final from?, final to?) => RouteIds.junction(node, from, to),
  _ => null,
};

/// Whether leaving [junction] on [exit] after [approach] is a decision (SPEC §16.23 item 112):
/// another legal way on (U-turns aside), and the route enters another named street or another
/// way on is at least as straight as [exit], give or take [LearningConfig.decisionAlikeDeg].
bool isDecision(
  RoadGraph graph,
  int junction,
  RoadEdge? approach,
  RoadEdge exit, {
  required bool newStreet,
}) {
  final others = [
    for (final e in graph.legalExits(junction, approach: approach))
      if (e.id != exit.id && e.id != approach?.id) e,
  ];
  if (others.isEmpty) return false;
  if (newStreet || approach == null) return true;
  final angle = turnAngle(approach, exit, junction).abs();
  return others.any(
    (e) =>
        turnAngle(approach, e, junction).abs() <=
        angle + LearningConfig.decisionAlikeDeg,
  );
}

/// The decisions along [route], having arrived at its first junction on [approach] (null: the
/// first junction counts as a start). [streets] are by part id, [landmarks] those worth naming.
List<NavDecision> navDecisions(
  RoadGraph graph,
  Route route, {
  RoadEdge? approach,
  Map<String, NamedStreet> streets = const {},
  List<RouteLandmark> landmarks = const [],
  Map<int, int> junctionNodes = const {},
}) {
  final out = <NavDecision>[];
  var atM = 0.0;
  String? street = switch (approach?.streetId) {
    final part? => streets[part]?.id ?? part,
    null => null,
  };
  for (final (i, exit) in route.edges.indexed) {
    final j = route.junctions[i];
    final before = i == 0 ? approach : route.edges[i - 1];
    final named = switch (exit.streetId) {
      final part? => streets[part],
      null => null,
    };
    final namedId = named?.id ?? exit.streetId;
    final newStreet = street != null && namedId != null && namedId != street;
    if (namedId != null) street = namedId;
    if (isDecision(graph, j, before, exit, newStreet: newStreet)) {
      out.add((
        index: i,
        junction: j,
        approach: before,
        exit: exit,
        turn: before == null ? null : turnAt(before, exit, j),
        street: named,
        newStreet: newStreet,
        atM: atM,
        key: junctionKey(junctionNodes, j, before, exit),
        landmark: landmarkAt(graph, j, landmarks),
        signals: graph.signals.contains(j),
      ));
    }
    atM += exit.lengthM;
  }
  return out;
}

/// The landmark to name at junction [j]: one placed at it, else the nearest within
/// [LearningConfig.landmarkAtM].
RouteLandmark? landmarkAt(
  RoadGraph graph,
  int j,
  List<RouteLandmark> landmarks,
) {
  RouteLandmark? best;
  var bestM = LearningConfig.landmarkAtM;
  for (final l in landmarks) {
    if (l.junction == j) return l;
    final m = distanceBetween(graph.at(j), l.at);
    if (m <= bestM) (best, bestM) = (l, m);
  }
  return best;
}

/// The quickest drive from junction [from] (arrived on [approach]) to stop [to] through the
/// stops [via], with its decisions; null when none is legal.
NavPlan? planNav(
  RoadGraph graph,
  NavCost cost, {
  required int from,
  required NavStop to,
  List<NavStop> via = const [],
  RoadEdge? approach,
  Map<String, NamedStreet> streets = const {},
  List<RouteLandmark> landmarks = const [],
  Map<int, int> junctionNodes = const {},
}) => planNavOptions(
  graph,
  cost,
  from: from,
  to: to,
  via: via,
  approach: approach,
  streets: streets,
  landmarks: landmarks,
  junctionNodes: junctionNodes,
  count: 1,
).firstOrNull;

/// Up to [count] drives from junction [from] (arrived on [approach]) to [to] through [via], the
/// quickest first
/// (SPEC §16.23 item 129): each next one the quickest once the roads of the drives so far cost
/// more, kept when it is not much slower and clearly different (see
/// [LearningConfig.navOptions]); none when no drive is legal.
List<NavPlan> planNavOptions(
  RoadGraph graph,
  NavCost cost, {
  required int from,
  required NavStop to,
  List<NavStop> via = const [],
  RoadEdge? approach,
  Map<String, NamedStreet> streets = const {},
  List<RouteLandmark> landmarks = const [],
  Map<int, int> junctionNodes = const {},
  int count = LearningConfig.navOptions,
}) {
  final quickest = cost.route(graph, from, to, approach: approach, via: via);
  if (quickest == null) return const [];
  final kept = [quickest];
  final avoid = {for (final e in quickest.edges) e.id};
  final slowest =
      cost.secondsTo(quickest, to) * LearningConfig.navOptionMaxSlower;
  for (
    var i = 1;
    i < LearningConfig.navOptionTries && kept.length < count;
    i++
  ) {
    final next = cost.route(
      graph,
      from,
      to,
      approach: approach,
      avoid: avoid,
      via: via,
    );
    final known = avoid.length;
    avoid.addAll([...?next?.edges.map((e) => e.id)]);
    if (next == null || avoid.length == known) break;
    if (cost.secondsTo(next, to) <= slowest &&
        kept.every(
          (k) =>
              _sharedM(next, k) <=
              next.lengthM * LearningConfig.navOptionMaxShared,
        )) {
      kept.add(next);
    }
  }
  return [
    for (final route in kept)
      NavPlan.of(
        graph,
        cost,
        route,
        stop: to,
        via: via,
        approach: approach,
        streets: streets,
        landmarks: landmarks,
        junctionNodes: junctionNodes,
      ),
  ];
}

/// The drives to a place's [stops] (from [stopsNear]) through [via]: up to [count] - 1 to the
/// first (the right side), then the quickest to the second (the left), so the player sees both
/// and picks (SPEC §16.23 item 132); [planNavOptions] to a lone stop.
List<NavPlan> planStopOptions(
  RoadGraph graph,
  NavCost cost, {
  required int from,
  required List<NavStop> stops,
  List<NavStop> via = const [],
  Map<String, NamedStreet> streets = const {},
  List<RouteLandmark> landmarks = const [],
  Map<int, int> junctionNodes = const {},
  int count = LearningConfig.navOptions,
}) {
  List<NavPlan> plans(NavStop to, int count) => planNavOptions(
    graph,
    cost,
    from: from,
    to: to,
    via: via,
    streets: streets,
    landmarks: landmarks,
    junctionNodes: junctionNodes,
    count: count,
  );
  if (stops.isEmpty) return const [];
  if (stops.length == 1 || count < 2) return plans(stops.first, count);
  return [...plans(stops.first, count - 1), ...plans(stops[1], 1)];
}

/// The length of [a] on edges [b] also takes.
double _sharedM(Route a, Route b) {
  final ids = {for (final e in b.edges) e.id};
  return a.edges
      .where((e) => ids.contains(e.id))
      .fold(0, (sum, e) => sum + e.lengthM);
}
