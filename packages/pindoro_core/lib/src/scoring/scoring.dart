import 'dart:math' as math;

enum Difficulty { easy, medium, hard, expert }

enum Tier { perfect, great, close, miss }

/// Single source of truth on the Dart side; must equal @pindoro/geo
/// ScoringConfig (shared/fixtures prove it).
abstract final class ScoringConfig {
  static const double perfectFloorM = 20;
  static const double greatFloorM = 60;
  static const double closeFloorM = 200;

  static const double perfectRatio = 0.005;
  static const double greatRatio = 0.02;
  static const double closeRatio = 0.07;

  static double difficultyFactor(Difficulty d) => switch (d) {
    Difficulty.easy => 1.5,
    Difficulty.medium => 1.0,
    Difficulty.hard => 0.7,
    Difficulty.expert => 0.5,
  };

  static const int perfectPoints = 100;
  static const double greatPointsFrom = 90;
  static const double greatPointsTo = 70;
  static const double closePointsFrom = 60;
  static const double closePointsTo = 30;

  static double xpBonus(Difficulty d) => switch (d) {
    Difficulty.easy => 1.0,
    Difficulty.medium => 1.1,
    Difficulty.hard => 1.25,
    Difficulty.expert => 1.5,
  };

  static const int levelBaseXp = 1000;
  static const int levelStepXp = 250;
}

class TierThresholds {
  const TierThresholds({
    required this.perfect,
    required this.great,
    required this.close,
  });

  /// Bands scale with the side length L = sqrt(area) of the played area.
  factory TierThresholds.forArea(double areaM2, Difficulty difficulty) {
    final side = math.sqrt(areaM2);
    final factor = ScoringConfig.difficultyFactor(difficulty);
    double band(double floor, double ratio) =>
        math.max(floor, ratio * side) * factor;
    return TierThresholds(
      perfect: band(ScoringConfig.perfectFloorM, ScoringConfig.perfectRatio),
      great: band(ScoringConfig.greatFloorM, ScoringConfig.greatRatio),
      close: band(ScoringConfig.closeFloorM, ScoringConfig.closeRatio),
    );
  }

  final double perfect;
  final double great;
  final double close;

  Tier tierFor(double distanceM) {
    if (distanceM <= perfect) return Tier.perfect;
    if (distanceM <= great) return Tier.great;
    if (distanceM <= close) return Tier.close;
    return Tier.miss;
  }

  int pointsFor(double distanceM) => switch (tierFor(distanceM)) {
    Tier.perfect => ScoringConfig.perfectPoints,
    Tier.great => _lerpPoints(
      ScoringConfig.greatPointsFrom,
      ScoringConfig.greatPointsTo,
      perfect,
      great,
      distanceM,
    ),
    Tier.close => _lerpPoints(
      ScoringConfig.closePointsFrom,
      ScoringConfig.closePointsTo,
      great,
      close,
      distanceM,
    ),
    Tier.miss => 0,
  };
}

int _lerpPoints(double from, double to, double lo, double hi, double d) =>
    (from + (to - from) * (d - lo) / (hi - lo)).round();

int xpFor(int points, Difficulty difficulty) =>
    (points * ScoringConfig.xpBonus(difficulty)).round();

typedef Score = ({Tier tier, int points, int xp});

Score scoreAnswer(double distanceM, double areaM2, Difficulty difficulty) {
  final t = TierThresholds.forArea(areaM2, difficulty);
  final points = t.pointsFor(distanceM);
  return (
    tier: t.tierFor(distanceM),
    points: points,
    xp: xpFor(points, difficulty),
  );
}
