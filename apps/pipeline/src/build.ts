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
import postgres, { type Sql } from "postgres";
import {
  type CityConfig,
  cityDir,
  databaseUrl,
  extractPath,
  fixturePath,
  loadCity,
  OUT_DIR,
} from "./config.ts";
import {
  type CurrentStreet,
  identityFile,
  matchIdentities,
  readIdentities,
  stagedIdentityFile,
  writeIdentities,
} from "./identity.ts";
import { isoSeconds, run } from "./io.ts";
import { extractCity, loadOsm, readNeighbourhoods, runSqlSteps } from "./load.ts";
import { finalisePack, type PackOptions, packVersion, writePack } from "./pack.ts";

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

/** Cuts and loads the extract, runs the SQL steps; returns the city's streets for identity. */
const loadStreets = async (
  sql: Sql,
  city: CityConfig,
  input: string,
  out: string,
): Promise<CurrentStreet[]> => {
  const pbf = extractCity(input, city.osm_relation_id, join(out, "work"));
  console.log("osm2pgsql");
  await loadOsm(sql, pbf, databaseUrl());
  await runSqlSteps(sql, {
    cityRelationId: city.osm_relation_id,
    utmSrid: city.utm_epsg,
    expectRelations: city.expect_relations,
    neighbourhoods: readNeighbourhoods(join(cityDir(city.id), "curation/neighbourhoods.geojson")),
  });
  return sql<CurrentStreet[]>`
    SELECT key::float8 AS key, norm_name, name_ka AS name, way_ids::float8[] AS way_ids
    FROM pipeline.street ORDER BY key`;
};

const writeFixturePack = async (sql: Sql, pack: PackOptions): Promise<void> => {
  const file = fixturePath(pack.city);
  mkdirSync(dirname(file), { recursive: true });
  await writePack(sql, file, {
    ...pack,
    districtId: `osm:r${pack.city.fixture.district_relation_id}`,
  });
  console.log(`fixture: ${file} (${(statSync(file).size / 1e3).toFixed(0)} kB)`);
};

const writeFullPack = async (sql: Sql, pack: PackOptions, out: string): Promise<void> => {
  const file = join(out, `${pack.city.id}-${pack.version}.sqlite`);
  const bbox = await writePack(sql, file, pack);
  const manifest = finalisePack(file, join(out, "manifest.json"), {
    city: pack.city.id,
    name_ka: pack.city.name_ka,
    name_en: pack.city.name_en,
    version: pack.version,
    osm_timestamp: pack.osmTimestamp,
    generated_at: pack.generatedAt,
    bbox,
  });
  console.log(`pack: ${join(out, manifest.file)} (${(manifest.size / 1e6).toFixed(2)} MB)`);
};

export const build = async (cityId: string, opts: { fixture: boolean }): Promise<void> => {
  const city = loadCity(cityId);
  const input = extractPath(city);
  if (!existsSync(input)) throw new Error(`missing ${input}; run: pipeline fetch ${cityId}`);
  const out = join(OUT_DIR, cityId);
  mkdirSync(out, { recursive: true });

  const sql = postgres(databaseUrl(), { onnotice: () => {} });
  try {
    // Identity always spans the whole city so fixture ids equal full-pack ids.
    const now = new Date();
    const identity = matchIdentities(
      readIdentities(cityId),
      await loadStreets(sql, city, input, out),
      now.toISOString().slice(0, 10),
    );
    const pack: PackOptions = {
      city,
      ids: identity.ids,
      version: packVersion(now),
      osmTimestamp: osmTimestamp(input),
      generatedAt: isoSeconds(now),
    };
    if (opts.fixture) {
      await writeFixturePack(sql, pack);
    } else {
      await writeFullPack(sql, pack, out);
    }

    // A full build's ids only count once its pack is validated and published; the fixture is
    // committed straight from the build.
    writeIdentities(
      opts.fixture ? identityFile(cityId) : stagedIdentityFile(cityId),
      identity.identities,
    );
    const report = join(out, `identity-diff-${pack.version}.json`);
    writeFileSync(report, `${JSON.stringify(identity.diff, null, 2)}\n`);
    const { matched, added, retired } = identity.diff;
    console.log(
      `identity: ${matched} matched, ${added.length} new, ${retired.length} retired -> ${report}`,
    );
  } finally {
    await sql.end();
  }
};
