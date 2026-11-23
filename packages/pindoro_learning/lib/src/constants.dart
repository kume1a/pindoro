import 'package:pindoro_core/pindoro_core.dart';

/// Every tunable number of the learning system, as listed in SPEC §13. Distances shared with the
/// display tiers come from [ScoringConfig] instead of being copied.
abstract final class LearningConfig {
  // Scheduler (§4)
  static const List<double> fsrsWeights = [
    0.212,
    1.2931,
    2.3065,
    8.2956,
    6.4133,
    0.8334,
    3.0194,
    0.001,
    1.8722,
    0.1666,
    0.796,
    1.4835,
    0.0614,
    0.2629,
    1.6483,
    0.6014,
    1.8729,
    0.5425,
    0.0912,
    0.0658,
    0.1542,
  ];
  static const double retentionDefault = 0.90;
  static const double retentionTierCRelief = 0.85;
  static const double tierCReliefFactor = 1.2;
  static const int maxIntervalDays = 365;
  static const double fuzzFraction = 0.05;
  static const int fuzzMinDays = 3;
  static const int relearnGapMin = 5;
  static const int relearnGapMax = 10;

  /// Relearns of one card in one session (§16.18); after them it waits for its due time.
  static const int relearnMaxPerSession = 2;
  static const int leechLapses = 6;

  // Pin grading (§5.1)
  static const double pinGoodMaxM = ScoringConfig.greatMaxM;
  static const double snapSearchM = 150;
  static const int rtHardMs = 20000;
  static const int rtEasyMs = 6000;
  static const int easyMinSuccesses = 2;

  // Other cards (§5.2)
  static const double extentEndMinM = 150;
  static const double extentEndFraction = 0.10;
  static const double extentMinLengthM = 1200;
  static const int nameCheckOptions = 6;
  static const double fuzzyNameMax = 0.25;
  static const double bearingGreatDeg = 20;
  static const double bearingCloseDeg = 45;

  // Unlocks (§3)
  /// Answers a street's pin card needs (its two same-day retrievals) before its name card opens.
  static const int unlockNameReps = 2;
  static const int unlockExtentDays = 7;
  static const double gatewayUnlockKnown = 0.70;
  static const double districtJunctionUnlockSolid = 0.80;
  static const double phase2ChunkSolid = 0.80;
  static const double bearingUnlockGridSolid = 0.50;

  // Labels (§8)
  static const double knownMinR = 0.80;
  static const int solidDays = 21;
  static const int masteredDays = 90;
  static const int masteredSideDays = 21;
  static const double coreMinLengthM = 150;

  // Session planner (§7, §16.2)
  static const Map<int, int> newPerDay = {
    15: 7,
    20: 10,
    30: 14,
    45: 21,
    60: 28,
  };
  static const int tReviewS = 12;
  static const int tNewS = 45;
  static const int timeEstimateMinSamples = 50;
  static const int answerGapCapS = 60;
  static const double backlogCapFactor = 1.5;
  static const int groupSize = 3;
  static const int reviewsPerBlock = 5;
  static const int retrieval1GapMin = 3;
  static const int retrieval1GapMax = 6;
  static const int retrieval1GapFloor = 2;
  static const int learnMoreCount = 10;
  static const int roundSteps = 20;
  static const double nearDueFraction = 0.5;

  // Curriculum (§6)
  static const int childParentMinDays = 3;
  static const int maxSiblingsPerDay = 4;
  static const int placementSamplePerDistrict = 5;
  static const int placementPassMin = 4;
  static const int placementPinS = 4;
  static const double familyOrphanM = 1500;
  static const double familyNearM = 500;
  static const double chunkNeighbourM = 50;
  static const int migrationDueMinDays = 1;
  static const int migrationDueMaxDays = 7;

  // Drills (§7)
  static const int familySweepMinChildren = 3;
  static const int familySweepWindowDays = 2;
  static const int crossingsPerDay = 1;
  static const int bearingsPerSessionMin = 1;
  static const int bearingsPerSessionMax = 3;
  static const int familySweepMax = 6;
  static const int crossingsMax = 5;

