import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  type Difficulty,
  decodePolyline6,
  encodePolyline6,
  type LatLng,
  pointToPolylineDistance,
  scoreAnswer,
  thresholdsForStreet,
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
  }[];
  polyline6: { name: string; points: number[][]; encoded: string; decoded: number[][] }[];
  polyline6_invalid: { name: string; encoded: string }[];
}

const s = fixture<ScoringVectors>("scoring_vectors.json");
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
    expect(scoreAnswer(v.distance_m, v.road_class, v.difficulty)).toBe(v.tier);
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
