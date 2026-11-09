import { createHash } from "node:crypto";
import { readFileSync, rmSync, writeFileSync } from "node:fs";
import { basename } from "node:path";
import { gzipSync } from "node:zlib";
import { encodePolyline6 } from "@pindoro/geo";
import Database from "better-sqlite3";
import type { Sql } from "postgres";
import type { CityConfig } from "./config.ts";
import { isoSeconds } from "./io.ts";

export const PACK_FORMAT_VERSION = 3;

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

CREATE TABLE junction (
  id  INTEGER PRIMARY KEY,
  lat REAL NOT NULL,
  lon REAL NOT NULL
);

CREATE TABLE road_edge (
  id            INTEGER PRIMARY KEY,
  from_junction INTEGER NOT NULL REFERENCES junction (id),
  to_junction   INTEGER NOT NULL REFERENCES junction (id),
  street_id     TEXT NOT NULL REFERENCES street (id),
  length_m      REAL NOT NULL,
  geometry      TEXT NOT NULL
);
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

export interface Bbox {
  min_lat: number;
  min_lon: number;
  max_lat: number;
  max_lon: number;
}

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
  bbox: Bbox;
}

type Position = [lon: number, lat: number];

const ring6 = (ring: Position[]): string =>
  encodePolyline6(ring.map(([lon, lat]) => ({ lat, lon })));

const line6 = (geojson: string): string => {
  const g = JSON.parse(geojson) as { type: string; coordinates: Position[] };
  if (g.type !== "LineString") throw new Error(`expected LineString, got ${g.type}`);
  return ring6(g.coordinates);
};

const multiline6 = (geojson: string): string => {
  const g = JSON.parse(geojson) as { type: string; coordinates: Position[][] };
  if (g.type !== "MultiLineString") throw new Error(`expected MultiLineString, got ${g.type}`);
  return JSON.stringify(g.coordinates.map(ring6));
};

const multipolygon6 = (geojson: string): string => {
  const g = JSON.parse(geojson) as { type: string; coordinates: Position[][][] };
  if (g.type !== "MultiPolygon") throw new Error(`expected MultiPolygon, got ${g.type}`);
  return JSON.stringify(g.coordinates.map((polygon) => polygon.map(ring6)));
};

/** UTC build time as YYYYMMDDTHHMMSSZ (lexically sortable). */
export const packVersion = (at: Date): string => isoSeconds(at).replace(/[-:]/g, "");

export interface PackOptions {
  city: CityConfig;
  ids: Map<number, string>;
  version: string;
  osmTimestamp: string;
  generatedAt: string;
  /** Restrict to one district, the smaller areas inside it and its streets (fixture packs). */
  districtId?: string;
}

/** The district $1 and the quarters and neighbourhoods whose centre lies in it. */
const FIXTURE_AREAS = `
  SELECT d.id FROM pipeline.district d JOIN pipeline.pack_area a USING (id)
  WHERE d.id = $1
     OR (d.kind <> 'district'
         AND ST_Contains((SELECT geom FROM pipeline.pack_area WHERE id = $1), a.center))`;

const AREA_COLUMNS = `
  a.area_m2, ST_Y(a.center) AS center_lat, ST_X(a.center) AS center_lon,
  ST_YMin(a.geom) AS min_lat, ST_XMin(a.geom) AS min_lon, ST_YMax(a.geom) AS max_lat, ST_XMax(a.geom) AS max_lon,
  ST_AsGeoJSON(a.geom, 7) AS geojson`;

