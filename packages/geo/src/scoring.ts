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

export const xpFor = (distanceM: number, t: TierThresholds): number => {
  const d = distanceM / t.factor;
  switch (tierFor(distanceM, t)) {
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
  return { tier: tierFor(distanceM, t), xp: xpFor(distanceM, t) };
};
