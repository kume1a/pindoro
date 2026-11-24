import 'package:pindoro_core/pindoro_core.dart';

import 'constants.dart';
import 'drive.dart';

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
