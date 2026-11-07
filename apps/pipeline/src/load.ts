import { execFileSync } from "node:child_process";
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { Sql } from "postgres";
import { MIN_AREA_STREETS, PIPELINE_DIR } from "./config.ts";

const LUA = join(PIPELINE_DIR, "osm2pgsql/pindoro.lua");
const SQL_DIR = join(PIPELINE_DIR, "sql");

export const run = (cmd: string, args: string[]): string =>
  execFileSync(cmd, args, { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] });

interface Feature {
  type: "Feature";
  properties: Record<string, unknown>;
  geometry: { type: string };
}

/** Cuts `input` to the city relation's polygon; boundary relations stay complete. Returns the new file. */
export const extractCity = (input: string, relationId: number, workDir: string): string => {
  mkdirSync(workDir, { recursive: true });
  const relation = join(workDir, "boundary.osm.pbf");
  const areas = join(workDir, "boundary-areas.geojson");
  const polygon = join(workDir, "boundary.geojson");
  const out = join(workDir, "city.osm.pbf");

  run("osmium", [
    "getid",
    "--add-referenced",
    "--overwrite",
    input,
    `r${relationId}`,
    "-o",
    relation,
  ]);
  // The relation file also holds the subarea relations, so pick the city's own area explicitly.
  run("osmium", [
    "export",
    "--overwrite",
    "--geometry-types=polygon",
    "--attributes=type,id",
    relation,
    "-o",
    areas,
  ]);
  const features = (JSON.parse(readFileSync(areas, "utf8")) as { features: Feature[] }).features;
  const city = features.find(
    (f) => f.properties["@type"] === "relation" && Number(f.properties["@id"]) === relationId,
  );
  if (!city) throw new Error(`relation ${relationId} has no valid polygon in ${input}`);
  writeFileSync(polygon, JSON.stringify(city));

  run("osmium", [
    "extract",
    "--overwrite",
    "--strategy=smart",
    "--option=types=multipolygon,boundary",
    `--polygon=${polygon}`,
    input,
    "-o",
    out,
  ]);
  return out;
};

export const loadOsm = async (sql: Sql, pbf: string, databaseUrl: string): Promise<void> => {
  await sql.unsafe(`
    CREATE EXTENSION IF NOT EXISTS postgis;
    DROP SCHEMA IF EXISTS osm CASCADE;
    CREATE SCHEMA osm;
  `);
  run("osm2pgsql", [
    "--create",
    "--output=flex",
    `--style=${LUA}`,
    `--database=${databaseUrl}`,
    "--log-level=warn",
    pbf,
  ]);
};

export interface Neighbourhood {
  slug: string;
  name_ka: string;
  name_en?: string;
  geometry: unknown;
}

export interface StepParams {
  cityRelationId: number;
  utmSrid: number;
  expectRelations: number[];
  neighbourhoods: Neighbourhood[];
  /** Neighbourhoods with fewer streets are dropped; defaults to MIN_AREA_STREETS. */
  minAreaStreets?: number;
}

/** Recreates schema `pipeline` and runs pipeline/sql/*.sql in file-name order. */
export const runSqlSteps = async (sql: Sql, p: StepParams): Promise<void> => {
  await sql.unsafe(`
    DROP SCHEMA IF EXISTS pipeline CASCADE;
    CREATE SCHEMA pipeline;
    CREATE TABLE pipeline.params (
      city_relation_id bigint NOT NULL,
      utm_srid int NOT NULL,
      expect_relations bigint[] NOT NULL,
      min_area_streets int NOT NULL
    );
    CREATE TABLE pipeline.neighbourhood_raw (
      slug text PRIMARY KEY,
      name_ka text NOT NULL,
      name_en text,
      geojson text NOT NULL
    );
  `);
  await sql`INSERT INTO pipeline.params VALUES (${p.cityRelationId}, ${p.utmSrid}, ${p.expectRelations},
    ${p.minAreaStreets ?? MIN_AREA_STREETS})`;
  for (const n of p.neighbourhoods) {
    await sql`INSERT INTO pipeline.neighbourhood_raw
      VALUES (${n.slug}, ${n.name_ka}, ${n.name_en ?? null}, ${JSON.stringify(n.geometry)})`;
  }
  for (const file of readdirSync(SQL_DIR)
    .filter((f) => f.endsWith(".sql"))
    .sort()) {
    console.log(`sql ${file}`);
    await sql.unsafe(readFileSync(join(SQL_DIR, file), "utf8"));
  }
};

export const readNeighbourhoods = (file: string): Neighbourhood[] => {
  const fc = JSON.parse(readFileSync(file, "utf8")) as {
    features: { properties?: Record<string, string>; geometry: unknown }[];
  };
  return fc.features.map((f, i) => {
    const { slug, name_ka, name_en } = f.properties ?? {};
    if (!slug || !name_ka)
      throw new Error(`${file}: feature ${i} needs properties slug and name_ka`);
    return { slug, name_ka, name_en, geometry: f.geometry };
  });
};
