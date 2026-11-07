import { createHash } from "node:crypto";
import { readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { gzipSync } from "node:zlib";
import { encodePolyline6 } from "@pindoro/geo";
import Database from "better-sqlite3";
import type { Sql } from "postgres";
import type { CityConfig } from "./config.ts";

export const PACK_FORMAT_VERSION = 2;

// Mirrors docs/pack-format.md exactly; `validate` diffs packs against it.
export const PACK_DDL = `
CREATE TABLE meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE city (
  id              TEXT PRIMARY KEY,
  name_ka         TEXT NOT NULL,
  name_en         TEXT NOT NULL,
  osm_relation_id INTEGER NOT NULL,
  center_lat      REAL NOT NULL,
  center_lon      REAL NOT NULL,
  min_lat         REAL NOT NULL,
  min_lon         REAL NOT NULL,
  max_lat         REAL NOT NULL,
  max_lon         REAL NOT NULL,
  area_m2         REAL NOT NULL,
  boundary        TEXT NOT NULL
);

CREATE TABLE district (
  id              TEXT PRIMARY KEY,
  kind            TEXT NOT NULL CHECK (kind IN ('district', 'quarter', 'neighbourhood')),
  osm_relation_id INTEGER,
  name_ka         TEXT NOT NULL,
  name_en         TEXT,
  center_lat      REAL NOT NULL,
  center_lon      REAL NOT NULL,
  min_lat         REAL NOT NULL,
  min_lon         REAL NOT NULL,
  max_lat         REAL NOT NULL,
  max_lon         REAL NOT NULL,
  area_m2         REAL NOT NULL,
  boundary        TEXT NOT NULL
);

CREATE TABLE street (
  id          TEXT PRIMARY KEY,
  name_ka     TEXT NOT NULL,
  name_en     TEXT,
  road_class  TEXT NOT NULL,
  difficulty  TEXT NOT NULL CHECK (difficulty IN ('easy', 'medium', 'hard', 'expert')),
  length_m    REAL NOT NULL,
  mid_lat     REAL NOT NULL,
  mid_lon     REAL NOT NULL,
  min_lat     REAL NOT NULL,
  min_lon     REAL NOT NULL,
  max_lat     REAL NOT NULL,
  max_lon     REAL NOT NULL,
  geometry    TEXT NOT NULL
);
CREATE INDEX street_difficulty ON street (difficulty);

CREATE TABLE street_district (
  street_id   TEXT NOT NULL REFERENCES street (id),
  district_id TEXT NOT NULL REFERENCES district (id),
  length_m    REAL NOT NULL,
  share       REAL NOT NULL,
  PRIMARY KEY (street_id, district_id)
) WITHOUT ROWID;
CREATE INDEX street_district_district ON street_district (district_id);
`;

export const META_KEYS = [
  "format_version",
  "city_id",
  "version",
  "scope",
  "osm_timestamp",
  "generated_at",
  "attribution",
  "license",
] as const;

export interface Manifest {
  format_version: number;
  city: string;
  name_ka: string;
  name_en: string;
  version: string;
  file: string;
  sha256: string;
  size: number;
  osm_timestamp: string;
  generated_at: string;
  /** The city's bounding box, so clients can tell which city a position is in. */
  bbox: { min_lat: number; min_lon: number; max_lat: number; max_lon: number };
}

type Position = [lon: number, lat: number];

const ring6 = (ring: Position[]): string =>
  encodePolyline6(ring.map(([lon, lat]) => ({ lat, lon })));

export const multiline6 = (geojson: string): string => {
  const g = JSON.parse(geojson) as { type: string; coordinates: Position[][] };
  if (g.type !== "MultiLineString") throw new Error(`expected MultiLineString, got ${g.type}`);
  return JSON.stringify(g.coordinates.map(ring6));
};

export const multipolygon6 = (geojson: string): string => {
  const g = JSON.parse(geojson) as { type: string; coordinates: Position[][][] };
  if (g.type !== "MultiPolygon") throw new Error(`expected MultiPolygon, got ${g.type}`);
  return JSON.stringify(g.coordinates.map((polygon) => polygon.map(ring6)));
};

/** UTC build time as YYYYMMDDTHHMMSSZ (lexically sortable). */
export const packVersion = (at: Date): string =>
  at
    .toISOString()
    .replace(/[-:]/g, "")
    .replace(/\.\d+Z$/, "Z");

export interface PackOptions {
  city: CityConfig;
  ids: Map<number, string>;
  version: string;
  osmTimestamp: string;
  generatedAt: string;
  /** Restrict to one district and its streets (fixture packs). */
  districtId?: string;
}

const AREA_COLUMNS = `
  a.area_m2, ST_Y(a.center) AS center_lat, ST_X(a.center) AS center_lon,
  ST_YMin(a.geom) AS min_lat, ST_XMin(a.geom) AS min_lon, ST_YMax(a.geom) AS max_lat, ST_XMax(a.geom) AS max_lon,
  ST_AsGeoJSON(a.geom, 7) AS geojson`;

/** Writes a pack per docs/pack-format.md from the `pipeline` schema. */
export const writePack = async (sql: Sql, file: string, o: PackOptions): Promise<void> => {
  const only = o.districtId ?? null;
  const [city] = await sql.unsafe(
    `SELECT ${AREA_COLUMNS} FROM pipeline.pack_area a WHERE a.id = 'city'`,
  );
  const districts = await sql.unsafe(
    `SELECT d.id, d.kind, d.osm_relation_id::float8 AS osm_relation_id, d.name_ka, d.name_en, ${AREA_COLUMNS}
     FROM pipeline.district d JOIN pipeline.pack_area a USING (id)
     WHERE $1::text IS NULL OR d.id = $1 ORDER BY d.id`,
    [only],
  );
  const links = await sql`
    SELECT street_key::float8 AS street_key, district_id, length_m, share FROM pipeline.street_district
    WHERE ${only}::text IS NULL OR district_id = ${only} ORDER BY street_key, district_id`;
  const streets = await sql`
    SELECT s.key::float8 AS key, s.name_ka, s.name_en, s.road_class, s.difficulty, s.length_m,
           ST_Y(p.mid) AS mid_lat, ST_X(p.mid) AS mid_lon,
           ST_YMin(p.geom) AS min_lat, ST_XMin(p.geom) AS min_lon, ST_YMax(p.geom) AS max_lat, ST_XMax(p.geom) AS max_lon,
           ST_AsGeoJSON(p.geom, 7) AS geojson
    FROM pipeline.street s JOIN pipeline.pack_street p USING (key)
    WHERE ${only}::text IS NULL
       OR s.key IN (SELECT street_key FROM pipeline.street_district WHERE district_id = ${only})
    ORDER BY s.key`;
  if (!city) throw new Error("pipeline.pack_area has no city row; did the SQL steps run?");
  if (only && districts.length === 0) throw new Error(`district ${only} not found`);
  const { geojson: cityGeojson, ...cityArea } = city;

  const streetId = (key: number): string => {
    const id = o.ids.get(key);
    if (!id) throw new Error(`street ${key} has no stable id`);
    return id;
  };

  rmSync(file, { force: true });
  const db = new Database(file);
  db.exec(PACK_DDL);
  db.pragma(`user_version = ${PACK_FORMAT_VERSION}`);
  db.transaction(() => {
    const meta = db.prepare("INSERT INTO meta VALUES (?, ?)");
    const values: Record<(typeof META_KEYS)[number], string> = {
      format_version: String(PACK_FORMAT_VERSION),
      city_id: o.city.id,
      version: o.version,
      scope: only ? "fixture" : "full",
      osm_timestamp: o.osmTimestamp,
      generated_at: o.generatedAt,
      attribution: "© OpenStreetMap contributors",
      license: "ODbL-1.0",
    };
    for (const key of META_KEYS) meta.run(key, values[key]);

    db.prepare(
      `INSERT INTO city VALUES (@id, @name_ka, @name_en, @osm_relation_id, @center_lat, @center_lon,
        @min_lat, @min_lon, @max_lat, @max_lon, @area_m2, @boundary)`,
    ).run({
      ...cityArea,
      id: o.city.id,
      name_ka: o.city.name_ka,
      name_en: o.city.name_en,
      osm_relation_id: o.city.osm_relation_id,
      boundary: multipolygon6(cityGeojson),
    });

    const district = db.prepare(
      `INSERT INTO district VALUES (@id, @kind, @osm_relation_id, @name_ka, @name_en, @center_lat,
        @center_lon, @min_lat, @min_lon, @max_lat, @max_lon, @area_m2, @boundary)`,
    );
    for (const { geojson, ...d } of districts)
      district.run({ ...d, boundary: multipolygon6(geojson) });

    const street = db.prepare(
      `INSERT INTO street VALUES (@id, @name_ka, @name_en, @road_class, @difficulty, @length_m,
        @mid_lat, @mid_lon, @min_lat, @min_lon, @max_lat, @max_lon, @geometry)`,
    );
    for (const { key, geojson, ...s } of streets) {
      street.run({ ...s, id: streetId(key), geometry: multiline6(geojson) });
    }

    const link = db.prepare("INSERT INTO street_district VALUES (?, ?, ?, ?)");
    for (const l of links) link.run(streetId(l.street_key), l.district_id, l.length_m, l.share);
  })();
  db.exec("VACUUM");
  db.close();
};

/** Gzips a pack next to itself and writes manifest.json describing the .gz file. */
export const finalisePack = (
  sqliteFile: string,
  manifestFile: string,
  m: Omit<Manifest, "file" | "sha256" | "size">,
): Manifest => {
  const gz = `${sqliteFile}.gz`;
  const bytes = gzipSync(readFileSync(sqliteFile), { level: 9 });
  writeFileSync(gz, bytes);
  const manifest: Manifest = {
    ...m,
    file: gz.split(/[\\/]/).pop() as string,
    sha256: createHash("sha256").update(bytes).digest("hex"),
    size: statSync(gz).size,
  };
  writeFileSync(manifestFile, `${JSON.stringify(manifest, null, 2)}\n`);
  return manifest;
};
