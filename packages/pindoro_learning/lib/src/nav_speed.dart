import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'constants.dart';
import 'drive.dart';
import 'grader.dart';
import 'nav_cost.dart';
import 'nav_plan.dart';

/// The speed and the cameras on a drive (SPEC §16.23 item 127): over the limit long enough, a
/// warning and its chime; a camera ahead on the car's street, warned of once.
final class SpeedWatch {
  SpeedWatch(this.graph, this.cost, this.streets)
    : _camerasByEdge = _byEdge(graph.cameras);

  final RoadGraph graph;
  final NavCost cost;

  /// By part id.
  final Map<String, NamedStreet> streets;
  final Map<int, List<SpeedCamera>> _camerasByEdge;
  final Set<int> _warned = {};
  double _cameraUntilM = 0;
  DateTime? _overSince;
  DateTime? _chimedAt;

  /// Whether a camera was warned of and isn't passed yet, [drivenM] into the drive.
  bool cameraAhead(double drivenM) => drivenM < _cameraUntilM;

  /// Over [limit] plus the tolerance for [LearningConfig.overspeedHoldS]: [warned], and a
  /// [chime] then and every [LearningConfig.overspeedRepeatS] while it lasts.
  ({bool warned, bool chime}) overspeed(DateTime now, double kmh, int? limit) {
    if (limit == null || kmh <= limit + cost.toleranceKmh) {
      _overSince = null;
      return (warned: false, chime: false);
    }
    final since = _overSince ??= now;
    final chimed = _chimedAt;
    final warned =
        now.difference(since).inSeconds >= LearningConfig.overspeedHoldS;
    final chime =
        warned &&
        (chimed == null ||
            now.difference(chimed).inSeconds >=
                LearningConfig.overspeedRepeatS);
    if (chime) _chimedAt = now;
    return (warned: warned, chime: chime);
  }

  /// The limits of the cameras newly ahead of the car, [alongM] along [edge] driven away from
  /// [from], [drivenM] into the drive: on along the same street, checking the car's way, within
  /// the larger of [LearningConfig.cameraWarnM] and [LearningConfig.cameraWarnS]; once each.
  List<int> camerasAhead(
    RoadEdge edge,
    int from, {
    required double alongM,
    required double speedMps,
    required double drivenM,
  }) {
    if (_camerasByEdge.isEmpty) return const [];
    final reach = max(
      LearningConfig.cameraWarnM,
      LearningConfig.cameraWarnS * speedMps,
    );
    final limits = <int>[];
    var (e, f) = (edge, from);
    var startM = -alongM;
    for (
      var hop = 0;
      hop < LearningConfig.cameraHopsMax && startM <= reach;
      hop++
    ) {
      for (final c in _camerasByEdge[e.id] ?? const <SpeedCamera>[]) {
        final n = nearestDriven(c.at, e, f);
        final aheadM = startM + n.alongM;
        final direction = c.directionDeg;
        if (aheadM < 0 ||
            aheadM > reach ||
            (direction != null &&
                bearingError(direction, n.headingDeg) >
                    LearningConfig.cameraHeadingDeg) ||
            !_warned.add(c.id)) {
          continue;
        }
        _cameraUntilM = max(_cameraUntilM, drivenM + aheadM);
        limits.add(c.maxspeedKmh ?? cost.limitKmh(e));
      }
      startM += e.lengthM;
      final at = e.other(f);
      final on = _straightOn(e, at);
      if (on == null) break;
      (e, f) = (on, at);
    }
    return limits;
  }

  /// The way on from [junction] after [edge] along the same street, the straightest within
  /// [LearningConfig.navStraightOnDeg]; null at its end.
  RoadEdge? _straightOn(RoadEdge edge, int junction) {
    final street = edge.streetId;
    if (street == null) return null;
    final name = streets[street]?.id ?? street;
    RoadEdge? best;
    var bestDeg = LearningConfig.navStraightOnDeg;
    for (final e in graph.legalExits(junction, approach: edge)) {
      if (e.id == edge.id || e.streetId == null) continue;
      if ((streets[e.streetId]?.id ?? e.streetId) != name) continue;
      final deg = turnAngle(edge, e, junction).abs();
      if (deg <= bestDeg) (best, bestDeg) = (e, deg);
    }
    return best;
  }

  static Map<int, List<SpeedCamera>> _byEdge(List<SpeedCamera> cameras) {
    final out = <int, List<SpeedCamera>>{};
    for (final c in cameras) {
      out.putIfAbsent(c.edgeId, () => []).add(c);
    }
    return out;
  }
}
