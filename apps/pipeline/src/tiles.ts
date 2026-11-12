import { mkdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { type Flavor, layers, namedFlavor } from "@protomaps/basemaps";
import { MOBILE_ASSETS, REPO_ROOT, TOKENS_FILES } from "./config.ts";
import { replaceAtomically, run, writeJson } from "./io.ts";

// minLon,minLat,maxLon,maxLat around Georgia
const GEORGIA_BBOX = "39.9,41.0,46.8,43.6";
const TILES_FILE = join(REPO_ROOT, "infra/tiles/georgia.pmtiles");
const STYLES_DIR = join(MOBILE_ASSETS, "map_styles");
const ATTRIBUTION = "© OpenStreetMap contributors, Protomaps";
const ROAD_KINDS = ["highway", "major", "link", "minor", "other"];
// Protomaps daily builds stop at z15; MapLibre overzooms beyond it.
const MAX_ZOOM = 15;

type Mode = "light" | "dark";

/** Most recent Protomaps daily planet build (they are published as YYYYMMDD.pmtiles). */
const latestBuild = async (): Promise<string> => {
  for (let daysBack = 0; daysBack < 21; daysBack++) {
    const day = new Date(Date.now() - daysBack * 86_400_000).toISOString().slice(0, 10);
    const url = `https://build.protomaps.com/${day.replaceAll("-", "")}.pmtiles`;
    if ((await fetch(url, { method: "HEAD" })).ok) return url;
  }
  throw new Error("no Protomaps daily build found in the last 21 days");
};

export type TokenValue = string | Record<Mode, string>;

const loadTokens = (): Map<string, TokenValue> =>
  new Map(
    TOKENS_FILES.flatMap((file) =>
      Object.values(JSON.parse(readFileSync(file, "utf8")) as Record<string, unknown>).flatMap(
        (group) =>
          (group as { tokens?: { name: string; value: TokenValue }[] } | null)?.tokens?.map(
            (t) => [t.name, t.value] as const,
          ) ?? [],
      ),
    ),
  );

/** A token's value in one theme, following `{other.token}` aliases. */
export const resolveToken = (tokens: Map<string, TokenValue>, name: string, mode: Mode): string => {
  const value = tokens.get(name);
  if (value === undefined) throw new Error(`tokens: missing ${name}`);
  const raw = typeof value === "string" ? value : value[mode];
  const [, alias] = /^\{(.+)\}$/.exec(raw) ?? [];
  return alias ? resolveToken(tokens, alias, mode) : raw;
};

const flavorFor = (mode: Mode): Flavor => {
  const tokens = loadTokens();
  const c = (name: string): string => resolveToken(tokens, `color.map.basemap.${name}`, mode);
  const land = c("land");
  const park = c("park");
  const road = c("road");
  const casing = c("casing");
  return {
    ...namedFlavor(mode),
    background: land,
    earth: land,
    water: c("water"),
    park_a: park,
    park_b: park,
    wood_a: park,
    wood_b: park,
    buildings: c("building"),
    railway: c("railway"),
    boundaries: c("boundary"),
    ...Object.fromEntries(
      ["", "tunnel_", "bridges_"].flatMap((prefix) =>
        ROAD_KINDS.flatMap((kind) => [
          [`${prefix}${kind}`, road],
          [`${prefix}${kind}_casing`, casing],
        ]),
      ),
    ),
    minor_a: road,
    minor_b: road,
    minor_service: road,
    minor_service_casing: casing,
    major_casing_early: casing,
    major_casing_late: casing,
    highway_casing_early: casing,
    highway_casing_late: casing,
  };
};

/** Unlabelled basemap: Protomaps layers minus every symbol layer, recoloured from tokens.json. */
export const mapStyle = (mode: Mode): object => ({
  version: 8,
  name: `pindoro-${mode}`,
  sources: {
    // Tile template rather than TileJSON: behind the tunnel Martin's TileJSON would advertise http:// URLs.
    protomaps: {
      type: "vector",
      tiles: ["{TILES_BASE_URL}/georgia/{z}/{x}/{y}"],
      minzoom: 0,
      maxzoom: MAX_ZOOM,
      attribution: ATTRIBUTION,
    },
  },
  layers: layers("protomaps", flavorFor(mode)).filter((layer) => layer.type !== "symbol"),
});

const writeStyles = (): void => {
  mkdirSync(STYLES_DIR, { recursive: true });
  for (const mode of ["light", "dark"] as const) {
    const file = join(STYLES_DIR, `pindoro_${mode}.json`);
    writeJson(file, mapStyle(mode));
    console.log(`style: ${file}`);
  }
};

export const tiles = async (opts: { stylesOnly: boolean }): Promise<void> => {
  writeStyles();
  if (opts.stylesOnly) return;
  const url = await latestBuild();
  console.log(`extracting ${url} (bbox ${GEORGIA_BBOX}) -> ${TILES_FILE}`);
  // martin keeps serving the old file until `dc restart martin`.
  replaceAtomically(TILES_FILE, (tmp) =>
    run("pmtiles", ["extract", url, tmp, `--bbox=${GEORGIA_BBOX}`, "--download-threads=4"]),
  );
};
