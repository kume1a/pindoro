import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { basename } from "node:path";
import { gzipSync } from "node:zlib";
import { encodePolyline6 } from "@pindoro/geo";
import Database from "better-sqlite3";
import type { Sql } from "postgres";
import type { CityConfig } from "./config.ts";
import { isoSeconds, replaceAtomically, writeJson } from "./io.ts";

export const PACK_FORMAT_VERSION = 5;

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
  boundary        TEXT NOT NULL,
  parent_id       TEXT REFERENCES district (id)
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
  geometry    TEXT NOT NULL,
  tier        TEXT NOT NULL CHECK (tier IN ('A', 'B', 'C')),
  ring        INTEGER NOT NULL,
  bank        TEXT NOT NULL CHECK (bank IN ('L', 'R')),
  chunk_id    TEXT REFERENCES district (id),
  etymology   TEXT
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
  id      INTEGER PRIMARY KEY,
  node_id INTEGER NOT NULL,
  lat     REAL NOT NULL,
  lon     REAL NOT NULL
);

CREATE TABLE bridge (
  id       TEXT PRIMARY KEY,
  name_ka  TEXT NOT NULL,
  name_en  TEXT,
  mid_lat  REAL NOT NULL,
  mid_lon  REAL NOT NULL,
  geometry TEXT NOT NULL
);

CREATE TABLE road_edge (
  id            INTEGER PRIMARY KEY,
  from_junction INTEGER NOT NULL REFERENCES junction (id),
  to_junction   INTEGER NOT NULL REFERENCES junction (id),
  street_id     TEXT REFERENCES street (id),
  oneway        INTEGER NOT NULL CHECK (oneway IN (-1, 0, 1)),
  bridge_id     TEXT REFERENCES bridge (id),
  length_m      REAL NOT NULL,
  geometry      TEXT NOT NULL
);

CREATE TABLE turn_restriction (
  from_edge    INTEGER NOT NULL REFERENCES road_edge (id),
  via_junction INTEGER NOT NULL REFERENCES junction (id),
  to_edge      INTEGER NOT NULL REFERENCES road_edge (id),
  only         INTEGER NOT NULL CHECK (only IN (0, 1)),
  PRIMARY KEY (from_edge, via_junction, to_edge)
) WITHOUT ROWID;

CREATE TABLE landmark (
  id       TEXT PRIMARY KEY,
  kind     TEXT NOT NULL,
  name_ka  TEXT NOT NULL,
  name_en  TEXT,
  brand    TEXT,
  salience REAL NOT NULL,
  lat      REAL NOT NULL,
  lon      REAL NOT NULL
);

CREATE TABLE junction_item (
  junction_id   INTEGER NOT NULL REFERENCES junction (id),
  approach_edge INTEGER NOT NULL REFERENCES road_edge (id),
  exit_edge     INTEGER NOT NULL REFERENCES road_edge (id),
  layer         TEXT NOT NULL CHECK (layer IN ('skeleton', 'district', 'gateway_out', 'gateway_in', 'bridge')),
  rank          INTEGER NOT NULL,
  chunk_id      TEXT REFERENCES district (id),
  dest_chunk_id TEXT REFERENCES district (id),
  landmark_id   TEXT REFERENCES landmark (id),
  landmark_side TEXT CHECK (landmark_side IN ('left', 'right')),
  bridge_id     TEXT REFERENCES bridge (id),
  PRIMARY KEY (junction_id, approach_edge, exit_edge)
) WITHOUT ROWID;

CREATE TABLE family (
  parent_street_id TEXT NOT NULL REFERENCES street (id),
  child_street_id  TEXT PRIMARY KEY REFERENCES street (id),
  kind             TEXT NOT NULL CHECK (kind IN ('lane', 'dead_end', 'passage')),
  n                INTEGER NOT NULL,
  orphan           INTEGER NOT NULL CHECK (orphan IN (0, 1))
) WITHOUT ROWID;
CREATE INDEX family_parent ON family (parent_street_id);

CREATE TABLE chunk_neighbour (
  chunk_a TEXT NOT NULL REFERENCES district (id),
  chunk_b TEXT NOT NULL REFERENCES district (id),
  PRIMARY KEY (chunk_a, chunk_b)
) WITHOUT ROWID;
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

export const readManifest = (file: string): Manifest =>
  JSON.parse(readFileSync(file, "utf8")) as Manifest;

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
  /** Restricts the pack to one district (fixture packs). */
  fixture?: FixtureScope;
}

