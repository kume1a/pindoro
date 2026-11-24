import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'constants.dart';
import 'drive_log.dart';
import 'nav_level.dart';
import 'nav_plan.dart';
import 'nav_stop.dart';

/// What navigation says, most urgent first (SPEC §16.23 items 115, 117, 127): when two come
/// together the first wins and the other is dropped.
enum PromptKind {
  action,
  camera,
  guard,
  recovery,
  prepare,
  confirmation,
  district,
  stillFinding,
}

/// A prompt for the app to word and speak: the [decision] of an action, prepare or recovery
/// prompt ([distanceM] when no landmark or lights name it); a confirmation's [street]; a
/// district cue's [district]; with the [headingDeg] driven; a camera's [limitKmh].
typedef NavPrompt = ({
  PromptKind kind,
  NavDecision? decision,
  double? distanceM,
  NamedStreet? street,
  String? district,
  double? headingDeg,
  int? limitKmh,
});

/// A junction passed on a drive with a way on to choose (SPEC §16.23 item 124): the move made
/// ([key] its J item id), whether the plan had a decision there ([planned]; a wrong turn
/// elsewhere has none), whether it kept a good path ([ok]; null in a GPS gap), the level and
/// help then, and whether a recovery was on within [LearningConfig.noCreditAfterPromptS].
typedef PassedDecision = ({
  int junction,
  RoadEdge? approach,
  RoadEdge exit,
  String? key,
  bool planned,
  bool? ok,
  DateTime at,
  DriveLevel level,
  NavHelp help,
  bool recentHelp,
});

/// What the drive screen shows after a fix or a tick (boards V32-20 to V32-41).
typedef NavView = ({
  DriveLevel level,
  bool recovering,

  /// Seconds back on a good path while [recovering]: the 10 s ring.
  double? goodS,
  bool stopped,
  bool arrived,

  /// Seconds since the last fix once over [LearningConfig.gpsGapS]; null while GPS is fine.
  int? gpsLostS,
  LatLng? at,
  double? headingDeg,

  /// The car on its plan and the way the road runs there ([LearningConfig.navRoadAheadM]
  /// ahead): Guided's car and bearing, the road ahead straight up (item 130). Null off the
  /// plan or before its first junction.
  ({LatLng at, double headingDeg})? onRoad,

  /// The road from the car to the plan's first junction while it is still short of it (the
  /// plan's route starts there); empty once on the route.
  Polyline toPlan,
  double speedKmh,
  int? limitKmh,

  /// Over the limit plus the tolerance for [LearningConfig.overspeedHoldS]: the sign pulses.
  bool over,

  /// A camera was warned of and isn't passed yet.
  bool camera,
  NavDecision? next,
  double? nextInM,

  /// How far before [next] its approach began (the plate shows from the prepare point); null
  /// before it.
  double? prepareM,

  /// The decision after [next] when it comes within the prepare reach of it: "then".
  NavDecision? then,

  /// The first decision of a new route after a wrong turn in Guided.
  bool newRoute,

  /// The street just turned onto and its heading, until the voice confirms it.
  ({NamedStreet street, double headingDeg})? turned,

  /// The car's street.
  NamedStreet? street,
  String? district,

  /// The metres driven so far: with [leftM], the bar's progress.
  double drivenM,

  /// The plan's metres and seconds left.
  double? leftM,
  double? leftS,

  /// The next stop's side of the road (the destination's once no stop is left) while the car
  /// is on that road (items 132, 134).
  NavSide? side,
  NavPlan? plan,

  /// The stop on the way reached with this fix (item 134), for this view only.
  NavStop? reached,

  /// The metres to the next stop on the way; null without one.
  double? viaInM,
});

/// One step of navigation: the view, the prompts due (most urgent first; each is due once, so
/// the app says them all), and whether to chime for speed.
typedef NavUpdate = ({NavView view, List<NavPrompt> prompts, bool chime});

/// [m] to the next turn or stop as it is said and shown: to [LearningConfig.navRoundM], and at
/// least that.
double navRoundedM(double m) => max(
  LearningConfig.navRoundM,
  (m / LearningConfig.navRoundM).round() * LearningConfig.navRoundM,
);
