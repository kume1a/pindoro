import { ScoringConfig } from "./scoring.ts";

const { levelBaseXp, levelStepXp } = ScoringConfig;

/** XP needed to go from level n to n + 1. */
export const requirement = (n: number): number => levelBaseXp + levelStepXp * (n - 1);

/** Cumulative XP at which level n starts (level 1 starts at 0). */
export const totalXpToReach = (n: number): number =>
  levelBaseXp * (n - 1) + (levelStepXp / 2) * (n - 1) * (n - 2);

export const levelForXp = (xp: number): number => {
  let n = 1;
  while (totalXpToReach(n + 1) <= xp) n++;
  return n;
};

export interface LevelProgress {
  level: number;
  xpIntoLevel: number;
  xpForLevel: number;
}

export const progressWithinLevel = (xp: number): LevelProgress => {
  const level = levelForXp(xp);
  return { level, xpIntoLevel: xp - totalXpToReach(level), xpForLevel: requirement(level) };
};
