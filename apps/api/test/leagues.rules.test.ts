import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  isLeagueName,
  leagueName,
  leagueWeek,
  nextTier,
  zone,
} from "../src/modules/leagues/leagues.rules.ts";

type Vectors = {
  week: { name: string; at: string; key: string; start: string; end: string }[];
  name: { raw: string; name: string; valid: boolean }[];
};

const vectors: Vectors = JSON.parse(
  readFileSync(new URL("../../../shared/fixtures/league_vectors.json", import.meta.url), "utf8"),
);

describe("leagueWeek", () => {
  it.each(vectors.week)("$name", (v) => {
    const week = leagueWeek(new Date(v.at));
    expect(week.key).toBe(v.key);
    expect(week.start.toISOString()).toBe(new Date(v.start).toISOString());
    expect(week.end.toISOString()).toBe(new Date(v.end).toISOString());
  });
});

describe("league names", () => {
  it.each(vectors.name)('"$raw"', (v) => {
    const name = leagueName(v.raw);
    expect(name).toBe(v.name);
    expect(isLeagueName(name)).toBe(v.valid);
  });
});

describe("zones", () => {
  it("moves the top 5 up and ranks 26 to 30 down", () => {
    expect([1, 5, 6, 25, 26, 30].map((rank) => zone(rank, 2))).toEqual([
      "up",
      "up",
      "stay",
      "stay",
      "down",
      "down",
    ]);
  });

  it("keeps Highway's top and Alley's bottom where they are", () => {
    expect(zone(1, 5)).toBe("stay");
    expect(zone(30, 0)).toBe("stay");
    expect([nextTier(1, 5), nextTier(30, 0), nextTier(3, 0), nextTier(28, 4)]).toEqual([
      5, 0, 1, 3,
    ]);
  });
});