  /// A crossings drill asks at least this many Known crossings.
  static const int crossingsMin = 2;

  /// Solid streets tried for a crossings drill with two Known crossings.
  static const int crossingsTries = 8;

  // Route items (§6.5, §6.6, §7, §9)
  static const int routeNewPerDayMax = 10;
  static const double routePauseFactor = 1.2;

  /// New places a day (§16.18), each taught as an intro like a new street.
  static const int landmarkNewPerDay = 3;
  static const int phase2StableDays = 14;

  /// A turn within this of the approach heading is straight on; past [turnUTurnDeg] a U-turn.
  static const double turnStraightDeg = 30;
  static const double turnUTurnDeg = 150;
  static const double junctionCoverage = 0.90;
  static const int odSamples = 20000;
  static const double landmarkRadiusM = 60;
  static const double landmarkStructuralM = 40;
  static const double landmarkUniquenessM = 300;

  // Recitals and drives (§5.3)
  static const double stretchPerfect = 1.03;
  static const double stretchGreat = 1.25;
  static const double stretchClose = 1.60;
  static const double connectorMaxM = 150;
  static const int connectorMax = 2;
  static const double uTurnPenaltyM = RoutingConfig.uTurnPenaltyM;
  static const double recitalLandmarkBonus = 0.1;
  static const double recitalLandmarkBonusCap = 0.3;
  static const double hesitationKmh = 5;
  static const int hesitationS = 10;

  /// What a recited turn word the path doesn't make adds to the path search: soft, it only
  /// picks between near-equal paths (§16.15).
  static const double recitalTurnMismatchM = 200;

  /// The longest name, in words, a transcript phrase is matched against.
  static const int recitalNameWordsMax = 5;

  /// Name matches this close to the best count as equal; the one nearest the previous street
  /// wins (§5.3 step 2).
  static const double recitalNameTieSlack = 0.05;

  /// A drive keeps a GPS fix this far from the last one kept.
  static const double driveSampleM = 20;

  /// A fix snaps to edges within this distance.
  static const double driveSnapM = 35;

  /// What a fix's heading off an edge's direction adds to its snap, per 90°.
  static const double driveHeadingM = 20;

  /// What turning back between two fixes adds to the match, on an edge or at a junction.
  static const double driveTurnBackM = 40;

  /// What driving an edge against its one-way adds to a snap.
  static const double driveWrongWayM = 15;

  /// A stop this close to a junction is traffic, not a hesitation: the pack has no traffic
  /// signals, junctions stand in for them (§16.15).
  static const double hesitationJunctionM = 30;

  // Recital runs in the plan (§3 R, §16.15)
  /// What a recital takes in the day's minutes (report 2: about 3 minutes a day).
  static const int tRecitalS = 180;
  static const int recitalNewPerDay = 1;

  /// A route-book run starts and ends about this far from its seed turn, along its streets.
  static const double runLeadM = 800;

  /// A route-book run drives at least this many J items of the book.
  static const int runMinItems = 2;
  static const int randomRunEveryDays = 7;
  static const double randomRunMinM = 1500;
  static const double randomRunMaxM = 5000;
  static const int randomRunTries = 50;

  /// A drive that ends this close to its destination arrived there.
  static const double driveArriveM = 200;

  // Drive log (§16.23)
  /// No fix for longer than this is a GPS gap ("GPS lost").
  static const int gpsGapS = 10;

  /// A fix less accurate than this counts as none (Android's "Approximate" and iOS's "Precise:
  /// Off" locations): no recovery, credit or match from it (item 131).
  static const double coarseFixM = 50;

  /// A drive's track stays on the phone this long; its summary stays for good.
  static const int driveTrackKeepDays = 90;

  // Navigation (§16.23)
  /// Another way on within this of the route's straightness makes a junction a decision.
  static const double decisionAlikeDeg = 30;

