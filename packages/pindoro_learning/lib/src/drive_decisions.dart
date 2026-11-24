import 'package:pindoro_core/pindoro_core.dart';

import 'constants.dart';
import 'drive.dart';
import 'drive_log.dart';
import 'nav_level.dart';
import 'nav_plan.dart';
import 'nav_view.dart';
import 'recital.dart';

/// The decisions a drive's cards are reviewed by: the navigator's [passed], unless the drive
/// was Off throughout ([startLevel] and [mostHelp]) or had no navigator, then the [graded]
/// path's (item 124).
List<PassedDecision> reviewedDecisions(
  RoadGraph graph, {
  required DriveLevel startLevel,
  required DriveLevel mostHelp,
  required List<PassedDecision>? passed,
  required RecitalResult? graded,
  required List<DriveFix> fixes,
  Map<int, int> junctionNodes = const {},
}) {
  final gpsFree = startLevel == DriveLevel.off && mostHelp == DriveLevel.off;
  if (!gpsFree && passed != null) return passed;
  return graded == null
      ? const []
      : offDriveDecisions(graph, graded, fixes, junctionNodes: junctionNodes);
}

/// The junctions with a way on to choose on a graded GPS-free drive, for the drive log (SPEC
/// §16.23 item 124): each move with its J item id, whether navigation calls it a decision
/// (item 112), whether it kept a good path, and the time of the fix nearest the junction. No
/// help at Off.
List<PassedDecision> offDriveDecisions(
  RoadGraph graph,
  RecitalResult graded,
  List<DriveFix> fixes, {
  Map<int, int> junctionNodes = const {},
}) => [
  for (final d in graded.decisions)
    (
      junction: d.junction,
      approach: d.approach,
      exit: d.exit,
      key: junctionKey(junctionNodes, d.junction, d.approach, d.exit),
      planned: isDecision(
        graph,
        d.junction,
        d.approach,
        d.exit,
        newStreet: d.newStreet,
      ),
      ok: d.correct,
      at: _nearestFix(fixes, graph.at(d.junction)),
      level: DriveLevel.off,
      help: NavHelp.none,
      recentHelp: false,
    ),
];

DateTime _nearestFix(List<DriveFix> fixes, LatLng p) => fixes
    .where((f) => !isCoarse(f))
    .reduce(
      (a, b) => distanceBetween(b.at, p) < distanceBetween(a.at, p) ? b : a,
    )
    .t;

/// Whether the drive [match] hesitated within [LearningConfig.hesitationBeforeM] before the
/// [decision]'s junction (SPEC §16.23 item 119: Hard, not Good).
bool hesitatedNear(
  RoadGraph graph,
  DriveMatch match,
  PassedDecision decision,
) => match.hesitations.any(
  (h) =>
      !h.t.isAfter(decision.at) &&
      distanceBetween(h.at, graph.at(decision.junction)) <=
          LearningConfig.hesitationBeforeM,
);
