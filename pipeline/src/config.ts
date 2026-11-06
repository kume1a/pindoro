import { readFileSync } from "node:fs";
import { basename, join, resolve } from "node:path";
import { parse } from "yaml";

export const REPO_ROOT = resolve(import.meta.dirname, "../..");
export const PIPELINE_DIR = join(REPO_ROOT, "pipeline");
export const CACHE_DIR = join(PIPELINE_DIR, ".cache");
export const OUT_DIR = join(PIPELINE_DIR, "out");
/** The claude.ai design system's tokens, then the app-only ones. */
export const TOKENS_FILES = ["tokens.json", "app.json"].map((f) =>
  join(REPO_ROOT, "packages/pindoro_design/tokens", f),
);
export const MOBILE_ASSETS = join(REPO_ROOT, "apps/mobile/assets");

export interface CityConfig {
  id: string;
  name_ka: string;
  name_en: string;
  osm_relation_id: number;
  utm_epsg: number;
  extract: { url: string; max_age_days: number };
  expect_relations: number[];
  fixture: { name: string; district_relation_id: number };
}

export const cityDir = (city: string): string => join(REPO_ROOT, "data/cities", city);

export const loadCity = (city: string): CityConfig => {
  const config = parse(readFileSync(join(cityDir(city), "city.yaml"), "utf8")) as CityConfig;
  for (const key of [
    "id",
    "name_ka",
    "name_en",
    "osm_relation_id",
    "utm_epsg",
    "extract",
  ] as const) {
    if (!config[key]) throw new Error(`data/cities/${city}/city.yaml: missing ${key}`);
  }
  return { ...config, expect_relations: config.expect_relations ?? [] };
};

export const extractPath = (city: CityConfig): string =>
  join(CACHE_DIR, city.id, basename(new URL(city.extract.url).pathname));

export const fixturePath = (city: CityConfig): string =>
  join(MOBILE_ASSETS, "packs_fixture", `${city.id}_${city.fixture.name}_fixture.sqlite`);

export const databaseUrl = (): string =>
  process.env.DATABASE_URL ?? "postgres://pindoro:pindoro@localhost:5433/pindoro";

export const packsDir = (): string => process.env.PACKS_DIR ?? join(REPO_ROOT, "infra/packs");
