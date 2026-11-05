export type Tier = "perfect" | "great" | "close" | "miss";
export type Difficulty = "easy" | "medium" | "hard" | "expert";

// Single source of truth on the TS side; must equal pindoro_core ScoringConfig (shared/fixtures prove it).
export const ScoringConfig = {
  thresholdFloorM: { perfect: 20, great: 60, close: 200 },
  thresholdRatio: { perfect: 0.005, great: 0.02, close: 0.07 },
  difficultyFactor: { easy: 1.5, medium: 1.0, hard: 0.7, expert: 0.5 },
  perfectPoints: 100,
  greatPoints: { from: 90, to: 70 },
  closePoints: { from: 60, to: 30 },
  xpBonus: { easy: 1.0, medium: 1.1, hard: 1.25, expert: 1.5 },
  levelBaseXp: 1000,
  levelStepXp: 250,
} as const;

export interface TierThresholds {
  perfect: number;
  great: number;
  close: number;
}

export const thresholdsForArea = (areaM2: number, difficulty: Difficulty): TierThresholds => {
  const side = Math.sqrt(areaM2);
  const factor = ScoringConfig.difficultyFactor[difficulty];
  const band = (tier: keyof TierThresholds): number =>
    Math.max(ScoringConfig.thresholdFloorM[tier], ScoringConfig.thresholdRatio[tier] * side) *
    factor;
  return { perfect: band("perfect"), great: band("great"), close: band("close") };
};

export const tierFor = (distanceM: number, t: TierThresholds): Tier => {
  if (distanceM <= t.perfect) return "perfect";
  if (distanceM <= t.great) return "great";
  if (distanceM <= t.close) return "close";
  return "miss";
};

const lerpPoints = (
  range: { from: number; to: number },
  lo: number,
  hi: number,
  d: number,
): number => Math.round(range.from + ((range.to - range.from) * (d - lo)) / (hi - lo));

export const pointsFor = (distanceM: number, t: TierThresholds): number => {
  switch (tierFor(distanceM, t)) {
    case "perfect":
      return ScoringConfig.perfectPoints;
    case "great":
      return lerpPoints(ScoringConfig.greatPoints, t.perfect, t.great, distanceM);
    case "close":
      return lerpPoints(ScoringConfig.closePoints, t.great, t.close, distanceM);
    case "miss":
      return 0;
  }
};

export const xpFor = (points: number, difficulty: Difficulty): number =>
  Math.round(points * ScoringConfig.xpBonus[difficulty]);

export interface Score {
  tier: Tier;
  points: number;
  xp: number;
}

export const scoreAnswer = (distanceM: number, areaM2: number, difficulty: Difficulty): Score => {
  const t = thresholdsForArea(areaM2, difficulty);
  const points = pointsFor(distanceM, t);
  return { tier: tierFor(distanceM, t), points, xp: xpFor(points, difficulty) };
};
