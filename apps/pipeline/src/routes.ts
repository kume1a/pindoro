import { distanceBetween, onewayOf, type RoadEdge, RoadGraph } from "@pindoro/geo";
import type { Sql } from "postgres";

/** SPEC §13: `odSamples`, `junctionCoverage`, `landmarkRadiusM`, `landmarkStructuralM`. */
export const COVERAGE = {
  pairs: 20_000,
  share: 0.9,
  landmarkM: 60,
  structuralM: 40,
  seed: 1,
} as const;

export type CoverageOptions = { [K in keyof typeof COVERAGE]: number };

type Tier = "A" | "B" | "C";

export interface Edge extends RoadEdge {
  tier: Tier | null;
  chunk: string | null;
  bridge: string | null;
  /** Degrees from north: leaving `from`, and arriving at `to`. */
  outBearing: number;
  inBearing: number;
}

interface Decision {
  junction: number;
  approach: Edge;
  exit: Edge;
  count: number;
  destinations: Map<string, number>;
}

/** mulberry32: a small seeded generator, so a build draws the same pairs every time. */
const random = (seed: number): (() => number) => {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
};

/** Picks street edges with a chance in proportion to their length. */
const byLength = (edges: Edge[], next: () => number): (() => Edge) => {
  const streets = edges.filter((e) => e.streetId !== null);
  const cumulative: number[] = [];
  let total = 0;
  for (const e of streets) {
    total += e.lengthM;
    cumulative.push(total);
  }
  return () => {
    const x = next() * total;
    let lo = 0;
    let hi = cumulative.length - 1;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if ((cumulative[mid] ?? 0) < x) lo = mid + 1;
      else hi = mid;
    }
    return streets[lo] as Edge;
  };
};

/**
 * The bridge the exit leads onto: the exit edge's own, or one met before the next junction with a
 * choice (a bridge way often starts past the turn that takes it).
 */
export const bridgeAhead = (graph: RoadGraph, exit: Edge, junction: number): string | null => {
  let edge = exit;
  let at = edge.from === junction ? edge.to : edge.from;
  for (let step = 0; step < BRIDGE_LOOKAHEAD; step++) {
    if (edge.bridge !== null) return edge.bridge;
    const ways = graph.legalExits(at, edge).filter((e) => e.id !== edge.id);
    if (ways.length !== 1) return null;
    edge = ways[0] as Edge;
    at = edge.from === at ? edge.to : edge.from;
  }
  return null;
};

/** Edges followed past a turn looking for a bridge. */
const BRIDGE_LOOKAHEAD = 8;

const layerOf = (d: Decision, bridge: string | null): { layer: string; chunk: string | null } => {
  const { approach: a, exit: x } = d;
  const main = (t: Tier | null): boolean => t === "A" || t === "B";
  if (bridge !== null) return { layer: "bridge", chunk: null };
  if (a.tier === "C" && main(x.tier)) return { layer: "gateway_out", chunk: a.chunk };
  if (main(a.tier) && x.tier === "C") return { layer: "gateway_in", chunk: x.chunk };
  if (a.tier === "A" && x.tier === "A") return { layer: "skeleton", chunk: null };
  return { layer: "district", chunk: null };
};

const mostCommon = (counts: Map<string, number>): string | null =>
  [...counts.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0]?.[0] ?? null;

interface Landmark {
  id: string;
  junction: number;
  base: number;
  lat: number;
  lon: number;
}

/**
 * The landmark for a turn (SPEC §6.6, §9): within `landmarkM` of the junction, the highest base
 * salience plus 0.15 × structural (1.0 within `structuralM` before the turn on the approach, 0.6
 * within it after, 0.3 farther), and the side it is on driving in.
 */
