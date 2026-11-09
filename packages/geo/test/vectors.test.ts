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
  scoreRoute,
  thresholdsForStreet,
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
    road_class: string;
    difficulty: Difficulty;
    perfect: number;
    great: number;
    close: number;
  }[];
  score: {
    name: string;
    distance_m: number;
    road_class: string;
    difficulty: Difficulty;
    tier: string;
    xp: number;
  }[];
  polyline6: { name: string; points: number[][]; encoded: string; decoded: number[][] }[];
  polyline6_invalid: { name: string; encoded: string }[];
}

interface LevelsVectors {
  requirement: { n: number; xp: number }[];
  total_xp_to_reach: { n: number; xp: number }[];
  progress: { xp: number; level: number; xpIntoLevel: number; xpForLevel: number }[];
}

const s = fixture<ScoringVectors>("scoring_vectors.json");
const l = fixture<LevelsVectors>("levels_vectors.json");
const r = fixture<{
  route_score: {
    name: string;
    drawn_m: number;
    best_m: number;
    difficulty: Difficulty;
    tier: string;
    xp: number;
  }[];
}>("route_vectors.json");
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
  it.each(s.thresholds)("thresholds for $road_class $difficulty", (v) => {
    const t = thresholdsForStreet(v.road_class, v.difficulty);
    expect(t.perfect).toBeCloseTo(v.perfect, 5);
    expect(t.great).toBeCloseTo(v.great, 5);
    expect(t.close).toBeCloseTo(v.close, 5);
  });

  it.each(s.score)("$name", (v) => {
    expect(scoreAnswer(v.distance_m, v.road_class, v.difficulty)).toEqual({
      tier: v.tier,
      xp: v.xp,
    });
  });
});

describe("polyline6", () => {
  it.each(s.polyline6)("$name", (v) => {
    expect(encodePolyline6(v.points.map(ll))).toBe(v.encoded);
    expect(decodePolyline6(v.encoded).map((p) => [p.lat, p.lon])).toEqual(v.decoded);
  });

  it.each(s.polyline6_invalid)("rejects $name", (v) => {
    expect(() => decodePolyline6(v.encoded)).toThrow(RangeError);
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

describe("route scoring", () => {
  it.each(r.route_score)("$name", (v) => {
    expect(scoreRoute(v.drawn_m, v.best_m, v.difficulty)).toEqual({ tier: v.tier, xp: v.xp });
  });
});
