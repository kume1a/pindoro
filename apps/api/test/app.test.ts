import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { FastifyInstance } from "fastify";
import postgres from "postgres";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.ts";
import { loadConfig } from "../src/config.ts";
import { runMigrations } from "../src/db/migrate.ts";

const DATABASE_URL =
  process.env.TEST_DATABASE_URL ?? "postgres://pindoro:pindoro@localhost:5433/pindoro_test";

const manifest = {
  format_version: 1,
  city: "tbilisi",
  name_ka: "თბილისი",
  name_en: "Tbilisi",
  version: "20261105T221700Z",
  file: "tbilisi-20261105T221700Z.sqlite.gz",
  sha256: "a".repeat(64),
  size: 1234,
  osm_timestamp: "2026-11-04T20:21:42Z",
  generated_at: "2026-11-05T22:17:00Z",
  bbox: { min_lat: 41.57, min_lon: 44.59, max_lat: 41.84, max_lon: 45.02 },
};

const appWith = (env: Record<string, string>): Promise<FastifyInstance> =>
  buildApp(
    loadConfig({
      NODE_ENV: "test",
      LOG_LEVEL: "silent",
      DATABASE_URL,
      PACKS_PUBLIC_URL: "https://packs.example.com/",
      ...env,
    }),
  );

describe("api", () => {
  let packsDir: string;
  let app: FastifyInstance;

  beforeAll(async () => {
    await runMigrations(DATABASE_URL);
    packsDir = await mkdtemp(join(tmpdir(), "pindoro-packs-"));
    await mkdir(join(packsDir, "tbilisi"));
    await writeFile(join(packsDir, "tbilisi", "manifest.json"), JSON.stringify(manifest));
    await mkdir(join(packsDir, "broken"));
    await writeFile(join(packsDir, "broken", "manifest.json"), "{ not json");
    // A file name outside the city's dir must never become a pack url.
    await mkdir(join(packsDir, "escape"));
    await writeFile(
      join(packsDir, "escape", "manifest.json"),
      JSON.stringify({ ...manifest, city: "escape", file: "../tbilisi/x.sqlite.gz" }),
    );
    app = await appWith({ PACKS_DIR: packsDir });
  });

  afterAll(async () => {
    await app?.close();
    await rm(packsDir, { recursive: true, force: true });
  });

  it("migrations install PostGIS and the M0 tables", async () => {
    const sql = postgres(DATABASE_URL, { max: 1 });
    const tables = await sql<{ table_name: string }[]>`
      select table_name from information_schema.tables where table_schema = 'public' order by 1`;
    await sql.end();
    expect(tables.map((t) => t.table_name)).toEqual(
      expect.arrayContaining(["city", "district", "pack", "street", "street_district"]),
    );
  });

  it("GET /health reports ok with the PostGIS version", async () => {
    const res = await app.inject({ method: "GET", url: "/health" });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: "ok", postgis: expect.stringMatching(/^3\./) });
  });

  it("GET /health returns 503 when the database is unreachable", async () => {
    const down = await appWith({ DATABASE_URL: "postgres://x:y@127.0.0.1:1/none" });
    const res = await down.inject({ method: "GET", url: "/health" });
    await down.close();
    expect(res.statusCode).toBe(503);
    expect(res.json()).toEqual({ status: "unavailable" });
  });

  it("GET /v1/catalog lists valid manifests with absolute pack urls", async () => {
    const res = await app.inject({ method: "GET", url: "/v1/catalog" });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      cities: [
        {
          id: "tbilisi",
          name_ka: "თბილისი",
          name_en: "Tbilisi",
          bbox: manifest.bbox,
          pack: {
            format_version: 1,
            version: manifest.version,
            url: "https://packs.example.com/tbilisi/tbilisi-20261105T221700Z.sqlite.gz",
            sha256: manifest.sha256,
            size: 1234,
            osm_timestamp: manifest.osm_timestamp,
          },
        },
      ],
    });
  });

  it("GET /v1/catalog is empty when the packs dir does not exist", async () => {
    const empty = await appWith({ PACKS_DIR: join(packsDir, "missing") });
    const res = await empty.inject({ method: "GET", url: "/v1/catalog" });
    await empty.close();
    expect(res.json()).toEqual({ cities: [] });
  });
});

describe("loadConfig", () => {
  it("applies defaults and coerces numbers", () => {
    expect(loadConfig({ PORT: "4000" })).toMatchObject({ PORT: 4000, HOST: "0.0.0.0" });
  });

  it("rejects invalid values", () => {
    expect(() => loadConfig({ PORT: "abc", DATABASE_URL: "mysql://x" })).toThrow(
      /Invalid environment/,
    );
  });
});
