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
  "fuel",
];

/**
 * Kinds so dense in a city centre (hundreds per km²) that they wait for their min_zoom; the rest
 * show a zoom earlier, from the first zoom whose tiles carry them.
 */
const DENSE_POI_KINDS = ["restaurant", "cafe", "bar", "pub", "fast_food", "pharmacy", "hotel"];

/**
 * Kinds that are no place to drive to, left off the navigation maps' every-place layers: land use,
 * areas and admin labels (Protomaps puts them in `pois` too), and street furniture (the pack skips
 * the same things in osm2pgsql/pindoro.lua).
 */
const NOT_PLACES = [
  "administrative",
  "allotments",
  "apartment",
  "atm",
  "bare_rock",
  "bench",
  "bicycle_parking",
  "brownfield",
  "building",
  "bus_stop",
  "commercial",
  "construction",
  "drinking_water",
  "farmland",
  "forest",
  "garages",
  "grass",
  "greenfield",
  "industrial",
  "information",
  "landfill",
  "meadow",
  "military",
  "motorcycle_parking",
  "neighborhood",
  "neighbourhood",
  "orchard",
  "outpost",
  "parking",
  "payment_terminal",
  "picnic_table",
  "pitch",
  "place",
  "playground",
  "post_box",
  "quarry",
  "railway",
  "recycling",
  "residential",
  "retail",
  "sand",
  "scrub",
  "shelter",
  "stop",
  "taxi",
  "telephone",
  "toilets",
  "vending_machine",
  "vineyard",
  "waste_basket",
  "waste_disposal",
  "water",
  "wetland",
  "wood",
];

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