/** Writes a pack per docs/pack-format.md from the `pipeline` schema; returns the city's bbox. */
export const writePack = async (sql: Sql, file: string, o: PackOptions): Promise<Bbox> => {
  const only = o.districtId ?? null;
  const [city] = await sql.unsafe(
    `SELECT ${AREA_COLUMNS} FROM pipeline.pack_area a WHERE a.id = 'city'`,
  );
  const districts = await sql.unsafe(
    `SELECT d.id, d.kind, d.osm_relation_id::float8 AS osm_relation_id, d.name_ka, d.name_en, ${AREA_COLUMNS}
     FROM pipeline.district d JOIN pipeline.pack_area a USING (id)
     WHERE $1::text IS NULL OR d.id IN (${FIXTURE_AREAS}) ORDER BY d.id`,
    [only],
  );
  const links = await sql.unsafe(
    `SELECT street_key::float8 AS street_key, district_id, length_m, share FROM pipeline.street_district
     WHERE $1::text IS NULL
        OR (district_id IN (${FIXTURE_AREAS})
            AND street_key IN (SELECT street_key FROM pipeline.street_district WHERE district_id = $1))
     ORDER BY street_key, district_id`,
    [only],
  );
  const streets = await sql`
    SELECT s.key::float8 AS key, s.name_ka, s.name_en, s.road_class, s.difficulty, s.length_m,
           ST_Y(p.mid) AS mid_lat, ST_X(p.mid) AS mid_lon,
           ST_YMin(p.geom) AS min_lat, ST_XMin(p.geom) AS min_lon, ST_YMax(p.geom) AS max_lat, ST_XMax(p.geom) AS max_lon,
           ST_AsGeoJSON(p.geom, 7) AS geojson
    FROM pipeline.street s JOIN pipeline.pack_street p USING (key)
    WHERE ${only}::text IS NULL
       OR s.key IN (SELECT street_key FROM pipeline.street_district WHERE district_id = ${only})
    ORDER BY s.key`;
  const edges = await sql`
    SELECT e.id::float8 AS id, e.from_junction::float8 AS from_junction,
           e.to_junction::float8 AS to_junction, e.street_key::float8 AS street_key, e.length_m,
           ST_AsGeoJSON(e.geom, 7) AS geojson
    FROM pipeline.road_edge e
    WHERE ${only}::text IS NULL
       OR e.street_key IN (SELECT street_key FROM pipeline.street_district WHERE district_id = ${only})
    ORDER BY e.id`;
  const junctions = await sql`
    SELECT j.id::float8 AS id, ST_Y(j.geom) AS lat, ST_X(j.geom) AS lon
    FROM pipeline.junction_point j
    WHERE j.id IN (SELECT from_junction FROM pipeline.road_edge
                   UNION SELECT to_junction FROM pipeline.road_edge)
    ORDER BY j.id`;
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

    // A fixture keeps only the junctions its edges use.
    const used = new Set(
      edges.flatMap((e) => [e.from_junction as number, e.to_junction as number]),
    );
    const junction = db.prepare("INSERT INTO junction VALUES (@id, @lat, @lon)");
    for (const j of junctions) if (used.has(j.id)) junction.run(j);
    const edge = db.prepare(
      `INSERT INTO road_edge VALUES (@id, @from_junction, @to_junction, @street_id, @length_m,
        @geometry)`,
    );
    for (const { street_key, geojson, ...e } of edges) {
      edge.run({ ...e, street_id: streetId(street_key), geometry: line6(geojson) });
    }
  })();
  db.exec("VACUUM");
  db.close();
  const { min_lat, min_lon, max_lat, max_lon } = cityArea;
  return { min_lat, min_lon, max_lat, max_lon };
};

/** Gzips a pack next to itself and writes manifest.json describing the .gz file. */
export const finalisePack = (
  sqliteFile: string,
  manifestFile: string,
  m: Omit<Manifest, "format_version" | "file" | "sha256" | "size">,
): Manifest => {
  const gz = `${sqliteFile}.gz`;
  const bytes = gzipSync(readFileSync(sqliteFile), { level: 9 });
  writeFileSync(gz, bytes);
  const manifest: Manifest = {
    format_version: PACK_FORMAT_VERSION,
    ...m,
    file: basename(gz),
    sha256: createHash("sha256").update(bytes).digest("hex"),
    size: bytes.length,
  };
  writeFileSync(manifestFile, `${JSON.stringify(manifest, null, 2)}\n`);
  return manifest;
};
