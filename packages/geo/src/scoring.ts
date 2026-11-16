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
} as const;

export interface TierThresholds {
  perfect: number;
  great: number;
  close: number;
}

export const thresholdsForStreet = (roadClass: string, difficulty: Difficulty): TierThresholds => {
  const f = ScoringConfig.difficultyFactor[difficulty];
  const halfWidth = ScoringConfig.halfWidthM[roadClass] ?? ScoringConfig.narrowestHalfWidthM;
  return {
    perfect: (halfWidth + ScoringConfig.perfectMarginM) * f,
    great: ScoringConfig.greatMaxM * f,
    close: ScoringConfig.closeMaxM * f,
  };
};

export const tierFor = (distanceM: number, t: TierThresholds): Tier => {
  if (distanceM <= t.perfect) return "perfect";
  if (distanceM <= t.great) return "great";
  if (distanceM <= t.close) return "close";
  return "miss";
};

/** The tier of a pin distanceM from the nearest part of a street of roadClass. */
export const scoreAnswer = (distanceM: number, roadClass: string, difficulty: Difficulty): Tier =>
  tierFor(distanceM, thresholdsForStreet(roadClass, difficulty));
