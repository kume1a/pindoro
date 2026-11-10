// The weekly league rules. pindoro_core `progress/league.dart` holds the week and name rules too;
// both pass shared/fixtures/league_vectors.json.

export const LEAGUE = {
  /** Alley, Lane, Street, Avenue, Boulevard, Highway. */
  tiers: 6,
  size: 30,
  promote: 5,
  demote: 5,
  nameMin: 2,
  nameMax: 20,
  /** Weeks run on Tbilisi time, which has no daylight saving. */
  offsetMs: 4 * 60 * 60 * 1000,
} as const;

const DAY_MS = 24 * 60 * 60 * 1000;

export type LeagueWeek = { key: string; start: Date; end: Date };

/** The league week holding `now`: its Monday as `YYYY-MM-DD` and its UTC bounds. */
export const leagueWeek = (now: Date): LeagueWeek => {
  const local = new Date(now.getTime() + LEAGUE.offsetMs);
  const sinceMonday = (local.getUTCDay() + 6) % 7;
  const monday = Date.UTC(
    local.getUTCFullYear(),
    local.getUTCMonth(),
    local.getUTCDate() - sinceMonday,
  );
  const start = monday - LEAGUE.offsetMs;
  return {
    key: new Date(monday).toISOString().slice(0, 10),
    start: new Date(start),
    end: new Date(start + 7 * DAY_MS),
  };
};

/** `raw` trimmed, with runs of whitespace as one space. */
export const leagueName = (raw: string): string => raw.trim().replace(/\s+/gu, " ");

const nameShape = /^\p{L}[\p{L} .'’-]*$/u;

/** 2–20 characters, a letter first, then letters, spaces and `. ' ’ -`. */
export const isLeagueName = (name: string): boolean => {
  const length = [...name].length;
  return length >= LEAGUE.nameMin && length <= LEAGUE.nameMax && nameShape.test(name);
};

export type Zone = "up" | "stay" | "down";

/** Where `rank` (1-based) in a league of `tier` moves at the week's end. */
export const zone = (rank: number, tier: number): Zone => {
  if (rank <= LEAGUE.promote && tier < LEAGUE.tiers - 1) return "up";
  if (rank > LEAGUE.size - LEAGUE.demote && tier > 0) return "down";
  return "stay";
};

export const nextTier = (rank: number, tier: number): number =>
  tier + { up: 1, stay: 0, down: -1 }[zone(rank, tier)];