  /// Typical speed by road class (OSRM's car profile; motorway and trunk at Georgia's limits).
  static const Map<String, double> navClassKmh = {
    'motorway': 110,
    'trunk': 90,
    'primary': 65,
    'secondary': 55,
    'tertiary': 40,
    'unclassified': 25,
    'residential': 25,
    'living_street': 10,
    'service': 15,
  };

  /// A connector's speed (an unnamed way or a link), and any class not above.
  static const double navConnectorKmh = 25;

  /// Route options (item 129): up to [navOptions] plans, each next one the quickest once the
  /// roads of the plans so far cost [navOptionPenalty] times as much, kept when it takes at
  /// most [navOptionMaxSlower] times the quickest's time and shares at most
  /// [navOptionMaxShared] of its length with each plan kept; [navOptionTries] plans at most.
  static const int navOptions = 3;
  static const double navOptionPenalty = 1.5;
  static const double navOptionMaxSlower = 1.4;
  static const double navOptionMaxShared = 0.7;
  static const int navOptionTries = 6;

  /// Georgian limits where no sign is mapped.
  static const int limitTownKmh = 60;
  static const int limitMotorwayKmh = 110;
  static const int limitLivingStreetKmh = 20;

  /// "Warn me over the limit by": the default (fines start above 15 km/h over) and the most.
  static const int speedToleranceKmh = 14;
  static const int speedToleranceMaxKmh = 20;
  static const int overspeedHoldS = 3;
  static const int overspeedRepeatS = 30;
  static const double cameraWarnM = 300;
  static const int cameraWarnS = 15;

  /// A camera tagged with a direction checks traffic heading within this of it.
  static const double cameraHeadingDeg = 60;

  /// Silent-eligible: a Known J card at this recall, not failed for this many days; a decision
  /// without one after this many drives through it on the player's own.
  static const double silentMinR = 0.85;
  static const int silentNoFailDays = 14;
  static const int silentOwnDrives = 2;

  /// The suggested level by the share of silent-eligible decisions.
  static const double levelOffShare = 0.90;
  static const double levelOffMinR = 0.75;
  static const double levelQuietShare = 0.70;
  static const double levelCoachedShare = 0.40;

  /// Fewer introduced J cards than this in the destination's raion: always Guided.
  static const int levelMinAreaJ = 5;

  /// An earlier drive is on this route when it passed this share of the route's decisions.
  static const double routeOverlap = 0.80;

  /// One level less after [stepDrives] good drives in a row, one more after as many poor ones.
  static const int stepDrives = 2;
  static const double stepDownStretch = 1.25;
  static const double stepUpStretch = 1.60;
  static const int stepUpRecoveries = 3;

  /// Recovery ends after this long back on a good path.
  static const int recoveryHoldS = 10;

  /// The frustration guard: this many recoveries within [guardWindowS], or [guardLostS] lost,
  /// switch to Coached; [guardToGuidedRecoveries] at Coached to Guided.
  static const int guardRecoveries = 2;
  static const int guardWindowS = 300;
  static const int guardLostS = 180;
  static const int guardToGuidedRecoveries = 3;

  /// Stopped: below [stoppedKmh] for [stoppedHoldS]; arrived: stopped this close to the
  /// destination.
  static const double stoppedKmh = 5;
  static const int stoppedHoldS = 2;
  static const double navArriveM = 50;

  /// Voice: the prepare prompt at the larger of [prepareM] and [prepareS] ahead, the action
  /// prompt at the larger of [actionM] and [actionS].
  static const double prepareM = 150;
  static const int prepareS = 10;
  static const double actionM = 40;
  static const int actionS = 4;

  /// A landmark this close to a junction names it in a prompt; without one the distance does.
  static const double landmarkAtM = 50;
  static const int confirmDelayS = 6;
  static const double districtCueM = 2000;
  static const int districtCueS = 180;

  /// GPS lost this long: "Still finding you" (the line shows after [gpsGapS]).
  static const int gpsLostSayS = 60;

