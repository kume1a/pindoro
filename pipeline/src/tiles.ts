import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { type Flavor, layers, namedFlavor } from "@protomaps/basemaps";
import { MOBILE_ASSETS, REPO_ROOT, TOKENS_FILE } from "./config.ts";
import { run } from "./load.ts";

// minLon,minLat,maxLon,maxLat around Georgia
const GEORGIA_BBOX = "39.9,41.0,46.8,43.6";
const TILES_FILE = join(REPO_ROOT, "infra/tiles/georgia.pmtiles");
const STYLES_DIR = join(MOBILE_ASSETS, "map_styles");
const ATTRIBUTION = "© OpenStreetMap contributors, Protomaps";
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

/** Tokens use Flutter's #AARRGGBB; MapLibre wants #RRGGBBAA. */
const cssColor = (hex: string): string =>
  hex.length === 9 ? `#${hex.slice(3)}${hex.slice(1, 3)}` : hex;

const flavorFor = (mode: Mode): Flavor => {
  const tokens = JSON.parse(readFileSync(TOKENS_FILE, "utf8")) as Record<string, unknown>;
  const c = (name: string): string => {
    const value = tokens[`color.map.${mode}.${name}`];
    if (typeof value !== "string")
      throw new Error(`tokens.json: missing color.map.${mode}.${name}`);
    return cssColor(value);
  };
  const major = c("road_major");
  const minor = c("road_minor");
  const casing = c("road_casing");
  return {
    ...namedFlavor(mode),
    background: c("background"),
    earth: c("earth"),
    water: c("water"),
    park_a: c("park"),
    park_b: c("park"),
    wood_a: c("wood"),
    wood_b: c("wood"),
    buildings: c("building"),
    railway: c("railway"),
    boundaries: c("boundary"),
    ...Object.fromEntries(
      ["", "tunnel_", "bridges_"].flatMap((prefix) => [
        [`${prefix}highway`, major],
        [`${prefix}major`, major],
        [`${prefix}link`, major],
        [`${prefix}minor`, minor],
        [`${prefix}other`, minor],
        [`${prefix}highway_casing`, casing],
        [`${prefix}major_casing`, casing],
        [`${prefix}link_casing`, casing],
        [`${prefix}minor_casing`, casing],
        [`${prefix}other_casing`, casing],
      ]),
    ),
    minor_a: minor,
    minor_b: minor,
    minor_service: minor,
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

export const writeStyles = (): void => {
  mkdirSync(STYLES_DIR, { recursive: true });
  for (const mode of ["light", "dark"] as const) {
    const file = join(STYLES_DIR, `pindoro_${mode}.json`);
    writeFileSync(file, `${JSON.stringify(mapStyle(mode), null, 2)}\n`);
    console.log(`style: ${file}`);
  }
};

export const tiles = async (opts: { stylesOnly: boolean }): Promise<void> => {
  writeStyles();
  if (opts.stylesOnly) return;
  const url = await latestBuild();
  console.log(`extracting ${url} (bbox ${GEORGIA_BBOX}) -> ${TILES_FILE}`);
  run("pmtiles", ["extract", url, TILES_FILE, `--bbox=${GEORGIA_BBOX}`, "--download-threads=4"]);
};