const landmarkFor = (
  at: { lat: number; lon: number },
  heading: number,
  candidates: Landmark[],
  o: CoverageOptions,
): { id: string; side: "left" | "right" } | null => {
  const h = (heading * Math.PI) / 180;
  const [hx, hy] = [Math.sin(h), Math.cos(h)];
  let best: { id: string; side: "left" | "right"; score: number } | null = null;
  for (const l of candidates) {
    const d = distanceBetween(at, l);
    // Local metres east (x) and north (y) of the junction.
    const y = (l.lat - at.lat) * 111_320;
    const x = (l.lon - at.lon) * 111_320 * Math.cos((at.lat * Math.PI) / 180);
    const ahead = x * hx + y * hy;
    const structural = d <= o.structuralM ? (ahead < 0 ? 1 : 0.6) : 0.3;
    const score = l.base + 0.15 * structural;
    if (!best || score > best.score || (score === best.score && l.id < best.id)) {
      best = { id: l.id, side: hx * y - hy * x > 0 ? "left" : "right", score };
    }
  }
  return best && { id: best.id, side: best.side };
};

/**
 * Chooses the junction items by route coverage (SPEC §6.6) into `pipeline.junction_item`: drives
 * `pairs` origin–destination pairs drawn by street length on the directed, restricted graph,
 * counts every decision (a turn with another legal way on), and keeps the most driven until they
 * cover `share` of all decisions driven. Returns the coverage report (Markdown).
 */