  /// Guided's map (item 130): the road's way this far ahead of the car is straight up; the
  /// turn arrow runs from [navArrowBeforeM] before the next decision to [navArrowAfterM] after
  /// it; a lane's arrow within [laneMatchDeg] of the turn is the one to take.
  static const double navRoadAheadM = 10;
  static const double navArrowBeforeM = 35;
  static const double navArrowAfterM = 20;
  static const double laneMatchDeg = 60;

  /// Drive credit: only while recall is at most [creditMaxR]; Hard after a hesitation within
  /// [hesitationBeforeM] before the junction; none within [noCreditAfterPromptS] of a prompt or
  /// recovery.
  static const double creditMaxR = 0.92;
  static const double hesitationBeforeM = 150;
  static const int noCreditAfterPromptS = 60;

  /// A habitual corridor ([habitPasses] passes in [habitWindowDays]) credits once per
  /// [habitCreditDays].
  static const int habitPasses = 3;
  static const int habitWindowDays = 14;
  static const int habitCreditDays = 7;

  /// Preview and debrief (item 121): the key decisions, at least [keyTurnsMin] and at most
  /// [keyTurnsMax]; a junction with [complexWaysOn] or more ways on is complex. The player
  /// steps through the preview (item 129).
  static const int keyTurnsMin = 3;
  static const int keyTurnsMax = 7;
  static const int complexWaysOn = 4;

  /// The debrief waits this long after a drive.
  static const int debriefOfferHours = 24;

  /// Point to home: Perfect, Great and Close up to these errors.
  static const double pointPerfectDeg = 10;
  static const double pointGreatDeg = 25;
  static const double pointCloseDeg = 45;

  /// Your routes first (item 120): a route driven [yourRouteDrives] times in [yourRouteDays];
  /// its book junctions take up to [yourRoutesShare] of the day's new cards, [yourRoutesSlowShare]
  /// while City memory grows below [yourRoutesSlowRate] of its rate over the [yourRouteDays]
  /// before.
  static const int yourRouteDrives = 2;
  static const int yourRouteDays = 14;
  static const double yourRoutesShare = 0.25;
  static const double yourRoutesSlowShare = 0.15;
  static const double yourRoutesSlowRate = 0.80;

  /// The weekly drive goal (item 122): [weekQuietDrives] drives at Quiet or Off and
  /// [weekNewPlaces] new destination reached without help; new places are suggested at
  /// [newPlaceMinShare] of the route the player's, Surprise me at [surpriseMinShare].
  static const int weekQuietDrives = 2;
  static const int weekNewPlaces = 1;
  static const double newPlaceMinShare = 0.60;
  static const double surpriseMinShare = 0.70;

  /// Progress's routes (item 123): a route with this many drives.
  static const int frequentRouteDrives = 3;

  /// A drive starts or ends at Home or Work within this of it.
  static const double placeNearM = 300;

  // Tuning (§12, §16.17)
  /// Calibration bins over predicted recall 0–1, each this wide a share.
  static const int calibrationBins = 10;

  /// A bin is healthy when its recall is within this of the prediction (±5 points).
  static const double calibrationTolerance = 0.05;
  static const int calibrationMinReviews = 20;

  /// Reviews that moved a card before fitted weights are worth it (§12: about 1 000).
  static const int fitMinReviews = 1000;

  /// Tier C relief looks at the days played in this many days, replayed over the longer span.
  static const int tierCReliefDays = 7;
  static const int tierCReliefReplayDays = 28;

  // Motivation and maps (§8, §16.6)
  /// The City memory chart (§16.4): a point a day in a frame of this many days at first, then
  /// a point a week, showing at most the last [chartWeeks] weeks.
  static const int chartDailyDays = 14;
  static const int chartWeeks = 10;
  static const int cityMemoryMilestone = 500;
  static const int maintenanceBadgeDays = 100;
  static const int bullseyeBadgePerfects = 10;
  static const int onFireBadgeDays = 7;
  static const int explorerBadgeDistricts = 5;

  /// Recall rate (§16.18) over the due reviews of the last this many days.
  static const int recallWindowDays = 30;

  /// Night owl: an answer from midnight until this local hour.
  static const int nightOwlBefore = 4;
}
