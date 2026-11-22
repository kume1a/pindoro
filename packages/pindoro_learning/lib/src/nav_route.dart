import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'constants.dart';
import 'grader.dart';
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

  /// The quickest legal drive from [from] to [to], having arrived on [approach]; the edges in
  /// [avoid] cost [LearningConfig.navOptionPenalty] times as much.
  Route? route(
    RoadGraph graph,
    int from,
    int to, {
    RoadEdge? approach,
    Set<int> avoid = const {},
  }) => graph.shortestRoute(
    from,
    {to},
    approach: approach,
    costOf: avoid.isEmpty
        ? cost
        : (e) =>
              cost(e) *
              (avoid.contains(e.id) ? LearningConfig.navOptionPenalty : 1),
    uTurnCostM: uTurnCostM,
  );

  /// [route]'s time.
  double secondsOf(Route route) =>
      route.edges.fold(0, (sum, e) => sum + seconds(e));
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

/// [line] from share [from] to share [to] of its length.
Polyline linePart(Polyline line, double from, double to) {
  final cum = [0.0];
  for (var i = 1; i < line.length; i++) {
    cum.add(cum.last + distanceBetween(line[i - 1], line[i]));
  }
  final total = cum.last;
  LatLng at(double m) {
    for (var i = 1; i < line.length; i++) {
      if (cum[i] >= m) {
        final len = cum[i] - cum[i - 1];
        final t = len == 0 ? 0.0 : (m - cum[i - 1]) / len;
        final a = line[i - 1], b = line[i];
        return LatLng(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
      }
    }
    return line.last;
  }

  final fromM = from * total, toM = to * total;
  return [
    at(fromM),
    for (var i = 1; i < line.length - 1; i++)
      if (cum[i] > fromM && cum[i] < toM) line[i],
    if (toM > fromM) at(toM),
  ];
}

/// The arrow Guided draws on the map at [d] (SPEC §16.23 item 130): [plan]'s route from
/// [LearningConfig.navArrowBeforeM] before it to [LearningConfig.navArrowAfterM] after.
Polyline turnArrow(NavPlan plan, NavDecision d) => plan.slice(
  d.atM - LearningConfig.navArrowBeforeM,
  d.atM + LearningConfig.navArrowAfterM,
);

/// A lane into a junction, left to right (item 130): its painted arrows as turn angles in
/// degrees (0 straight on, -90 left, 90 right, 180 turning around) and [use], the arrow to take
/// in it; null when the lane doesn't go the way.
typedef NavLane = ({List<double> arrowsDeg, double? use});

/// OSM `turn:lanes` values as turn angles; an unmarked lane (`none`, empty) and a merging one
/// count as straight on.
const Map<String, double> _laneDeg = {
  'sharp_left': -135,
  'left': -90,
  'slight_left': -45,
  'through': 0,
  'slight_right': 45,
  'right': 90,
  'sharp_right': 135,
  'reverse': 180,
};

/// The lanes into [d]'s junction (its approach's `turn:lanes`), each with the arrow to take:
/// the painted arrow nearest the turn [d] makes, in every lane that has it. Null when no lanes
/// are mapped there, or no arrow is within [LearningConfig.laneMatchDeg] of the turn.
List<NavLane>? navLanes(NavDecision d) {
  final approach = d.approach;
  final tagged = approach?.lanesInto(d.junction);
  if (approach == null || tagged == null) return null;
  final lanes = [
    for (final lane in tagged.split('|'))
      {for (final v in lane.split(';')) _laneDeg[v.trim()] ?? 0.0}.toList(),
  ];
  final turn = turnAngle(approach, d.exit, d.junction);
  double off(double a) => bearingError(turn, a);
  final best = lanes.expand((l) => l).reduce((a, b) => off(b) < off(a) ? b : a);
  if (off(best) > LearningConfig.laneMatchDeg) return null;
  return [
    for (final l in lanes) (arrowsDeg: l, use: l.contains(best) ? best : null),
  ];
}

/// The turn from [approach] onto [exit] at [junction] in degrees, -180 to 180 (right positive).
double turnAngle(RoadEdge approach, RoadEdge exit, int junction) =>
    ((leavingBearing(exit, junction) - arrivingBearing(approach, junction)) %
                360 +
            540) %
        360 -
    180;

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
        turn: before == null
            ? null
            : turnOf(arrivingBearing(before, j), leavingBearing(exit, j)),
        street: named,
        newStreet: newStreet,
        atM: atM,
        key: junctionKey(junctionNodes, j, before, exit),
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
}) => planNavOptions(
  graph,
  cost,
  from: from,
  to: to,
  approach: approach,
  streets: streets,
  landmarks: landmarks,
  junctionNodes: junctionNodes,
  count: 1,
).firstOrNull;

/// Up to [count] drives from junction [from] (arrived on [approach]) to [to], the quickest first
/// (SPEC §16.23 item 129): each next one the quickest once the roads of the drives so far cost
/// more, kept when it is not much slower and clearly different (see
/// [LearningConfig.navOptions]); none when no drive is legal.
List<NavPlan> planNavOptions(
  RoadGraph graph,
  NavCost cost, {
  required int from,
  required int to,
  RoadEdge? approach,
  Map<String, NamedStreet> streets = const {},
  List<RouteLandmark> landmarks = const [],
  Map<int, int> junctionNodes = const {},
  int count = LearningConfig.navOptions,
}) {
  final quickest = cost.route(graph, from, to, approach: approach);
  if (quickest == null) return const [];
  final kept = [quickest];
  final avoid = {for (final e in quickest.edges) e.id};
  final slowest = cost.secondsOf(quickest) * LearningConfig.navOptionMaxSlower;
  for (
    var i = 1;
    i < LearningConfig.navOptionTries && kept.length < count;
    i++
  ) {
    final next = cost.route(graph, from, to, approach: approach, avoid: avoid);
    final known = avoid.length;
    avoid.addAll([...?next?.edges.map((e) => e.id)]);
    if (next == null || avoid.length == known) break;
    if (cost.secondsOf(next) <= slowest &&
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
      NavPlan(
        route,
        navDecisions(
          graph,
          route,
          approach: approach,
          streets: streets,
          landmarks: landmarks,
          junctionNodes: junctionNodes,
        ),
        cost.secondsOf(route),
      ),
  ];
}

/// The length of [a] on edges [b] also takes.
double _sharedM(Route a, Route b) {
  final ids = {for (final e in b.edges) e.id};
  return a.edges
      .where((e) => ids.contains(e.id))
      .fold(0, (sum, e) => sum + e.lengthM);
}
