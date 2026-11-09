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

  /// XP for a pin [distanceM] away that scored [tier] (from [tierFor]).
  int xpFor(Tier tier, double distanceM) {
    final d = distanceM / factor;
    return switch (tier) {
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
  final tier = t.tierFor(distanceM);
  return (tier: tier, xp: t.xpFor(tier, distanceM));
}

/// Road trips: how much longer the drawn drive is than the shortest one, in
/// percent of the shortest, scored like a pin distance. Must equal
/// @pindoro/geo RouteScoring (shared/fixtures/route_vectors.json).
abstract final class RouteScoring {
  /// Medium percentages; each is multiplied by the difficulty factor.
  static const double perfectMaxPct = 3;
  static const double greatMaxPct = 25;
  static const double closeMaxPct = 60;

  /// Great: [greatXpAt] − [greatXpPerPct] × p, 90 → 60.
  static const double greatXpAt = 90;
  static const double greatXpPerPct = 1.2;

  /// Close: [closeXpAt] − [closeXpPerPct] × (p − [greatMaxPct]), 60 → 25.
  static const double closeXpAt = 60;
  static const double closeXpPerPct = 1;
}

/// Scores a drawn drive of [drawnM] against the shortest of [bestM]; p is
/// divided by the difficulty factor, as pin distances are.
Score scoreRoute(double drawnM, double bestM, Difficulty difficulty) {
  final p =
      (drawnM / bestM - 1) * 100 / ScoringConfig.difficultyFactor(difficulty);
  if (p <= RouteScoring.perfectMaxPct) {
    return (tier: Tier.perfect, xp: ScoringConfig.perfectXp);
  }
  if (p <= RouteScoring.greatMaxPct) {
    return (
      tier: Tier.great,
      xp: (RouteScoring.greatXpAt - RouteScoring.greatXpPerPct * p).round(),
    );
  }
  if (p <= RouteScoring.closeMaxPct) {
    return (
      tier: Tier.close,
      xp:
          (RouteScoring.closeXpAt -
                  RouteScoring.closeXpPerPct * (p - RouteScoring.greatMaxPct))
              .round(),
    );
  }
  return (tier: Tier.miss, xp: 0);
}
