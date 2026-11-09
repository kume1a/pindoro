import { spawnSync } from "node:child_process";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { decodePolyline6 } from "@pindoro/geo";
import Database from "better-sqlite3";
import postgres, { type Sql } from "postgres";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { CityConfig } from "../src/config.ts";
import { extractCity, loadOsm, runSqlSteps, type StepParams } from "../src/load.ts";
import { writePack } from "../src/pack.ts";

const DB =
  process.env.TEST_DATABASE_URL ??
  "postgres://pindoro:pindoro@localhost:5433/pindoro_pipeline_test";
const SYNTHETIC = join(import.meta.dirname, "fixtures/synthetic.osm");

const onPath = (cmd: string): boolean => spawnSync(cmd, ["--version"]).status === 0;
const toolsReady = onPath("osm2pgsql") && onPath("osmium");
if (!toolsReady) {
  if (process.env.PINDORO_REQUIRE_OSM_TOOLS === "1") {
    throw new Error("PINDORO_REQUIRE_OSM_TOOLS=1 but osm2pgsql/osmium are not on PATH");
  }
  console.warn(
    "SKIP SQL step tests: osm2pgsql/osmium not on PATH (run them in the pipeline image)",
  );
}

const params: StepParams = {
  cityRelationId: 1000,
  utmSrid: 32638,
  expectRelations: [1001, 1002],
  neighbourhoods: [],
  minAreaStreets: 1,
};

