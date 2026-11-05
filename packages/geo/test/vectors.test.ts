import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  type Difficulty,
  decodePolyline6,
  encodePolyline6,
  type LatLng,
  levelForXp,
  pointToPolylineDistance,
  progressWithinLevel,
  requirement,
  scoreAnswer,
  thresholdsForArea,
  totalXpToReach,
} from "../src/index.ts";

const fixture = <T>(name: string): T =>
  JSON.parse(readFileSync(new URL(`../../../shared/fixtures/${name}`, import.meta.url), "utf8"));

const ll = ([lat, lon]: number[]): LatLng => ({ lat: lat as number, lon: lon as number });

interface ScoringVectors {
  distance_tolerance_m: number;
  distance: {
    name: string;
    point: number[];
    lines: number[][][];
    distance_m: number;
    nearest: number[];
  }[];
  thresholds: {
    area_m2: number;
    difficulty: Difficulty;
    perfect: number;
    great: number;
    close: number;
  }[];
  score: {
    distance_m: number;
    area_m2: number;
    difficulty: Difficulty;
    tier: string;
    points: number;
    xp: number;
  }[];
  polyline6: { name: string; points: number[][]; encoded: string; decoded: number[][] }[];
}

interface LevelsVectors {
  requirement: { n: number; xp: number }[];
  total_xp_to_reach: { n: number; xp: number }[];
  progress: { xp: number; level: number; xpIntoLevel: number; xpForLevel: number }[];
}

const s = fixture<ScoringVectors>("scoring_vectors.json");
const l = fixture<LevelsVectors>("levels_vectors.json");
const tol = s.distance_tolerance_m;

describe("pointToPolylineDistance", () => {
  it.each(s.distance)("$name", (v) => {
    const res = pointToPolylineDistance(
      ll(v.point),
      v.lines.map((line) => line.map(ll)),
    );
    expect(Math.abs(res.distanceMeters - v.distance_m)).toBeLessThanOrEqual(tol);
    const back = pointToPolylineDistance(res.nearestPoint, [[ll(v.nearest)]]);
    expect(back.distanceMeters).toBeLessThanOrEqual(tol);
  });

  it("rejects an empty polyline", () => {
    expect(() => pointToPolylineDistance({ lat: 0, lon: 0 }, [])).toThrow(RangeError);
  });
});

describe("scoring", () => {
  it.each(s.thresholds)("thresholds for $area_m2 m² $difficulty", (v) => {
    const t = thresholdsForArea(v.area_m2, v.difficulty);
    expect(t.perfect).toBeCloseTo(v.perfect, 5);
    expect(t.great).toBeCloseTo(v.great, 5);
    expect(t.close).toBeCloseTo(v.close, 5);
  });

  it.each(s.score)("$distance_m m in $area_m2 m² $difficulty -> $tier", (v) => {
    expect(scoreAnswer(v.distance_m, v.area_m2, v.difficulty)).toEqual({
      tier: v.tier,
      points: v.points,
      xp: v.xp,
    });
  });
});

describe("polyline6", () => {
  it.each(s.polyline6)("$name", (v) => {
    expect(encodePolyline6(v.points.map(ll))).toBe(v.encoded);
    expect(decodePolyline6(v.encoded).map((p) => [p.lat, p.lon])).toEqual(v.decoded);
  });
});

describe("levels", () => {
  it.each(l.requirement)("requirement($n) = $xp", ({ n, xp }) => expect(requirement(n)).toBe(xp));
  it.each(l.total_xp_to_reach)("totalXpToReach($n) = $xp", ({ n, xp }) =>
    expect(totalXpToReach(n)).toBe(xp),
  );
  it.each(l.progress)("$xp xp -> level $level", ({ xp, ...expected }) => {
    expect(levelForXp(xp)).toBe(expected.level);
    expect(progressWithinLevel(xp)).toEqual(expected);
  });
});
