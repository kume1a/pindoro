import { readFileSync } from "node:fs";
import { gunzipSync } from "node:zlib";
import { decodePolyline6, type LatLng } from "@pindoro/geo";
import Database from "better-sqlite3";
import { loadCity, MIN_AREA_STREETS } from "./config.ts";
import { type Bbox, META_KEYS, PACK_DDL, PACK_FORMAT_VERSION } from "./pack.ts";

const MIN_EXPERT_STREETS = 30;
/** Road trips are picked in the largest connected part; most of the graph must be in it. */
const MIN_CONNECTED_SHARE = 0.9;
const TABLES = ["meta", "city", "district", "street", "street_district", "junction", "road_edge"];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

interface Check {
  check: string;
  ok: boolean;
  detail: string;
}

type Pack = Database.Database;
type CityRow = Bbox & { boundary: string };
interface DistrictCount {
  id: string;
  kind: string;
  name: string;
  streets: number;
  expert: number;
}

const check = (name: string, ok: boolean, detail = ""): Check => ({ check: name, ok, detail });

/** A .gz pack is unpacked in memory; nothing is left in the temp dir. */
const openPack = (file: string): Pack =>
  file.endsWith(".gz")
    ? new Database(gunzipSync(readFileSync(file)), { readonly: true })
    : new Database(file, { readonly: true, fileMustExist: true });

const columns = (db: Pack, table: string): string =>
  JSON.stringify(
    db.prepare('SELECT name, type, "notnull", pk FROM pragma_table_info(?)').all(table),
  );

const decodeAll = (json: string): LatLng[][] =>
  (JSON.parse(json) as string[]).map((line) => decodePolyline6(line));

const inside = (p: LatLng, b: Bbox, margin = 1e-6): boolean =>
  Number.isFinite(p.lat) &&
  Number.isFinite(p.lon) &&
  p.lat >= b.min_lat - margin &&
  p.lat <= b.max_lat + margin &&
  p.lon >= b.min_lon - margin &&
  p.lon <= b.max_lon + margin;

const isClosedRing = (r: LatLng[]): boolean =>
  r.length >= 4 && r[0]?.lat === r.at(-1)?.lat && r[0]?.lon === r.at(-1)?.lon;

/** Every table matches docs/pack-format.md, and the pack carries this format's version. */
const schemaChecks = (db: Pack): Check[] => {
  const ref = new Database(":memory:");
  try {
    ref.exec(PACK_DDL);
    return [
      ...TABLES.map((t) => check(`schema ${t}`, columns(db, t) === columns(ref, t))),
      check("user_version", db.pragma("user_version", { simple: true }) === PACK_FORMAT_VERSION),
    ];
  } finally {
    ref.close();
  }
};

const relationsCheck = (db: Pack, meta: Record<string, string>): Check => {
  const city = loadCity(meta.city_id ?? "");
  const expected =
    meta.scope === "fixture" ? [city.fixture.district_relation_id] : city.expect_relations;
  const present = new Set(
    db
      .prepare("SELECT osm_relation_id FROM district WHERE osm_relation_id IS NOT NULL")
      .pluck()
      .all(),
  );
  const missing = expected.filter((id) => !present.has(id));
  return check("expected relations", missing.length === 0, missing.join(", "));
};

const districtCounts = (db: Pack): DistrictCount[] =>
  db
    .prepare(
      `SELECT d.id, d.kind, d.name_ka AS name, count(s.id) AS streets,
              coalesce(sum(s.difficulty = 'expert'), 0) AS expert
       FROM district d
       LEFT JOIN street_district sd ON sd.district_id = d.id
       LEFT JOIN street s ON s.id = sd.street_id
       GROUP BY d.id ORDER BY d.id`,
    )
    .all() as DistrictCount[];

const districtCheck = (districts: DistrictCount[]): Check => {
  const thin = districts.filter((d) =>
    d.kind === "district" ? d.expert < MIN_EXPERT_STREETS : d.streets < MIN_AREA_STREETS,
  );
  return check(
    `>= ${MIN_EXPERT_STREETS} expert streets per district, ${MIN_AREA_STREETS} per smaller area`,
    districts.length > 0 && thin.length === 0,
    thin.map((d) => d.id).join(", "),
  );
};

const streetCheck = (db: Pack, cityRow: CityRow | undefined): Check => {
  const bad: string[] = [];
  for (const s of db.prepare("SELECT * FROM street").iterate() as Iterable<
    Bbox & { id: string; geometry: string; mid_lat: number; mid_lon: number; length_m: number }
  >) {
    try {
      const parts = decodeAll(s.geometry);
      const ok =
        UUID.test(s.id) &&
        s.length_m > 0 &&
        parts.length > 0 &&
        parts.every((p) => p.length >= 2 && p.every((pt) => inside(pt, s))) &&
        inside({ lat: s.mid_lat, lon: s.mid_lon }, s) &&
        (!cityRow || inside({ lat: s.mid_lat, lon: s.mid_lon }, cityRow, 0.01));
      if (!ok) bad.push(s.id);
    } catch {
      bad.push(s.id);
    }
  }
  return check("street geometry + ids", bad.length === 0, bad.slice(0, 5).join(", "));
};

