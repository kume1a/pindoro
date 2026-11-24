import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'constants.dart';
import 'grader.dart';
import 'nav_plan.dart';

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
    final turn = angleDiffDeg(first, bearingDegrees(line[k], line[k + 1]));
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