export interface FixtureScope {
  districtId: string;
  /**
   * Keys of the streets that kept a live id. Streets with a newly minted id stay out, so the
   * fixture never holds an id the server's packs don't know.
   */
  liveStreetKeys: number[];
}

/** The streets of the fixture district $1 that kept a live id ($2: their keys). */
const FIXTURE_STREETS = `
  SELECT street_key FROM pipeline.street_district
  WHERE district_id = $1 AND street_key = ANY($2::bigint[])`;

/**
 * The district $1, and the quarters and neighbourhoods whose centre lies in it that keep enough
 * fixture streets for a round.
 */
const FIXTURE_AREAS = `
  SELECT d.id FROM pipeline.district d JOIN pipeline.pack_area a USING (id)
  WHERE d.id = $1
     OR (d.kind <> 'district'
         AND ST_Contains((SELECT geom FROM pipeline.pack_area WHERE id = $1), a.center)
         AND (SELECT count(*) FROM pipeline.street_district sd
              WHERE sd.district_id = d.id AND sd.street_key IN (${FIXTURE_STREETS}))
             >= (SELECT min_area_streets FROM pipeline.params))`;

// A full pack ($1 null) takes every street and area.
const streetInPack = (key: string): string =>
  `($1::text IS NULL OR ${key} IN (${FIXTURE_STREETS}))`;
const areaInPack = (id: string): string => `($1::text IS NULL OR ${id} IN (${FIXTURE_AREAS}))`;

const AREA_COLUMNS = `
  a.area_m2, ST_Y(a.center) AS center_lat, ST_X(a.center) AS center_lon,
  ST_YMin(a.geom) AS min_lat, ST_XMin(a.geom) AS min_lon, ST_YMax(a.geom) AS max_lat, ST_XMax(a.geom) AS max_lon,
  ST_AsGeoJSON(a.geom, 7) AS geojson`;

/** Builds a SQLite file beside `file` and swaps it in only once complete. */
const buildSqlite = (file: string, fill: (db: Database.Database) => void): void =>
  replaceAtomically(file, (tmp) => {
    const db = new Database(tmp);
    try {
      fill(db);
    } finally {
      db.close();
    }
  });