describe.skipIf(!toolsReady)("SQL steps on synthetic OSM", () => {
  let sql: Sql;

  beforeAll(async () => {
    sql = postgres(DB, { onnotice: () => {} });
    const pbf = extractCity(SYNTHETIC, 1000, mkdtempSync(join(tmpdir(), "pindoro-synth-")));
    await loadOsm(sql, pbf, DB);
    await runSqlSteps(sql, params);
  }, 120_000);

  afterAll(async () => {
    await sql?.end();
  });

  const streets = async (
    name: string,
  ): Promise<
    {
      key: number;
      name_ka: string;
      name_en: string | null;
      difficulty: string;
      way_ids: number[];
      parts: number;
    }[]
  > =>
    (await sql`
      SELECT key::float8 AS key, name_ka, name_en, difficulty, way_ids::float8[] AS way_ids,
             ST_NumGeometries(geom) AS parts
      FROM pipeline.street WHERE norm_name = pipeline.normalise_name(${name}) ORDER BY key`) as never;

  /** Exports the synthetic city's pack (a fixture pack with [districtId]) and opens it. */
  const exportPack = async (districtId?: string): Promise<Database.Database> => {
    const keys = (await sql`SELECT key::float8 AS key FROM pipeline.street`).map(
      (r) => r.key as number,
    );
    const file = join(mkdtempSync(join(tmpdir(), "pindoro-pack-")), "synth.sqlite");
    await writePack(sql, file, {
      city: {
        id: "synth",
        name_ka: "სინთი",
        name_en: "Synth",
        osm_relation_id: 1000,
      } as CityConfig,
      ids: new Map(keys.map((k) => [k, crypto.randomUUID()])),
      version: "20261105T000000Z",
      osmTimestamp: "",
      generatedAt: "2026-11-05T00:00:00Z",
      districtId,
    });
    return new Database(file, { readonly: true });
  };

  const districtsOf = async (name: string): Promise<string[]> =>
    (
      await sql`
        SELECT sd.district_id FROM pipeline.street_district sd
        JOIN pipeline.street s ON s.key = sd.street_key
        WHERE s.norm_name = pipeline.normalise_name(${name}) ORDER BY 1`
    ).map((r) => r.district_id as string);

  it("merges a split way into one street (names normalised)", async () => {
    const rows = await streets("Split Street");
    expect(rows).toHaveLength(1);
    expect(rows[0]?.way_ids).toEqual([2001, 2002]);
    expect(rows[0]?.parts).toBe(1);
  });

  it("keeps same-name streets far apart as separate streets", async () => {
    const rows = await streets("Twin Street");
    expect(rows.map((r) => r.way_ids)).toEqual([[2003], [2004]]);
  });

  it("drops unnamed, service, footway, private and link roads", async () => {
    const ways = (
      await sql`SELECT unnest(way_ids)::float8 AS id FROM pipeline.street ORDER BY 1`
    ).map((r) => r.id);
    expect(ways).toEqual([2001, 2002, 2003, 2004, 2006, 2008, 2012, 2013, 2014]);
  });

  it("assigns a road crossing two districts to both", async () => {
    expect(await districtsOf("ჯვრის გამზირი")).toEqual(["osm:r1001", "osm:r1002"]);
  });

  it("ignores a short (< 150 m, < 30 %) stretch inside a district", async () => {
    expect(await districtsOf("Edge Lane")).toEqual(["osm:r1001"]);
  });

  it("takes districts from subarea members only, whatever their admin_level", async () => {
    const ids = (
      await sql`SELECT id FROM pipeline.district WHERE kind = 'district' ORDER BY id`
    ).map((r) => r.id);
    expect(ids).toEqual(["osm:r1001", "osm:r1002"]);
  });

  it("prefers name:ka and derives difficulty from the road class", async () => {
    const [cross] = await streets("ჯვრის გამზირი");
    expect(cross).toMatchObject({
      name_ka: "ჯვრის გამზირი",
      name_en: "Cross Avenue",
      difficulty: "easy",
    });
    expect((await streets("Edge Lane"))[0]?.difficulty).toBe("hard");
    expect((await streets("Split Street"))[0]?.difficulty).toBe("expert");
  });

  it("exports a pack with decodable polyline6 geometry", async () => {
    const db = await exportPack();
    expect(db.prepare("SELECT count(*) FROM street").pluck().get()).toBe(8);
    expect(db.prepare("SELECT count(*) FROM district").pluck().get()).toBe(4);
    const split = db
      .prepare("SELECT geometry FROM street WHERE name_ka = 'Split Street'")
      .pluck()
      .get();
    const parts = (JSON.parse(split as string) as string[]).map(decodePolyline6);
    expect(parts).toHaveLength(1);
    expect(parts[0]?.at(0)).toEqual({ lat: 41.71, lon: 44.71 });
    expect(parts[0]?.at(-1)).toEqual({ lat: 41.71, lon: 44.73 });
    db.close();
  });

  it("adds OSM quarters and neighbourhoods: the smallest per name, none without streets", async () => {
    const rows = await sql`
      SELECT id, kind, osm_relation_id::float8 AS relation, name_ka, name_en FROM pipeline.district
      WHERE kind <> 'district' ORDER BY id`;
    expect(rows).toEqual([
      { id: "osm:r1004", kind: "quarter", relation: 1004, name_ka: "შუა", name_en: "Middle" },
      { id: "osm:w114", kind: "neighbourhood", relation: null, name_ka: "ტყუპი", name_en: null },
    ]);
    expect(await districtsOf("Twin Street")).toContain("osm:w114");
    expect(await districtsOf("Split Street")).toContain("osm:r1004");
  });

  it("a fixture pack keeps one district, the areas inside it and only its streets", async () => {
    const db = await exportPack("osm:r1001");
    expect(db.prepare("SELECT id FROM district ORDER BY id").pluck().all()).toEqual([
      "osm:r1001",
      "osm:r1004",
      "osm:w114",
    ]);
    const strays = db
      .prepare(
        "SELECT count(*) FROM street_district WHERE street_id NOT IN (SELECT id FROM street)",
      )
      .pluck()
      .get();
    expect(strays).toBe(0);
    db.close();
  });

  const edgesOf = async (name: string): Promise<{ from: number; to: number; length_m: number }[]> =>
    (await sql`
      SELECT e.from_junction::float8 AS from, e.to_junction::float8 AS to, e.length_m
      FROM pipeline.road_edge e JOIN pipeline.street s ON s.key = e.street_key
      WHERE s.norm_name = pipeline.normalise_name(${name}) ORDER BY e.id`) as never;

  it("joins streets at the nodes they share, not where they only cross", async () => {
    const north = await edgesOf("North Road");
    const ridge = await edgesOf("Ridge Road");
    expect(north).toHaveLength(2);
    expect(ridge).toHaveLength(2);
    const northEnds = new Set(north.flatMap((e) => [e.from, e.to]));
    const shared = new Set(ridge.flatMap((e) => [e.from, e.to]).filter((j) => northEnds.has(j)));
    expect(shared.size).toBe(1);
    expect(await edgesOf("Bridge Road")).toHaveLength(1);
    expect(await edgesOf("Split Street")).toHaveLength(2);
  });

  it("measures each edge along its way", async () => {
    const [street] = await sql`
      SELECT length_m FROM pipeline.street WHERE norm_name = pipeline.normalise_name('North Road')`;
    const total = (await edgesOf("North Road")).reduce((sum, e) => sum + e.length_m, 0);
    expect(total).toBeCloseTo(street?.length_m as number, 3);
  });

  it("exports the road graph: edges start and end at their junctions", async () => {
    const db = await exportPack();
    const junctions = new Map(
      (
        db.prepare("SELECT id, lat, lon FROM junction").all() as {
          id: number;
          lat: number;
          lon: number;
        }[]
      ).map((j) => [j.id, j]),
    );
    const edges = db.prepare("SELECT * FROM road_edge").all() as {
      from_junction: number;
      to_junction: number;
      street_id: string;
      geometry: string;
    }[];
    expect(edges).toHaveLength(11);
    for (const e of edges) {
      const line = decodePolyline6(e.geometry);
      const from = junctions.get(e.from_junction);
      const to = junctions.get(e.to_junction);
      expect(line[0]?.lat).toBeCloseTo(from?.lat as number, 5);
      expect(line[0]?.lon).toBeCloseTo(from?.lon as number, 5);
      expect(line.at(-1)?.lat).toBeCloseTo(to?.lat as number, 5);
      expect(line.at(-1)?.lon).toBeCloseTo(to?.lon as number, 5);
    }
    const strays = db
      .prepare("SELECT count(*) FROM road_edge WHERE street_id NOT IN (SELECT id FROM street)")
      .pluck()
      .get();
    expect(strays).toBe(0);
    db.close();
  });

  it("a fixture pack keeps only its streets' edges and their junctions", async () => {
    const db = await exportPack("osm:r1002");
    const edgeStreets = db
      .prepare(
        "SELECT DISTINCT s.name_ka FROM road_edge e JOIN street s ON s.id = e.street_id ORDER BY 1",
      )
      .pluck()
      .all();
    expect(edgeStreets).toEqual(["Bridge Road", "North Road", "Ridge Road", "ჯვრის გამზირი"]);
    const unused = db
      .prepare(
        `SELECT count(*) FROM junction j WHERE NOT EXISTS
           (SELECT 1 FROM road_edge e WHERE j.id IN (e.from_junction, e.to_junction))`,
      )
      .pluck()
      .get();
    expect(unused).toBe(0);
    db.close();
  });

  it("adds curated neighbourhoods from GeoJSON", async () => {
    const square = (lat: number, lon: number, d: number): number[][][] => [
      [
        [lon, lat],
        [lon + d, lat],
        [lon + d, lat + d],
        [lon, lat + d],
        [lon, lat],
      ],
    ];
    await runSqlSteps(sql, {
      ...params,
      neighbourhoods: [
        {
          slug: "crossing",
          name_ka: "გადაკვეთა",
          geometry: { type: "Polygon", coordinates: square(41.725, 44.735, 0.03) },
        },
      ],
    });
    const [n] =
      await sql`SELECT kind, osm_relation_id FROM pipeline.district WHERE id = 'curated:crossing'`;
    expect(n).toEqual({ kind: "neighbourhood", osm_relation_id: null });
    expect(await districtsOf("ჯვრის გამზირი")).toContain("curated:crossing");
  });

  it("fails loudly when an expected district relation is missing", async () => {
    await expect(runSqlSteps(sql, { ...params, expectRelations: [1001, 9999] })).rejects.toThrow(
      /9999/,
    );
  });
});
