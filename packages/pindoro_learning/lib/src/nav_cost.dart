import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'constants.dart';
import 'nav_stop.dart';

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
Map<String, String> _roadClasses(Map<String, NamedStreet> streets) => {
  for (final s in streets.values)
    for (final p in s.parts) p.id: p.roadClass,
};

/// How navigation routes (SPEC §16.23 item 125): time on each edge, priced as metres at the top
/// class speed so no edge costs less than its length (A*'s straight-line estimate holds).
final class NavCost {
  NavCost(Map<String, NamedStreet> streets, {required this.toleranceKmh})
    : _classes = _roadClasses(streets);

  final int toleranceKmh;
  final Map<String, String> _classes;

  String? _classOf(RoadEdge e) => _classes[e.streetId];

  double kmh(RoadEdge e) => navSpeedKmh(e, _classOf(e), toleranceKmh);

  int limitKmh(RoadEdge e) => speedLimitKmh(e, _classOf(e));

  double cost(RoadEdge e) => e.lengthM * _topKmh / kmh(e);

  double seconds(RoadEdge e) => e.lengthM / (kmh(e) / 3.6);

  /// A U-turn: [LearningConfig.navUTurnS] at the top speed.
  double get uTurnCostM => LearningConfig.navUTurnS * _topKmh / 3.6;

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
