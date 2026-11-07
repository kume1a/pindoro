import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { gunzipSync } from "node:zlib";
import { decodePolyline6, type LatLng } from "@pindoro/geo";
import Database from "better-sqlite3";
import { loadCity, MIN_AREA_STREETS } from "./config.ts";
import { META_KEYS, PACK_DDL, PACK_FORMAT_VERSION } from "./pack.ts";

export const MIN_EXPERT_STREETS = 30;
const TABLES = ["meta", "city", "district", "street", "street_district"];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

interface Check {
  check: string;
  ok: boolean;
  detail: string;
}

interface Bbox {
  min_lat: number;
  min_lon: number;
  max_lat: number;
  max_lon: number;
}

const openPack = (file: string): Database.Database => {
  if (!file.endsWith(".gz")) return new Database(file, { readonly: true, fileMustExist: true });
  const plain = join(mkdtempSync(join(tmpdir(), "pindoro-pack-")), "pack.sqlite");
  writeFileSync(plain, gunzipSync(readFileSync(file)));
  return new Database(plain, { readonly: true });
};

const columns = (db: Database.Database, table: string): string =>
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

/** Checks a pack (.sqlite or .sqlite.gz) and prints a summary; returns false when anything fails. */
export const validatePack = (file: string): boolean => {
  const db = openPack(file);
  const checks: Check[] = [];
  const check = (name: string, ok: boolean, detail = ""): void => {
    checks.push({ check: name, ok, detail });
  };

  const ref = new Database(":memory:");
  ref.exec(PACK_DDL);
  for (const t of TABLES) check(`schema ${t}`, columns(db, t) === columns(ref, t));
  check("user_version", db.pragma("user_version", { simple: true }) === PACK_FORMAT_VERSION);

  const meta = Object.fromEntries(
    (db.prepare("SELECT key, value FROM meta").all() as { key: string; value: string }[]).map(
      (r) => [r.key, r.value],
    ),
  );
  const missingMeta = META_KEYS.filter((k) => !meta[k]);
  check("meta keys", missingMeta.length === 0, missingMeta.join(", "));

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
  check("expected relations", missing.length === 0, missing.join(", "));

  const districts = db
    .prepare(
      `SELECT d.id, d.kind, d.name_ka AS name, count(s.id) AS streets,
              coalesce(sum(s.difficulty = 'expert'), 0) AS expert
       FROM district d
       LEFT JOIN street_district sd ON sd.district_id = d.id
       LEFT JOIN street s ON s.id = sd.street_id
       GROUP BY d.id ORDER BY d.id`,
    )
    .all() as { id: string; kind: string; name: string; streets: number; expert: number }[];
  const thin = districts.filter((d) =>
    d.kind === "district" ? d.expert < MIN_EXPERT_STREETS : d.streets < MIN_AREA_STREETS,
  );
  check(
    `>= ${MIN_EXPERT_STREETS} expert streets per district, ${MIN_AREA_STREETS} per neighbourhood`,
    districts.length > 0 && thin.length === 0,
    thin.map((d) => d.id).join(", "),
  );

  const cityRow = db.prepare("SELECT * FROM city").get() as
    | (Bbox & { boundary: string })
    | undefined;
  check("city row", cityRow !== undefined);
  const badStreets: string[] = [];
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
      if (!ok) badStreets.push(s.id);
    } catch {
      badStreets.push(s.id);
    }
  }
  check("street geometry + ids", badStreets.length === 0, badStreets.slice(0, 5).join(", "));

  const badAreas: string[] = [];
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
      const closed = (r: LatLng[]): boolean =>
        r.length >= 4 && r[0]?.lat === r.at(-1)?.lat && r[0]?.lon === r.at(-1)?.lon;
      if (rings.length === 0 || !rings.every(closed)) badAreas.push(a.id);
    } catch {
      badAreas.push(a.id);
    }
  }
  check("boundary rings", badAreas.length === 0, badAreas.join(", "));

  const orphans = db
    .prepare(
      `SELECT count(*) FROM street_district sd
       WHERE NOT EXISTS (SELECT 1 FROM street s WHERE s.id = sd.street_id)
          OR NOT EXISTS (SELECT 1 FROM district d WHERE d.id = sd.district_id)`,
    )
    .pluck()
    .get() as number;
  check("street_district references", orphans === 0, orphans ? `${orphans} orphans` : "");

  db.close();
  console.log(`${file}\n  city ${meta.city_id}  version ${meta.version}  scope ${meta.scope}`);
  console.table(districts);
  console.table(checks.map((c) => ({ ...c, ok: c.ok ? "ok" : "FAIL" })));
  return checks.every((c) => c.ok);
};