const boundaryCheck = (db: Pack, cityRow: CityRow | undefined): Check => {
  const bad: string[] = [];
  const areas = [
    ...(cityRow ? [{ id: "city", boundary: cityRow.boundary }] : []),
    ...(db.prepare("SELECT id, boundary FROM district").all() as {
      id: string;
      boundary: string;
    }[]),
  ];
  for (const a of areas) {
    try {
      const rings = (JSON.parse(a.boundary) as string[][]).flat().map((r) => decodePolyline6(r));
      if (rings.length === 0 || !rings.every(isClosedRing)) bad.push(a.id);
    } catch {
      bad.push(a.id);
    }
  }
  return check("boundary rings", bad.length === 0, bad.join(", "));
};

const orphanCheck = (db: Pack): Check => {
  const orphans = db
    .prepare(
      `SELECT count(*) FROM street_district sd
       WHERE NOT EXISTS (SELECT 1 FROM street s WHERE s.id = sd.street_id)
          OR NOT EXISTS (SELECT 1 FROM district d WHERE d.id = sd.district_id)`,
    )
    .pluck()
    .get() as number;
  return check("street_district references", orphans === 0, orphans ? `${orphans} orphans` : "");
};

/** Polyline6 rounding plus float noise: an edge's ends equal its junctions within this. */
const SAME_POINT_DEG = 2e-6;

const samePoint = (a: LatLng | undefined, b: LatLng | undefined): boolean =>
  a !== undefined &&
  b !== undefined &&
  Math.abs(a.lat - b.lat) <= SAME_POINT_DEG &&
  Math.abs(a.lon - b.lon) <= SAME_POINT_DEG;

interface EdgeRow {
  id: number;
  from_junction: number;
  to_junction: number;
  street_id: string;
  length_m: number;
  geometry: string;
}

/** Share of the edges in the largest connected part, by union-find over the junctions. */
const largestPartShare = (edges: EdgeRow[]): number => {
  const parent = new Map<number, number>();
  const root = (j: number): number => {
    let r = j;
    while (parent.has(r) && parent.get(r) !== r) r = parent.get(r) ?? r;
    parent.set(j, r);
    return r;
  };
  for (const e of edges) {
    if (!parent.has(e.from_junction)) parent.set(e.from_junction, e.from_junction);
    if (!parent.has(e.to_junction)) parent.set(e.to_junction, e.to_junction);
    parent.set(root(e.from_junction), root(e.to_junction));
  }
  const sizes = new Map<number, number>();
  for (const e of edges) {
    const r = root(e.from_junction);
    sizes.set(r, (sizes.get(r) ?? 0) + 1);
  }
  return edges.length === 0 ? 0 : Math.max(...sizes.values()) / edges.length;
};

/** The road graph: references, lengths, edges that start and end at their junctions, connectivity. */
const graphChecks = (db: Pack): Check[] => {
  const junctions = new Map(
    (db.prepare("SELECT id, lat, lon FROM junction").all() as (LatLng & { id: number })[]).map(
      (j) => [j.id, j],
    ),
  );
  const streets = new Set(db.prepare("SELECT id FROM street").pluck().all() as string[]);
  const edges = db.prepare("SELECT * FROM road_edge").all() as EdgeRow[];
  const bad: number[] = [];
  for (const e of edges) {
    try {
      const line = decodePolyline6(e.geometry);
      const ok =
        streets.has(e.street_id) &&
        e.length_m > 0 &&
        line.length >= 2 &&
        samePoint(line[0], junctions.get(e.from_junction)) &&
        samePoint(line.at(-1), junctions.get(e.to_junction));
      if (!ok) bad.push(e.id);
    } catch {
      bad.push(e.id);
    }
  }
  const share = largestPartShare(edges);
  return [
    check("road edges", edges.length > 0 && bad.length === 0, bad.slice(0, 5).join(", ")),
    check(
      `>= ${MIN_CONNECTED_SHARE * 100} % of edges connected`,
      share >= MIN_CONNECTED_SHARE,
      `${(share * 100).toFixed(1)} % of ${edges.length} edges, ${junctions.size} junctions`,
    ),
  ];
};

/** Checks a pack (.sqlite or .sqlite.gz) and prints a summary; returns false when anything fails. */
export const validatePack = (file: string): boolean => {
  const db = openPack(file);
  try {
    const meta = Object.fromEntries(
      (db.prepare("SELECT key, value FROM meta").all() as { key: string; value: string }[]).map(
        (r) => [r.key, r.value],
      ),
    );
    const missingMeta = META_KEYS.filter((k) => !meta[k]);
    const districts = districtCounts(db);
    const cityRow = db.prepare("SELECT * FROM city").get() as CityRow | undefined;
    const checks = [
      ...schemaChecks(db),
      check("meta keys", missingMeta.length === 0, missingMeta.join(", ")),
      relationsCheck(db, meta),
      districtCheck(districts),
      check("city row", cityRow !== undefined),
      streetCheck(db, cityRow),
      boundaryCheck(db, cityRow),
      orphanCheck(db),
      ...graphChecks(db),
    ];
    console.log(`${file}\n  city ${meta.city_id}  version ${meta.version}  scope ${meta.scope}`);
    console.table(districts);
    console.table(checks.map((c) => ({ ...c, ok: c.ok ? "ok" : "FAIL" })));
    return checks.every((c) => c.ok);
  } finally {
    db.close();
  }
};
