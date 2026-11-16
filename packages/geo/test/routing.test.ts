import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { type LatLng, onewayOf, type RoadEdge, RoadGraph, RoutingConfig } from "../src/index.ts";

interface Vectors {
  u_turn_penalty_m: number;
  graphs: Record<
    string,
    {
      junctions: Record<string, [number, number]>;
      edges: { id: number; from: number; to: number; length_m: number; oneway: number }[];
      restrictions: { from_edge: number; via: number; to_edge: number; only: boolean }[];
    }
  >;
  routes: {
    name: string;
    graph: string;
    from: number;
    goals: number[];
    junctions?: number[];
    edges: number[] | null;
    length_m?: number;
    cost_m?: number;
  }[];
  exits: {
    name: string;
    graph: string;
    junction: number;
    approach: number | null;
    exits: number[];
  }[];
}

const v: Vectors = JSON.parse(
  readFileSync(
    new URL("../../../shared/fixtures/directed_route_vectors.json", import.meta.url),
    "utf8",
  ),
);

const graphOf = (name: string): RoadGraph => {
  const g = v.graphs[name];
  if (g === undefined) throw new Error(`no graph ${name}`);
  const junctions = new Map<number, LatLng>(
    Object.entries(g.junctions).map(([id, [lat, lon]]): [number, LatLng] => [
      Number(id),
      { lat, lon },
    ]),
  );
  const edges: RoadEdge[] = g.edges.map((e) => ({
    id: e.id,
    from: e.from,
    to: e.to,
    streetId: `e${e.id}`,
    lengthM: e.length_m,
    oneway: onewayOf(e.oneway),
  }));
  return new RoadGraph(
    junctions,
    edges,
    g.restrictions.map((r) => ({
      fromEdge: r.from_edge,
      via: r.via,
      toEdge: r.to_edge,
      only: r.only,
    })),
  );
};

describe("directed routing", () => {
  it("uses the vectors' U-turn penalty", () => {
    expect(RoutingConfig.uTurnPenaltyM).toBe(v.u_turn_penalty_m);
  });

  describe("shortestRoute", () => {
    for (const c of v.routes) {
      it(c.name, () => {
        const route = graphOf(c.graph).shortestRoute(c.from, new Set(c.goals));
        if (c.edges === null) {
          expect(route).toBeNull();
          return;
        }
        expect(route).toEqual({
          junctions: c.junctions,
          edges: c.edges,
          lengthM: c.length_m,
          costM: c.cost_m,
        });
      });
    }
  });

  describe("legalExits", () => {
    for (const c of v.exits) {
      it(c.name, () => {
        const graph = graphOf(c.graph);
        const approach =
          c.approach === null ? undefined : graph.edges.find((e) => e.id === c.approach);
        expect(graph.legalExits(c.junction, approach).map((e) => e.id)).toEqual(c.exits);
      });
    }
  });

  it("reads the pack's oneway column", () => {
    expect([onewayOf(1), onewayOf(-1), onewayOf(0), onewayOf(null)]).toEqual([
      "forward",
      "backward",
      "both",
      "both",
    ]);
  });
});
