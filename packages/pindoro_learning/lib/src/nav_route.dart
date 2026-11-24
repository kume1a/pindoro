import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'constants.dart';
import 'drive.dart';
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

  /// The quickest legal drive from [from] to [to] through the stops [via] in order (item 134),
  /// having arrived on [approach]: one leg per stop, each going on from the end of the last
  /// one's road; the edges in [avoid] cost [LearningConfig.navOptionPenalty] times as much.
  Route? route(
    RoadGraph graph,
    int from,
    NavStop to, {
    RoadEdge? approach,
    Set<int> avoid = const {},
    List<NavStop> via = const [],
  }) {
    double costOf(RoadEdge e) =>
        cost(e) * (avoid.contains(e.id) ? LearningConfig.navOptionPenalty : 1);
    Route? joined;
    var at = from;
    var inbound = approach;
    for (final stop in [...via, to]) {
      final leg = graph.shortestRoute(
        at,
        stop.goals,
        approach: inbound,
        arriveOn: stop.edge,
        costOf: avoid.isEmpty ? cost : costOf,
        uTurnCostM: uTurnCostM,
      );
      if (leg == null) return null;
      joined = joined == null ? leg : _join(joined, leg);
      at = leg.junctions.last;
      inbound = leg.edges.lastOrNull ?? inbound;
    }
    return joined;
  }

  static Route _join(Route a, Route b) => Route(
    [...a.junctions, ...b.junctions.skip(1)],
    [...a.edges, ...b.edges],
    a.lengthM + b.lengthM,
    costM: a.costM + b.costM,
  );

  /// [route]'s time.
  double secondsOf(Route route) =>
      route.edges.fold(0, (sum, e) => sum + seconds(e));

  /// [route]'s time to [stop], leaving out its road past the stop.
  double secondsTo(Route route, NavStop stop) {
    final last = route.edges.lastOrNull;
    final past = stop.pastM(route.junctions.last);
    if (last == null || last.lengthM <= 0 || past <= 0) return secondsOf(route);
    return max(0, secondsOf(route) - past / last.lengthM * seconds(last));
  }
}

/// The side of the road a place is on, driving toward it.
enum NavSide {
  right,
  left;

  NavSide get flipped => this == right ? left : right;
}

/// Where a drive stops (SPEC §16.23 item 132): a [junction], or a point [at] on a road ([edge],
/// [alongM] from its `from` end) driven toward [toward] (either way the road allows when null),
/// the place on its [side] then.
final class NavStop {
  const NavStop.junction(int this.junction)
    : edge = null,
      alongM = 0,
      toward = null,
      at = null,
      side = null;

  const NavStop.onEdge(
    RoadEdge this.edge, {
    required this.alongM,
    required LatLng this.at,
    this.toward,
    this.side,
  }) : junction = null;

  final int? junction;
  final RoadEdge? edge;
  final double alongM;
  final int? toward;
  final LatLng? at;
  final NavSide? side;

  /// The junctions a route to it ends at (along [edge] when there is one).
  Set<int> get goals => switch ((edge, toward)) {
    (null, _) => {junction!},
    (_, final t?) => {t},
    (final e?, null) => {e.from, e.to},
  };

  /// The metres of [edge] past the stop on a route ending at [end].
  double pastM(int end) => switch (edge) {
    null => 0,
    final e => end == e.to ? e.lengthM - alongM : alongM,
  };

  LatLng pointOn(RoadGraph graph) => at ?? graph.at(junction!);

  /// The junction the drive's learning keeps for it: the road's end nearer the stop.
  int get junctionNear =>
      junction ?? (2 * alongM <= edge!.lengthM ? edge!.from : edge!.to);
}

/// The stops for a [place] (item 132): on the road nearest it within
/// [LearningConfig.navStopReachM], one per way the road may be driven with the place on its
/// side (the right first); one either way when the place is on the road's line; none without a
/// road in reach.
List<NavStop> stopsNear(RoadGraph graph, LatLng place) {
  final e = graph.edgeNear(place, LearningConfig.navStopReachM);
  if (e == null) return const [];
  final n = nearestOnEdge(place, e);
  final at = linePart(e.line, n.along, n.along).first;
  final alongM = n.along * e.lengthM;
  if (n.distM <= LearningConfig.navStopSideM) {
    return [NavStop.onEdge(e, alongM: alongM, at: at)];
  }
  // Driving from `from` to `to`, the place is on the right when it bears 0–180° from the road.
  final forward = (bearingDegrees(at, place) - n.headingDeg) % 360 < 180
      ? NavSide.right
      : NavSide.left;
  return [
    for (final (toward, side) in [(e.to, forward), (e.from, forward.flipped)])
      if (graph.canDrive(e, e.other(toward)))
        NavStop.onEdge(e, alongM: alongM, at: at, toward: toward, side: side),
  ]..sort((a, b) => a.side!.index.compareTo(b.side!.index));
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

/// The arrow Guided draws on the map at [d] (SPEC §16.23 items 130, 135): [plan]'s route from
/// [LearningConfig.navArrowBeforeM] before it to [LearningConfig.navArrowAfterM] after, its way
/// on stopping [LearningConfig.navArrowGapM] short of the next decision and at the first bend
/// sharper than [LearningConfig.navArrowBendDeg], so it shows one turn only.
Polyline turnArrow(NavPlan plan, NavDecision d) {
  final i = plan.decisions.indexOf(d);
  final after = i < 0 ? null : plan.decisions.elementAtOrNull(i + 1);
  final endM = min(
    d.atM + LearningConfig.navArrowAfterM,
    after == null ? double.infinity : after.atM - LearningConfig.navArrowGapM,
  );
  final wayIn = plan.slice(d.atM - LearningConfig.navArrowBeforeM, d.atM);
  final wayOn = endM <= d.atM ? <LatLng>[] : _toBend(plan.slice(d.atM, endM));
  return [...wayIn, ...wayOn.skip(wayIn.isEmpty ? 0 : 1)];
}

/// [line] up to its first point where it turns more than [LearningConfig.navArrowBendDeg]
/// from the way it set out.
Polyline _toBend(Polyline line) {
  if (line.length < 3) return line;
  final first = bearingDegrees(line[0], line[1]);
  for (var k = 1; k + 1 < line.length; k++) {
    final turn =
        (bearingDegrees(line[k], line[k + 1]) - first + 540) % 360 - 180;
    if (turn.abs() > LearningConfig.navArrowBendDeg) {
      return line.sublist(0, k + 1);
    }
  }
  return line;
}

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
        cost.secondsTo(route, to),
        stop: to,
        via: via,
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
