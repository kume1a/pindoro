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

  static const int perfectXp = 100;

  /// Great: [greatXpAt] − [greatXpPerM] × (d/f − [perfectMarginM]), 90 → 70.
  static const double greatXpAt = 90;
  static const double greatXpPerM = 0.25;

  /// Close: [closeXpAt] − [closeXpPerM] × (d/f − [greatMaxM]), 60 → 30.
  static const double closeXpAt = 60;
  static const double closeXpPerM = 0.15;

  static const int levelBaseXp = 1000;
  static const int levelStepXp = 250;
}

class TierThresholds {
  const TierThresholds({
    required this.perfect,
    required this.great,
    required this.close,
    required this.factor,
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
      factor: f,
    );
  }

  final double perfect;
  final double great;
  final double close;

  /// Difficulty factor; XP is computed on distance / factor so the curve keeps
  /// its shape at every difficulty.
  final double factor;

  Tier tierFor(double distanceM) {
    if (distanceM <= perfect) return Tier.perfect;
    if (distanceM <= great) return Tier.great;
    if (distanceM <= close) return Tier.close;
    return Tier.miss;
  }

  int xpFor(double distanceM) {
    final d = distanceM / factor;
    return switch (tierFor(distanceM)) {
      Tier.perfect => ScoringConfig.perfectXp,
      Tier.great =>
        (ScoringConfig.greatXpAt -
                ScoringConfig.greatXpPerM * (d - ScoringConfig.perfectMarginM))
            .round(),
      Tier.close =>
        (ScoringConfig.closeXpAt -
                ScoringConfig.closeXpPerM * (d - ScoringConfig.greatMaxM))
            .round(),
      Tier.miss => 0,
    };
  }
}

typedef Score = ({Tier tier, int xp});

/// Scores a pin [distanceM] from the nearest part of a street of [roadClass].
Score scoreAnswer(double distanceM, String roadClass, Difficulty difficulty) {
  final t = TierThresholds.forStreet(roadClass, difficulty);
  return (tier: t.tierFor(distanceM), xp: t.xpFor(distanceM));
}
