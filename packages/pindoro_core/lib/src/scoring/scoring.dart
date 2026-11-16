enum Difficulty {
  easy,
  medium,
  hard,
  expert;

  /// Cumulative: a round at this difficulty asks every street up to it.
  Set<Difficulty> get pool => {
    for (final d in values)
      if (d.index <= index) d,
  };
}

enum Tier { perfect, great, close, miss }

/// Single source of truth on the Dart side; must equal @pindoro/geo
/// ScoringConfig (shared/fixtures prove it).
abstract final class ScoringConfig {
  /// Half the drawn width of a street by OSM road class; others use [narrowestHalfWidthM].
  static const Map<String, double> halfWidthM = {
    'motorway': 14,
    'trunk': 14,
    'primary': 10,
    'secondary': 8,
    'tertiary': 7,
  };
  static const double narrowestHalfWidthM = 5;

  /// Medium distances; every threshold is multiplied by [difficultyFactor].
  static const double perfectMarginM = 20;
  static const double greatMaxM = 100;
  static const double closeMaxM = 300;

  static double difficultyFactor(Difficulty d) => switch (d) {
    Difficulty.easy => 1.5,
    Difficulty.medium => 1.0,
    Difficulty.hard => 0.7,
    Difficulty.expert => 0.5,
  };
}

class TierThresholds {
  const TierThresholds({
    required this.perfect,
    required this.great,
    required this.close,
  });

  factory TierThresholds.forStreet(String roadClass, Difficulty difficulty) {
    final f = ScoringConfig.difficultyFactor(difficulty);
    final halfWidth =
        ScoringConfig.halfWidthM[roadClass] ??
        ScoringConfig.narrowestHalfWidthM;
    return TierThresholds(
      perfect: (halfWidth + ScoringConfig.perfectMarginM) * f,
      great: ScoringConfig.greatMaxM * f,
      close: ScoringConfig.closeMaxM * f,
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
}

/// The tier of a pin [distanceM] from the nearest part of a street of
/// [roadClass].
Tier scoreAnswer(double distanceM, String roadClass, Difficulty difficulty) =>
    TierThresholds.forStreet(roadClass, difficulty).tierFor(distanceM);