const flavorFor = (mode: Mode, tokens: Map<string, TokenValue>): Flavor => {
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

/** Landmark icons: the images are drawn by the app, so the style needs no sprite. */
const poiLayer = {
  id: "pois",
  type: "symbol",
  source: "protomaps",
  "source-layer": "pois",
  filter: [
    "all",
    ["in", ["get", "kind"], ["literal", POI_KINDS]],
    [">=", ["zoom"], ["-", ["get", "min_zoom"], ["match", ["get", "kind"], DENSE_POI_KINDS, 0, 1]]],
  ],
  layout: {
    "icon-image": ["concat", "poi-", ["get", "kind"]],
    // Landmarks (lower min_zoom) win collisions over cafés.
    "symbol-sort-key": ["get", "min_zoom"],
  },
};

/**
 * Every named place, for the navigation maps (SPEC §16.23 item 132): the landmark kinds as `pois`
 * shows them, any other named kind (but [NOT_PLACES]) from its own min_zoom, with the
 * `poi-other` icon when the app has none for it. Hidden until the app switches to it.
 */
const allPoiFilter = [
  "all",
  ["!", ["in", ["get", "kind"], ["literal", NOT_PLACES]]],
  ["any", ["in", ["get", "kind"], ["literal", POI_KINDS]], ["has", "name"]],
  [
    ">=",
    ["zoom"],
    [
      "-",
      ["get", "min_zoom"],
      ["match", ["get", "kind"], POI_KINDS.filter((k) => !DENSE_POI_KINDS.includes(k)), 1, 0],
    ],
  ],
];

const poiAllLayer = {
  id: "pois-all",
  type: "symbol",
  source: "protomaps",
  "source-layer": "pois",
  filter: allPoiFilter,
  layout: {
    visibility: "none",
    "icon-image": [
      "match",
      ["get", "kind"],
      POI_KINDS,
      ["concat", "poi-", ["get", "kind"]],
      "poi-other",
    ],
    "symbol-sort-key": ["get", "min_zoom"],
  },
};

/** One-way arrows along the roads, always shown; the app adds the `oneway` image (poi_icons.dart). */
const onewayLayer = {
  id: "oneway-arrows",
  type: "symbol",
  source: "protomaps",
  "source-layer": "roads",
  // The tiles carry `oneway` ("yes" or "no") from z14; the arrows wait for street level.
  minzoom: 16,
  filter: ["==", ["get", "oneway"], "yes"],
  layout: {
    "symbol-placement": "line",
    "symbol-spacing": 120,
    "icon-image": "oneway",
    "icon-rotation-alignment": "map",
  },
};

/** Martin serves FiraGO's glyph ranges (`--font`); the app injects the tile server. */
const GLYPHS = "{TILES_BASE_URL}/font/{fontstack}/{range}";

/** The name in the app's street-name language: the app turns `{NAME_KEY}` into `name` or `name:en`. */
const NAME = ["coalesce", ["get", "{NAME_KEY}"], ["get", "name"]];

/** The name layers, bottom to top, hidden until the app shows them (SPEC §16.18, §16.22). */
export const NAME_LAYERS = {
  pois: "poi-names",
  poisAll: "poi-names-all",
  areas: "area-names",
  water: "water-names",
  roads: "road-names",
} as const;

/** Neighbourhoods named on the map (Protomaps `places` kinds). */
const AREA_KINDS = ["macrohood", "neighbourhood"];

/** The names of the places `filter` keeps, hidden until shown, each under its icon. */
const poiNameLayer = (id: string, filter: unknown, paint: object): object => ({
  id,
  type: "symbol",
  source: "protomaps",
  "source-layer": "pois",
  filter,
  layout: {
    visibility: "none",
    "symbol-sort-key": ["get", "min_zoom"],
    "text-field": NAME,
    "text-font": ["FiraGO Regular"],
    "text-size": 11,
    // Under the icon drawn at the same point, clear of its collision box.
    "text-anchor": "top",
    "text-offset": [0, 1.4],
    "text-max-width": 8,
  },
  paint,
});

/** Street names along the roads, place names under their icons, neighbourhood and river names. */
const nameLayers = (mode: Mode, tokens: Map<string, TokenValue>): object[] => {
  const paint = {
    "text-color": resolveToken(tokens, "color.map.vector.label", mode),
    "text-halo-color": resolveToken(tokens, "color.map.vector.land", mode),
    "text-halo-width": 1.5,
  };
  return [
    poiNameLayer(NAME_LAYERS.pois, poiLayer.filter, paint),
    poiNameLayer(NAME_LAYERS.poisAll, allPoiFilter, paint),
    {
      id: NAME_LAYERS.areas,
      type: "symbol",
      source: "protomaps",
      "source-layer": "places",
      filter: [
        "all",
        ["in", ["get", "kind"], ["literal", AREA_KINDS]],
        [">=", ["zoom"], ["get", "min_zoom"]],
      ],
      layout: {
        visibility: "none",
        "symbol-sort-key": ["get", "min_zoom"],
        "text-field": NAME,
        "text-font": ["FiraGO Medium"],
        "text-size": 13,
        "text-max-width": 8,
      },
      paint,
    },
    {
      id: NAME_LAYERS.water,
      type: "symbol",
      source: "protomaps",
      "source-layer": "water",
      // Rivers and streams; lakes have no label point.
      filter: [
        "all",
        ["has", "name"],
        ["in", ["geometry-type"], ["literal", ["LineString", "MultiLineString"]]],
      ],
      layout: {
        visibility: "none",
        "symbol-placement": "line",
        "text-field": NAME,
        "text-font": ["FiraGO Regular"],
        "text-size": 12,
      },
      paint,
    },
    {
      id: NAME_LAYERS.roads,
      type: "symbol",
      source: "protomaps",
      "source-layer": "roads",
      filter: ["has", "name"],
      layout: {
        visibility: "none",
        "symbol-placement": "line",
        "symbol-sort-key": ["get", "min_zoom"],
        "text-field": NAME,
        "text-font": ["FiraGO Medium"],
        "text-size": 12,
      },
      paint,
    },
  ];
};

/**
 * Protomaps layers minus every symbol layer, recoloured from the tokens, plus one-way arrows, the
 * hidden name layers and the POI icons on top.
 */
export const mapStyle = (mode: Mode): object => {
  const tokens = loadTokens();
  return {
    version: 8,
    name: `pindoro-${mode}`,
    glyphs: GLYPHS,
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
      ...layers("protomaps", flavorFor(mode, tokens)).filter((layer) => layer.type !== "symbol"),
      onewayLayer,
      ...nameLayers(mode, tokens),
      // On top: MapLibre places the top layer first, so landmark icons win over names.
      poiLayer,
      poiAllLayer,
    ],
  };
};

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
