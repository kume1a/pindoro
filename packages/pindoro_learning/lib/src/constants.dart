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
  static const double retentionScene = 0.85;
  static const double retentionTierCRelief = 0.85;
  static const double tierCReliefFactor = 1.2;
  static const int maxIntervalDays = 365;
  static const double fuzzFraction = 0.05;
  static const int fuzzMinDays = 3;
  static const int relearnGapMin = 5;
  static const int relearnGapMax = 10;
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
  static const int nameCheckEvery = 10;
  static const int nameCheckOptions = 6;
  static const double fuzzyNameMax = 0.25;
  static const double bearingGreatDeg = 20;
  static const double bearingCloseDeg = 45;

  // Unlocks (§3)
  static const int unlockNameDays = 7;
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
  static const Map<int, int> newPerDay = {15: 7, 20: 10, 30: 14};
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
  static const int learnMoreCount = 5;
  static const double nearDueFraction = 0.5;

  // Curriculum (§6)
  static const double tierBShare = 0.60;
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

  // Route items (§6.5, §6.6, §7, §9)
  static const int routeNewPerDayMax = 10;
  static const double routePauseFactor = 1.2;
  static const int phase2StableDays = 14;
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
  static const double uTurnPenaltyM = 250;
  static const double recitalLandmarkBonus = 0.1;
  static const double recitalLandmarkBonusCap = 0.3;
  static const double hesitationKmh = 5;
  static const int hesitationS = 10;

  // Imagery (§10)
  static const double sceneApproachMinM = 25;
  static const double sceneApproachMaxM = 40;

  // Motivation and maps (§8, §16.6)
  static const int cityMemoryMilestone = 500;
  static const int maintenanceBadgeDays = 100;

  /// Night owl: an answer from midnight until this local hour.
  static const int nightOwlBefore = 4;
  static const int knownLabelMax = 12;
}