/** Writes a pack per docs/pack-format.md from the `pipeline` schema; returns the city's bbox. */
export const writePack = async (sql: Sql, file: string, o: PackOptions): Promise<Bbox> => {
  const scope = [o.fixture?.districtId ?? null, o.fixture?.liveStreetKeys ?? null];
  const [city] = await sql.unsafe(
    `SELECT ${AREA_COLUMNS} FROM pipeline.pack_area a WHERE a.id = 'city'`,
  );
  const districts = await sql.unsafe(
    `SELECT d.id, d.kind, d.osm_relation_id::float8 AS osm_relation_id, d.name_ka, d.name_en, ${AREA_COLUMNS},
            CASE WHEN ${areaInPack("ap.parent_id")} THEN ap.parent_id END AS parent_id
     FROM pipeline.district d JOIN pipeline.pack_area a USING (id)
     LEFT JOIN pipeline.area_parent ap USING (id)
     WHERE ${areaInPack("d.id")}
     ORDER BY d.kind <> 'district', d.id -- raions first: smaller areas reference them`,
    scope,
  );
  const links = await sql.unsafe(
    `SELECT l.street_key::float8 AS street_key, l.district_id, l.length_m, l.share
     FROM pipeline.street_district l
     WHERE ${areaInPack("l.district_id")} AND ${streetInPack("l.street_key")}
     ORDER BY l.street_key, l.district_id`,
    scope,
  );
  const streets = await sql.unsafe(
    `SELECT s.key::float8 AS key, s.name_ka, s.name_en, s.road_class, s.difficulty, s.length_m,
            ST_Y(p.mid) AS mid_lat, ST_X(p.mid) AS mid_lon,
            ST_YMin(p.geom) AS min_lat, ST_XMin(p.geom) AS min_lon, ST_YMax(p.geom) AS max_lat, ST_XMax(p.geom) AS max_lon,
            ST_AsGeoJSON(p.geom, 7) AS geojson, l.tier, l.ring, l.bank, s.etymology,
            CASE WHEN ${areaInPack("l.chunk_id")} THEN l.chunk_id END AS chunk_id
     FROM pipeline.street s JOIN pipeline.pack_street p USING (key)
     JOIN pipeline.street_learning l USING (key)
     WHERE ${streetInPack("s.key")} ORDER BY s.key`,
    scope,
  );
  // A fixture keeps its streets' edges and the connectors between their junctions.
  const edgeIds = (
    await sql.unsafe(
      `WITH street_edge AS (
         SELECT e.* FROM pipeline.road_edge e
         WHERE e.street_key IS NOT NULL AND ${streetInPack("e.street_key")}
       ),
       kept_junction AS (
         SELECT unnest(ARRAY[from_junction, to_junction]) AS id FROM street_edge
       )
       SELECT id::float8 AS id FROM street_edge
       UNION
       SELECT e.id::float8 FROM pipeline.road_edge e
       WHERE e.street_key IS NULL
         AND ($1::text IS NULL OR (e.from_junction IN (SELECT id FROM kept_junction)
                                   AND e.to_junction IN (SELECT id FROM kept_junction)))`,
      scope,
    )
  ).map((r) => r.id as number);
  const edges = await sql.unsafe(
    `SELECT e.id::float8 AS id, e.from_junction::float8 AS from_junction,
            e.to_junction::float8 AS to_junction, e.street_key::float8 AS street_key, e.oneway,
            b.bridge_id, e.length_m, ST_AsGeoJSON(e.geom, 7) AS geojson
     FROM pipeline.road_edge e LEFT JOIN pipeline.edge_bridge b ON b.edge_id = e.id
     WHERE e.id = ANY($1::bigint[]) ORDER BY e.id`,
    [edgeIds],
  );
  const junctions = await sql.unsafe(
    `SELECT j.id::float8 AS id, jn.node_id::float8 AS node_id, ST_Y(j.geom) AS lat, ST_X(j.geom) AS lon
     FROM pipeline.junction_point j JOIN pipeline.junction jn USING (id)
     WHERE j.id IN (SELECT unnest(ARRAY[e.from_junction, e.to_junction]) FROM pipeline.road_edge e
                    WHERE e.id = ANY($1::bigint[]))
     ORDER BY j.id`,
    [edgeIds],
  );
  const restrictions = await sql.unsafe(
    `SELECT from_edge::float8 AS from_edge, via_junction::float8 AS via_junction,
            to_edge::float8 AS to_edge, is_only::int AS only
     FROM pipeline.turn_restriction
     WHERE from_edge = ANY($1::bigint[]) AND to_edge = ANY($1::bigint[]) ORDER BY 1, 2, 3`,
    [edgeIds],
  );
  const bridges = await sql.unsafe(
    `SELECT b.id, b.name_ka, b.name_en, ST_AsGeoJSON(b.geom, 7) AS geojson,
            ST_Y(ST_PointOnSurface(b.geom)) AS mid_lat, ST_X(ST_PointOnSurface(b.geom)) AS mid_lon
     FROM pipeline.bridge b
     WHERE b.id IN (SELECT bridge_id FROM pipeline.edge_bridge WHERE edge_id = ANY($1::bigint[]))
        OR b.id IN (SELECT bridge_id FROM pipeline.junction_item
                    WHERE approach_edge = ANY($1::bigint[]) AND exit_edge = ANY($1::bigint[]))
     ORDER BY b.id`,
    [edgeIds],
  );
  const items = await sql.unsafe(
    `SELECT i.junction_id::float8 AS junction_id, i.approach_edge::float8 AS approach_edge,
            i.exit_edge::float8 AS exit_edge, i.layer, i.rank,
            CASE WHEN ${areaInPack("i.chunk_id")} THEN i.chunk_id END AS chunk_id,
            CASE WHEN ${areaInPack("i.dest_chunk_id")} THEN i.dest_chunk_id END AS dest_chunk_id,
            i.landmark_id, i.landmark_side, i.bridge_id
     FROM pipeline.junction_item i
     WHERE i.approach_edge = ANY($3::bigint[]) AND i.exit_edge = ANY($3::bigint[])
     ORDER BY i.rank`,
    [...scope, edgeIds],
  );
  const landmarks = await sql.unsafe(
    `SELECT l.id, l.kind, l.name_ka, l.name_en, l.brand, l.base AS salience,
            ST_Y(l.geom) AS lat, ST_X(l.geom) AS lon
     FROM pipeline.landmark l WHERE l.id = ANY($1::text[]) ORDER BY l.id`,
    [[...new Set(items.map((i) => i.landmark_id).filter((id) => id !== null))]],
  );
  const families = await sql.unsafe(
    `SELECT f.parent_key::float8 AS parent_key, f.child_key::float8 AS child_key, f.kind, f.n,
            f.orphan::int AS orphan
     FROM pipeline.family f
     WHERE ${streetInPack("f.parent_key")} AND ${streetInPack("f.child_key")} ORDER BY f.child_key`,
    scope,
  );
  const neighbours = await sql.unsafe(
    `SELECT n.chunk_a, n.chunk_b FROM pipeline.chunk_neighbour n
     WHERE ${areaInPack("n.chunk_a")} AND ${areaInPack("n.chunk_b")} ORDER BY 1, 2`,
    scope,
  );
  if (!city) throw new Error("pipeline.pack_area has no city row; did the SQL steps run?");
  if (o.fixture && districts.length === 0) {
    throw new Error(`district ${o.fixture.districtId} not found`);
  }
  const { geojson: cityGeojson, ...cityArea } = city;

  const streetId = (key: number): string => {
    const id = o.ids.get(key);
    if (!id) throw new Error(`street ${key} has no stable id`);
    return id;
  };

  buildSqlite(file, (db) => {
    db.exec(PACK_DDL);
    db.pragma(`user_version = ${PACK_FORMAT_VERSION}`);
    db.transaction(() => {
      const meta = db.prepare("INSERT INTO meta VALUES (?, ?)");
      const values: Record<(typeof META_KEYS)[number], string> = {
        format_version: String(PACK_FORMAT_VERSION),
        city_id: o.city.id,
        version: o.version,
        scope: o.fixture ? "fixture" : "full",
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
          @center_lon, @min_lat, @min_lon, @max_lat, @max_lon, @area_m2, @boundary, @parent_id)`,
      );
      for (const { geojson, ...d } of districts)
        district.run({ ...d, boundary: multipolygon6(geojson) });

      const street = db.prepare(
        `INSERT INTO street VALUES (@id, @name_ka, @name_en, @road_class, @difficulty, @length_m,
          @mid_lat, @mid_lon, @min_lat, @min_lon, @max_lat, @max_lon, @geometry, @tier, @ring, @bank,
          @chunk_id, @etymology)`,
      );
      for (const { key, geojson, ...s } of streets) {
        street.run({ ...s, id: streetId(key), geometry: multiline6(geojson) });
      }

      const link = db.prepare("INSERT INTO street_district VALUES (?, ?, ?, ?)");
      for (const l of links) link.run(streetId(l.street_key), l.district_id, l.length_m, l.share);

      const junction = db.prepare("INSERT INTO junction VALUES (@id, @node_id, @lat, @lon)");
      for (const j of junctions) junction.run(j);
      const bridge = db.prepare(
        "INSERT INTO bridge VALUES (@id, @name_ka, @name_en, @mid_lat, @mid_lon, @geometry)",
      );
      for (const { geojson, ...b } of bridges) bridge.run({ ...b, geometry: multiline6(geojson) });
      const edge = db.prepare(
        `INSERT INTO road_edge VALUES (@id, @from_junction, @to_junction, @street_id, @oneway,
          @bridge_id, @length_m, @geometry)`,
      );
      for (const { street_key, geojson, ...e } of edges) {
        edge.run({
          ...e,
          street_id: street_key === null ? null : streetId(street_key),
          geometry: line6(geojson),
        });
      }
      const restriction = db.prepare("INSERT INTO turn_restriction VALUES (?, ?, ?, ?)");
      for (const r of restrictions) {
        restriction.run(r.from_edge, r.via_junction, r.to_edge, r.only);
      }
      const landmark = db.prepare(
        `INSERT INTO landmark VALUES (@id, @kind, @name_ka, @name_en, @brand, @salience, @lat,
          @lon)`,
      );
      for (const l of landmarks) landmark.run(l);
      const item = db.prepare(
        `INSERT INTO junction_item VALUES (@junction_id, @approach_edge, @exit_edge, @layer, @rank,
          @chunk_id, @dest_chunk_id, @landmark_id, @landmark_side, @bridge_id)`,
      );
      for (const i of items) item.run(i);

      const family = db.prepare("INSERT INTO family VALUES (?, ?, ?, ?, ?)");
      for (const f of families) {
        family.run(streetId(f.parent_key), streetId(f.child_key), f.kind, f.n, f.orphan);
      }
      const neighbour = db.prepare("INSERT INTO chunk_neighbour VALUES (?, ?)");
      for (const n of neighbours) neighbour.run(n.chunk_a, n.chunk_b);
    })();
    db.exec("VACUUM");
  });
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
  writeJson(manifestFile, manifest);
  return manifest;
};
