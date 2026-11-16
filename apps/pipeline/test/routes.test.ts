import { RoadGraph } from "@pindoro/geo";
import { describe, expect, it } from "vitest";
import { bridgeAhead, type Edge } from "../src/routes.ts";

/** Junctions 1–5 on a line, 3 also on a side street to 6; edge 3→4 is the bridge. */
const edge = (id: number, from: number, to: number, bridge: string | null = null): Edge => ({
  id,
  from,
  to,
  streetId: String(id),
  lengthM: 100,
  oneway: "both",
  tier: "B",
  chunk: null,
  bridge,
  outBearing: 90,
  inBearing: 90,
});
const edges = [edge(1, 1, 2), edge(2, 2, 3), edge(3, 3, 4, "w9"), edge(4, 4, 5), edge(5, 3, 6)];
const graph = new RoadGraph(
  new Map([1, 2, 3, 4, 5, 6].map((j) => [j, { lat: 41.7, lon: 44.8 + j * 0.001 }])),
  edges,
);
const byId = (id: number): Edge => edges.find((e) => e.id === id) as Edge;

describe("bridgeAhead", () => {
  it("finds the bridge on the exit itself or past turns with no choice", () => {
    expect(bridgeAhead(graph, byId(3), 3)).toBe("w9");
    expect(bridgeAhead(graph, byId(1), 1)).toBeNull(); // junction 3 offers a choice first
    expect(bridgeAhead(graph, byId(4), 5)).toBe("w9"); // driving west from 5: 4 has one way on
  });
});
