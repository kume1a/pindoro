import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'constants.dart';
import 'route_questions.dart';
import 'routes.dart';

/// [e]'s speed limit (SPEC §16.23 item 127): its sign, else Georgian law for its [roadClass].
int speedLimitKmh(RoadEdge e, String? roadClass) =>
    e.maxspeedKmh ??
    switch (roadClass) {
      'motorway' => LearningConfig.limitMotorwayKmh,
      'living_street' => LearningConfig.limitLivingStreetKmh,
      _ => LearningConfig.limitTownKmh,
    };

/// The speed navigation times [e] at: its class's typical speed, at most its limit plus
/// [toleranceKmh].
double navSpeedKmh(RoadEdge e, String? roadClass, int toleranceKmh) => min(
  LearningConfig.navClassKmh[roadClass] ?? LearningConfig.navConnectorKmh,
  (speedLimitKmh(e, roadClass) + toleranceKmh).toDouble(),
);

final double _topKmh = LearningConfig.navClassKmh.values.reduce(max);

/// Road classes by street part id, from [streets] (by part id).
Map<String, String> roadClasses(Map<String, NamedStreet> streets) => {
  for (final s in streets.values)
    for (final p in s.parts) p.id: p.roadClass,
};

/// How navigation routes (SPEC §16.23 item 125): time on each edge, priced as metres at the top
/// class speed so no edge costs less than its length (A*'s straight-line estimate holds).
final class NavCost {
  NavCost(Map<String, NamedStreet> streets, {required this.toleranceKmh})
    : _classes = roadClasses(streets);

  final int toleranceKmh;
  final Map<String, String> _classes;

  String? classOf(RoadEdge e) => _classes[e.streetId];

  double kmh(RoadEdge e) => navSpeedKmh(e, classOf(e), toleranceKmh);

  int limitKmh(RoadEdge e) => speedLimitKmh(e, classOf(e));

  double cost(RoadEdge e) => e.lengthM * _topKmh / kmh(e);

  double seconds(RoadEdge e) => e.lengthM / (kmh(e) / 3.6);

  /// A U-turn: the routing penalty's 30 s, at the top speed.
  double get uTurnCostM => 30 * _topKmh / 3.6;

  /// The quickest legal drive from [from] to [to], having arrived on [approach].
  Route? route(RoadGraph graph, int from, int to, {RoadEdge? approach}) =>
      graph.shortestRoute(
        from,
        {to},
        approach: approach,
        costOf: cost,
        uTurnCostM: uTurnCostM,
      );
}

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
/// its time.
final class NavPlan {
  const NavPlan(this.route, this.decisions, this.seconds);

  final Route route;
  final List<NavDecision> decisions;
  final double seconds;

  /// Each junction's distance along the route.
  List<double> get junctionM {
    final out = [0.0];
    for (final e in route.edges) {
      out.add(out.last + e.lengthM);
    }
    return out;
  }
}

/// The turn from [approach] onto [exit] at [junction] in degrees, -180 to 180 (right positive).
double turnAngle(RoadEdge approach, RoadEdge exit, int junction) =>
    ((leavingBearing(exit, junction) - arrivingBearing(approach, junction)) %
                360 +
            540) %
        360 -
    180;

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
      final node = junctionNodes[j];
      final from = before == null ? null : junctionNodes[before.other(j)];
      final to = junctionNodes[exit.other(j)];
      out.add((
        index: i,
        junction: j,
        approach: before,
        exit: exit,
        turn: before == null
            ? null
            : turnOf(arrivingBearing(before, j), leavingBearing(exit, j)),
        street: named,
        newStreet: newStreet,
        atM: atM,
        key: node == null || from == null || to == null
            ? null
            : RouteIds.junction(node, from, to),
        landmark: _landmarkAt(graph.at(j), j, landmarks),
        signals: graph.signals.contains(j),
      ));
    }
    atM += exit.lengthM;
  }
  return out;
}

/// The landmark to name at junction [j]: one placed at it, else the nearest within
/// [LearningConfig.landmarkAtM].
RouteLandmark? _landmarkAt(LatLng at, int j, List<RouteLandmark> landmarks) {
  RouteLandmark? best;
  var bestM = LearningConfig.landmarkAtM;
  for (final l in landmarks) {
    if (l.junction == j) return l;
    final m = distanceBetween(at, l.at);
    if (m <= bestM) (best, bestM) = (l, m);
  }
  return best;
}

/// The quickest drive from junction [from] (arrived on [approach]) to [to], with its decisions;
/// null when none is legal.
NavPlan? planNav(
  RoadGraph graph,
  NavCost cost, {
  required int from,
  required int to,
  RoadEdge? approach,
  Map<String, NamedStreet> streets = const {},
  List<RouteLandmark> landmarks = const [],
  Map<int, int> junctionNodes = const {},
}) {
  final route = cost.route(graph, from, to, approach: approach);
  if (route == null) return null;
  return NavPlan(
    route,
    navDecisions(
      graph,
      route,
      approach: approach,
      streets: streets,
      landmarks: landmarks,
      junctionNodes: junctionNodes,
    ),
    route.edges.fold(0, (sum, e) => sum + cost.seconds(e)),
  );
}
