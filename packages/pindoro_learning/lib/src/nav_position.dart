import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'constants.dart';
import 'drive.dart';
import 'grader.dart';
import 'nav_cost.dart';
import 'nav_plan.dart';

/// Where the car is on a [plan] (SPEC §16.23): on the road it arrived on ([approach]), short of
/// the plan's first junction ([index] -1), or on the plan's [index]th edge; [progressM] along the
/// plan, below 0 short of it.
final class PlanPosition {
  /// The car on [approach] with the share [along] of it behind, heading for [plan]'s first
  /// junction.
  PlanPosition(this.plan, this.approach, double along)
    : junctionM = plan.junctionM,
      viaM = plan.viaM,
      progressM = -(1 - along) * approach.lengthM;

  final NavPlan plan;
  final RoadEdge approach;

  /// Each junction's and each stop on the way's metres along the plan.
  final List<double> junctionM;
  final List<double> viaM;

  int index = -1;
  double progressM;

  Route get _route => plan.route;

  /// The edge the car is on.
  RoadEdge get edge => index < 0 ? approach : _route.edges[index];

  /// The junction the car drives away from on [edge].
  int get from => index >= 0
      ? _route.junctions[index]
      : approach.other(_route.junctions.first);

  /// The junction the car drives toward on [edge].
  int get ahead => _route.junctions[index + 1];

  /// The metres of [edge] behind the car.
  double get alongM =>
      index < 0 ? approach.lengthM + progressM : progressM - junctionM[index];

  /// The car at [p] on the plan near where it was ([wide]: anywhere further along, after a GPS
  /// gap): its progress, or null when it is off the plan.
  double? track(LatLng p, double? heading, {bool wide = false}) {
    final edges = _route.edges;
    final last = wide ? edges.length - 1 : min(index + 3, edges.length - 1);
    ({int i, double distM, double alongM})? best;
    for (var i = max(-1, index); i <= last; i++) {
      final n = i < 0
          ? nearestDriven(p, approach, approach.other(_route.junctions.first))
          : nearestDriven(p, edges[i], _route.junctions[i]);
      if (n.distM > LearningConfig.driveSnapM) continue;
      if (heading != null &&
          bearingError(heading, n.headingDeg) >
              LearningConfig.navTrackHeadingDeg) {
        continue;
      }
      if (best == null || n.distM < best.distM) {
        best = (i: i, distM: n.distM, alongM: n.alongM);
      }
    }
    if (best == null) return null;
    index = best.i;
    progressM = best.i < 0
        ? best.alongM - approach.lengthM
        : junctionM[best.i] + best.alongM;
    return progressM;
  }

  /// The plan's time left from the car.
  double remainingS(NavCost cost) {
    final e = edge;
    final share = e.lengthM == 0 ? 0 : 1 - alongM / e.lengthM;
    var s = share * cost.seconds(e);
    for (var i = index + 1; i < _route.edges.length; i++) {
      s += cost.seconds(_route.edges[i]);
    }
    // Less the stop's road past it.
    final last = _route.edges.lastOrNull ?? e;
    final past = _route.lengthM - plan.endM;
    if (last.lengthM > 0) s -= past / last.lengthM * cost.seconds(last);
    return max(0, s);
  }

  /// The car and the way the road runs [LearningConfig.navRoadAheadM] ahead of it; null where
  /// that is no way (a zero-length edge, the plan's end).
  ({LatLng at, double headingDeg})? onRoad() {
    final e = edge;
    if (e.lengthM <= 0) return null;
    // Before the plan's first junction the car is on the edge it arrived on.
    final road = index >= 0
        ? plan.slice(progressM, progressM + LearningConfig.navRoadAheadM)
        : linePart(
            e.lineFrom(from),
            alongM / e.lengthM,
            min(1, (alongM + LearningConfig.navRoadAheadM) / e.lengthM),
          );
    if (road.length < 2 || distanceBetween(road.first, road.last) < 1) {
      return null;
    }
    return (at: road.first, headingDeg: bearingDegrees(road.first, road.last));
  }

  /// The road from the car to the plan's first junction, while short of it.
  Polyline toPlan() {
    if (approach.lengthM <= 0) return const [];
    // The stop may lie on this road, short of the plan's first junction.
    return linePart(
      approach.lineFrom(from),
      (alongM / approach.lengthM).clamp(0, 1),
      (1 + plan.endM / approach.lengthM).clamp(0, 1),
    );
  }

  /// The metres from the car to the next of the [left] stops on the way still ahead; null
  /// without one.
  double? viaInM(int left) {
    final k = viaM.length - left;
    if (left == 0 || k < 0 || k >= viaM.length) return null;
    return viaM[k] - progressM;
  }
}
