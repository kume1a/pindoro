export type Tier = "perfect" | "great" | "close" | "miss";
export type Difficulty = "easy" | "medium" | "hard" | "expert";

// Single source of truth on the TS side; must equal pindoro_core ScoringConfig (shared/fixtures prove it).
export const ScoringConfig = {
  /** Half the drawn width of a street by OSM road class; others use narrowestHalfWidthM. */
  halfWidthM: { motorway: 14, trunk: 14, primary: 10, secondary: 8, tertiary: 7 } as Record<
    string,
    number
  >,
  narrowestHalfWidthM: 5,
  /** Medium distances; every threshold is multiplied by the difficulty factor. */
  perfectMarginM: 20,
  greatMaxM: 100,
  closeMaxM: 300,
  difficultyFactor: { easy: 1.5, medium: 1.0, hard: 0.7, expert: 0.5 },
  perfectXp: 100,
  /** Great: at − perM × (d/f − perfectMarginM), 90 → 70. */
  greatXp: { at: 90, perM: 0.25 },
  /** Close: at − perM × (d/f − greatMaxM), 60 → 30. */
  closeXp: { at: 60, perM: 0.15 },
  levelBaseXp: 1000,
  levelStepXp: 250,
} as const;

export interface TierThresholds {
  perfect: number;
  great: number;
  close: number;
  /** Difficulty factor; XP is computed on distance / factor. */
  factor: number;
}

export const thresholdsForStreet = (roadClass: string, difficulty: Difficulty): TierThresholds => {
  const f = ScoringConfig.difficultyFactor[difficulty];
  const halfWidth = ScoringConfig.halfWidthM[roadClass] ?? ScoringConfig.narrowestHalfWidthM;
  return {
    perfect: (halfWidth + ScoringConfig.perfectMarginM) * f,
    great: ScoringConfig.greatMaxM * f,
    close: ScoringConfig.closeMaxM * f,
    factor: f,
  };
};

export const tierFor = (distanceM: number, t: TierThresholds): Tier => {
  if (distanceM <= t.perfect) return "perfect";
  if (distanceM <= t.great) return "great";
  if (distanceM <= t.close) return "close";
  return "miss";
};

/** XP for a pin distanceM away that scored `tier` (from tierFor). */
export const xpFor = (tier: Tier, distanceM: number, t: TierThresholds): number => {
  const d = distanceM / t.factor;
  switch (tier) {
    case "perfect":
      return ScoringConfig.perfectXp;
    case "great":
      return Math.round(
        ScoringConfig.greatXp.at - ScoringConfig.greatXp.perM * (d - ScoringConfig.perfectMarginM),
      );
    case "close":
      return Math.round(
        ScoringConfig.closeXp.at - ScoringConfig.closeXp.perM * (d - ScoringConfig.greatMaxM),
      );
    case "miss":
      return 0;
  }
};

export interface Score {
  tier: Tier;
  xp: number;
}

/** Scores a pin distanceM from the nearest part of a street of roadClass. */
export const scoreAnswer = (
  distanceM: number,
  roadClass: string,
  difficulty: Difficulty,
): Score => {
  const t = thresholdsForStreet(roadClass, difficulty);
  const tier = tierFor(distanceM, t);
  return { tier, xp: xpFor(tier, distanceM, t) };
};

// Road trips: how much longer the drawn drive is than the shortest one, in percent of the shortest,
// scored like a pin distance. Must equal pindoro_core RouteScoring (shared/fixtures/route_vectors.json).
export const RouteScoring = {
  /** Medium percentages; each is multiplied by the difficulty factor. */
  perfectMaxPct: 3,
  greatMaxPct: 25,
  closeMaxPct: 60,
  /** Great: at − perPct × p, 90 → 60. */
  greatXp: { at: 90, perPct: 1.2 },
  /** Close: at − perPct × (p − greatMaxPct), 60 → 25. */
  closeXp: { at: 60, perPct: 1 },
} as const;

/** Scores a drawn drive of drawnM against the shortest of bestM; p is divided by the difficulty factor. */
export const scoreRoute = (drawnM: number, bestM: number, difficulty: Difficulty): Score => {
  const p = ((drawnM / bestM - 1) * 100) / ScoringConfig.difficultyFactor[difficulty];
  if (p <= RouteScoring.perfectMaxPct) return { tier: "perfect", xp: ScoringConfig.perfectXp };
  if (p <= RouteScoring.greatMaxPct) {
    return {
      tier: "great",
      xp: Math.round(RouteScoring.greatXp.at - RouteScoring.greatXp.perPct * p),
    };
  }
  if (p <= RouteScoring.closeMaxPct) {
    return {
      tier: "close",
      xp: Math.round(
        RouteScoring.closeXp.at - RouteScoring.closeXp.perPct * (p - RouteScoring.greatMaxPct),
      ),
    };
  }
  return { tier: "miss", xp: 0 };
};
