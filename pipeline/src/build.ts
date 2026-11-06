import {
  createWriteStream,
  existsSync,
  mkdirSync,
  renameSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { Readable } from "node:stream";
import { pipeline as pipe } from "node:stream/promises";
import type { ReadableStream } from "node:stream/web";
import postgres from "postgres";
import { cityDir, databaseUrl, extractPath, fixturePath, loadCity, OUT_DIR } from "./config.ts";
import { matchIdentities, readIdentities, writeIdentities } from "./identity.ts";
import { extractCity, loadOsm, readNeighbourhoods, run, runSqlSteps } from "./load.ts";
import { finalisePack, type Manifest, packVersion, writePack } from "./pack.ts";

const DAY_MS = 86_400_000;

/** Downloads the city's extract into the cache unless a fresh copy is already there. */
export const fetchExtract = async (cityId: string): Promise<string> => {
  const city = loadCity(cityId);
  const dest = extractPath(city);
  if (
    existsSync(dest) &&
    Date.now() - statSync(dest).mtimeMs < city.extract.max_age_days * DAY_MS
  ) {
    console.log(`fresh: ${dest}`);
    return dest;
  }
  mkdirSync(dirname(dest), { recursive: true });
  console.log(`downloading ${city.extract.url}`);
  const res = await fetch(city.extract.url);
  if (!res.ok || !res.body) throw new Error(`download failed (${res.status}): ${city.extract.url}`);
  const part = `${dest}.part`;
  await pipe(Readable.fromWeb(res.body as ReadableStream), createWriteStream(part));
  renameSync(part, dest);
  console.log(`saved ${dest} (${(statSync(dest).size / 1e6).toFixed(1)} MB)`);
  return dest;
};

const osmTimestamp = (pbf: string): string =>
  run("osmium", ["fileinfo", "-g", "header.option.osmosis_replication_timestamp", pbf]).trim() ||
  run("osmium", ["fileinfo", "-e", "-g", "data.timestamp.last", pbf]).trim();

export const build = async (cityId: string, opts: { fixture: boolean }): Promise<void> => {
  const city = loadCity(cityId);
  const input = extractPath(city);
  if (!existsSync(input)) throw new Error(`missing ${input}; run: pipeline fetch ${cityId}`);
  const out = join(OUT_DIR, cityId);
  const pbf = extractCity(input, city.osm_relation_id, join(out, "work"));

  const url = databaseUrl();
  const sql = postgres(url, { onnotice: () => {} });
  try {
    console.log("osm2pgsql");
    await loadOsm(sql, pbf, url);
    await runSqlSteps(sql, {
      cityRelationId: city.osm_relation_id,
      utmSrid: city.utm_epsg,
      expectRelations: city.expect_relations,
      neighbourhoods: readNeighbourhoods(join(cityDir(cityId), "curation/neighbourhoods.geojson")),
    });

    // Identity always spans the whole city so fixture ids equal full-pack ids.
    const rows = await sql`
      SELECT key::float8 AS key, norm_name, name_ka AS name, way_ids::float8[] AS way_ids
      FROM pipeline.street ORDER BY key`;
    const current = rows.map((r) => ({
      key: r.key as number,
      norm_name: r.norm_name as string,
      name: r.name as string,
      way_ids: r.way_ids as number[],
    }));
    const now = new Date();
    const identity = matchIdentities(
      readIdentities(cityId),
      current,
      now.toISOString().slice(0, 10),
    );

    const version = packVersion(now);
    const pack = {
      city,
      ids: identity.ids,
      version,
      osmTimestamp: osmTimestamp(input),
      generatedAt: now.toISOString().replace(/\.\d+Z$/, "Z"),
    };
    mkdirSync(out, { recursive: true });
    if (opts.fixture) {
      const file = fixturePath(city);
      mkdirSync(dirname(file), { recursive: true });
      await writePack(sql, file, {
        ...pack,
        districtId: `osm:r${city.fixture.district_relation_id}`,
      });
      console.log(`fixture: ${file} (${(statSync(file).size / 1e3).toFixed(0)} kB)`);
    } else {
      const file = join(out, `${cityId}-${version}.sqlite`);
      await writePack(sql, file, pack);
      const [bbox] = await sql`
        SELECT ST_YMin(geom) AS min_lat, ST_XMin(geom) AS min_lon,
               ST_YMax(geom) AS max_lat, ST_XMax(geom) AS max_lon
        FROM pipeline.pack_area WHERE id = 'city'`;
      const manifest = finalisePack(file, join(out, "manifest.json"), {
        format_version: 1,
        city: cityId,
        name_ka: city.name_ka,
        name_en: city.name_en,
        version,
        osm_timestamp: pack.osmTimestamp,
        generated_at: pack.generatedAt,
        bbox: bbox as Manifest["bbox"],
      });
      console.log(`pack: ${join(out, manifest.file)} (${(manifest.size / 1e6).toFixed(2)} MB)`);
    }

    writeIdentities(cityId, identity.identities);
    const report = join(out, `identity-diff-${version}.json`);
    writeFileSync(report, `${JSON.stringify(identity.diff, null, 2)}\n`);
    const { matched, added, retired } = identity.diff;
    console.log(
      `identity: ${matched} matched, ${added.length} new, ${retired.length} retired -> ${report}`,
    );
  } finally {
    await sql.end();
  }
};