export const selectJunctionItems = async (
  sql: Sql,
  o: CoverageOptions = COVERAGE,
): Promise<string> => {
  const junctionRows = await sql`
    SELECT j.id::float8 AS id, ST_Y(p.geom) AS lat, ST_X(p.geom) AS lon
    FROM pipeline.junction j JOIN pipeline.junction_point p USING (id)`;
  const junctions = new Map(
    junctionRows.map((j) => [j.id as number, { lat: j.lat as number, lon: j.lon as number }]),
  );
  const edgeRows = await sql`
    SELECT e.id::float8 AS id, e.from_junction::float8 AS from, e.to_junction::float8 AS to,
           e.street_key::float8 AS street, e.oneway, e.length_m, b.bridge_id, l.tier, l.chunk_id,
           degrees(ST_Azimuth(ST_PointN(e.geom, 1)::geography, ST_PointN(e.geom, 2)::geography)) AS out_bearing,
           degrees(ST_Azimuth(ST_PointN(e.geom, -2)::geography, ST_PointN(e.geom, -1)::geography)) AS in_bearing
    FROM pipeline.road_edge e
    LEFT JOIN pipeline.edge_bridge b ON b.edge_id = e.id
    LEFT JOIN pipeline.street_learning l ON l.key = e.street_key
    ORDER BY e.id`;
  const edges: Edge[] = edgeRows.map((e) => ({
    id: e.id as number,
    from: e.from as number,
    to: e.to as number,
    streetId: e.street === null ? null : String(e.street),
    lengthM: e.length_m as number,
    oneway: onewayOf(e.oneway as number),
    tier: (e.tier as Tier | null) ?? null,
    chunk: (e.chunk_id as string | null) ?? null,
    bridge: (e.bridge_id as string | null) ?? null,
    outBearing: (e.out_bearing as number | null) ?? 0,
    inBearing: (e.in_bearing as number | null) ?? 0,
  }));
  const byId = new Map(edges.map((e) => [e.id, e]));
  const restrictions = (
    await sql`
      SELECT from_edge::float8 AS from_edge, via_junction::float8 AS via, to_edge::float8 AS to_edge,
             is_only FROM pipeline.turn_restriction`
  ).map((r) => ({
    fromEdge: r.from_edge as number,
    via: r.via as number,
    toEdge: r.to_edge as number,
    only: r.is_only as boolean,
  }));
  const graph = new RoadGraph(junctions, edges, restrictions);

  const next = random(o.seed);
  const pick = byLength(edges, next);
  const decisions = new Map<string, Decision>();
  let routed = 0;
  let driven = 0;
  for (let attempt = 0; routed < o.pairs && attempt < o.pairs * 3; attempt++) {
    const from = pick().from;
    const toEdge = pick();
    if (from === toEdge.from) continue;
    const route = graph.shortestRoute(from, new Set([toEdge.from]));
    if (!route) continue;
    routed++;
    const destination = toEdge.chunk ?? "";
    for (let i = 0; i + 1 < route.edges.length; i++) {
      const approach = byId.get(route.edges[i] as number) as Edge;
      const exit = byId.get(route.edges[i + 1] as number) as Edge;
      const junction = route.junctions[i + 1] as number;
      const ways = graph.legalExits(junction, approach).filter((e) => e.id !== approach.id);
      if (ways.length < 2) continue;
      driven++;
      const key = `${junction}:${approach.id}:${exit.id}`;
      const d = decisions.get(key) ?? {
        junction,
        approach,
        exit,
        count: 0,
        destinations: new Map<string, number>(),
      };
      d.count++;
      if (destination) d.destinations.set(destination, (d.destinations.get(destination) ?? 0) + 1);
      decisions.set(key, d);
    }
  }

  const ranked = [...decisions.values()].sort(
    (a, b) =>
      b.count - a.count ||
      a.junction - b.junction ||
      a.approach.id - b.approach.id ||
      a.exit.id - b.exit.id,
  );
  const chosen: Decision[] = [];
  let covered = 0;
  for (const d of ranked) {
    if (covered >= o.share * driven) break;
    chosen.push(d);
    covered += d.count;
  }

  const landmarkRows = await sql`
    SELECT l.id, j.id::float8 AS junction, l.base, ST_Y(l.geom) AS lat, ST_X(l.geom) AS lon
    FROM pipeline.landmark l
    JOIN pipeline.junction_point j
      ON ST_DWithin(l.geom::geography, j.geom::geography, ${o.landmarkM})
    WHERE j.id = ANY(${[...new Set(chosen.map((d) => d.junction))]}::bigint[])`;
  const near = new Map<number, Landmark[]>();
  for (const l of landmarkRows as unknown as Landmark[]) {
    near.set(l.junction, [...(near.get(l.junction) ?? []), l]);
  }

  const rows = chosen.map((d, i) => {
    const bridge = bridgeAhead(graph, d.exit, d.junction);
    const { layer, chunk } = layerOf(d, bridge);
    const heading =
      d.approach.to === d.junction ? d.approach.inBearing : (d.approach.outBearing + 180) % 360;
    const landmark = landmarkFor(
      junctions.get(d.junction) as { lat: number; lon: number },
      heading,
      near.get(d.junction) ?? [],
      o,
    );
    return {
      junction_id: d.junction,
      approach_edge: d.approach.id,
      exit_edge: d.exit.id,
      layer,
      rank: i + 1,
      chunk_id: chunk,
      dest_chunk_id: mostCommon(d.destinations),
      landmark_id: landmark?.id ?? null,
      landmark_side: landmark?.side ?? null,
      bridge_id: bridge,
    };
  });
  await sql`DELETE FROM pipeline.junction_item`;
  for (let i = 0; i < rows.length; i += 1000) {
    await sql`INSERT INTO pipeline.junction_item ${sql(rows.slice(i, i + 1000))}`;
  }

  const layers = new Map<string, number>();
  for (const r of rows) layers.set(r.layer, (layers.get(r.layer) ?? 0) + 1);
  const pct = (part: number, whole: number): string =>
    whole ? `${((part / whole) * 100).toFixed(1)} %` : "–";
  return [
    "| Measure | Count | Share |",
    "| --- | --- | --- |",
    `| Origin–destination pairs routed | ${routed} | ${pct(routed, o.pairs)} of ${o.pairs} |`,
    `| Decisions driven | ${driven} | |`,
    `| Distinct decisions | ${decisions.size} | |`,
    `| Junction items chosen | ${rows.length} | covers ${pct(covered, driven)} |`,
    ...[...layers.entries()].sort().map(([l, n]) => `| … ${l} | ${n} | ${pct(n, rows.length)} |`),
    `| Items with a landmark | ${rows.filter((r) => r.landmark_id).length} | ${pct(rows.filter((r) => r.landmark_id).length, rows.length)} |`,
    "",
  ].join("\n");
};
