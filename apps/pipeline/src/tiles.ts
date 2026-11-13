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
// Protomaps daily builds stop at z15; MapLibre overzooms beyond it.
const MAX_ZOOM = 15;

/** Protomaps road kind -> `color.map.vector.*` fill and casing. */
const ROAD_PAINT: Record<string, [fill: string, casing: string]> = {
  highway: ["highway", "highway-casing"],
  major: ["major", "major-casing"],
  link: ["major", "major-casing"],
  minor: ["road", "road-casing"],
  other: ["path", "road-casing"],
};

/** `pois` kinds drawn as icons; the app adds a `poi-<kind>` image for each (poi_icons.dart). */
export const POI_KINDS = [
  "station",
  "bus_station",
  "aerodrome",
  "museum",
  "theatre",
  "cinema",
  "gallery",
  "attraction",
  "monument",
  "castle",
  "place_of_worship",
  "park",
  "garden",
  "zoo",
  "peak",
  "university",
  "college",
  "school",
  "library",
  "stadium",
  "townhall",
  "post_office",
  "hotel",
  "hospital",
  "pharmacy",
  "restaurant",
  "cafe",
  "bar",
  "pub",
  "fast_food",
  "supermarket",
  "mall",
  "marketplace",
];

/** Kinds so dense in a city centre (hundreds per km²) that they wait one zoom past their min_zoom. */
const DENSE_POI_KINDS = ["restaurant", "cafe", "bar", "pub", "fast_food", "pharmacy", "hotel"];

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
  const c = (name: string): string => resolveToken(tokens, `color.map.vector.${name}`, mode);
  const base = namedFlavor(mode);
  const land = c("land");
  const park = c("park");
  const wood = c("wood");
  const grass = c("grass");
  const sand = c("sand");
  const industrial = c("industrial");
  const road = c("road");
  const roadCasing = c("road-casing");
  return {
    ...base,
    background: land,
    earth: land,
    water: c("water"),
    park_a: park,
    park_b: park,
    zoo: park,
    wood_a: wood,
    wood_b: wood,
    scrub_a: grass,
    scrub_b: grass,
    sand,
    beach: sand,
    hospital: c("hospital"),
    school: c("school"),
    industrial,
    military: industrial,
    aerodrome: industrial,
    runway: road,
    pedestrian: c("pedestrian"),
    pier: land,
    buildings: c("building"),
    railway: c("railway"),
    boundaries: c("boundary"),
    ...Object.fromEntries(
      ["", "tunnel_", "bridges_"].flatMap((prefix) =>
        Object.entries(ROAD_PAINT).flatMap(([kind, [fill, casing]]) => [
          [`${prefix}${kind}`, c(fill)],
          [`${prefix}${kind}_casing`, c(casing)],
        ]),
      ),
    ),
    minor_a: road,
    minor_b: road,
    minor_service: road,
    minor_service_casing: roadCasing,
    major_casing_early: c("major-casing"),
    major_casing_late: c("major-casing"),
    highway_casing_early: c("highway-casing"),
    highway_casing_late: c("highway-casing"),
    landcover: {
      glacier: land,
      forest: wood,
      grassland: grass,
      scrub: grass,
      farmland: grass,
      barren: sand,
      urban_area: c("urban"),
    },
  };
};

/** Landmark icons, no names: the images are drawn by the app, so the style needs no sprite or glyphs. */
const poiLayer = {
  id: "pois",
  type: "symbol",
  source: "protomaps",
  "source-layer": "pois",
  filter: [
    "all",
    ["in", ["get", "kind"], ["literal", POI_KINDS]],
    [">=", ["zoom"], ["+", ["get", "min_zoom"], ["match", ["get", "kind"], DENSE_POI_KINDS, 1, 0]]],
  ],
  layout: {
    "icon-image": ["concat", "poi-", ["get", "kind"]],
    // Landmarks (lower min_zoom) win collisions over cafés.
    "symbol-sort-key": ["get", "min_zoom"],
  },
};

/** Unlabelled basemap: Protomaps layers minus every symbol layer, recoloured from the tokens, plus POI icons. */
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
  layers: [
    ...layers("protomaps", flavorFor(mode)).filter((layer) => layer.type !== "symbol"),
    poiLayer,
  ],
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
