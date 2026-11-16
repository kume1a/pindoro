import type { LatLng } from "@pindoro/geo";
import { isoSeconds } from "./io.ts";

/** A street-level photo a source offers near a target. */
export interface Frame {
  source: "mapillary" | "panoramax";
  /** The image id at the source. */
  sourceId: string;
  at: LatLng;
  /** Degrees from north the image looks: a flat photo's centre, a panorama's centre column. */
  compass: number;
  pano: boolean;
  capturedAt: string | null;
  /** Display form, e.g. `CC BY-SA 4.0`. */
  licence: string;
  author: string;
  link: string | null;
  imageUrl: string;
}

export interface SearchArea {
  minLat: number;
  minLon: number;
  maxLat: number;
  maxLon: number;
}

export interface PhotoSources {
  fetch: typeof fetch;
  mapillaryToken?: string;
  panoramaxUrl?: string;
}

const RETRIES = 5;
const RETRY_BASE_MS = 500;

const sleep = (ms: number): Promise<void> => new Promise((done) => setTimeout(done, ms));

const isTransient = (status: number): boolean => status === 429 || status >= 500;

/** GET with backoff on 429, 5xx and network errors; any other failure throws at once. */
const getRetrying = async (
  sources: PhotoSources,
  url: string,
  headers: Record<string, string> = {},
): Promise<Response> => {
  for (let attempt = 0; ; attempt++) {
    const last = attempt === RETRIES;
    let res: Response | undefined;
    try {
      res = await sources.fetch(url, { headers });
    } catch (e) {
      if (last) throw e;
    }
    if (res?.ok) return res;
    if (res && (last || !isTransient(res.status))) {
      throw new Error(`HTTP ${res.status} for ${withoutQuery(url)}`);
    }
    await sleep(RETRY_BASE_MS * 2 ** attempt);
  }
};

/** Signed image URLs and search parameters stay out of error messages. */
const withoutQuery = (url: string): string => url.split("?")[0] ?? url;

export const download = async (sources: PhotoSources, url: string): Promise<Buffer> =>
  Buffer.from(await (await getRetrying(sources, url)).arrayBuffer());

const bboxParam = (a: SearchArea): string => [a.minLon, a.minLat, a.maxLon, a.maxLat].join(",");

interface MapillaryImage {
  id: string;
  computed_geometry?: { coordinates: [number, number] };
  geometry?: { coordinates: [number, number] };
  computed_compass_angle?: number;
  compass_angle?: number;
  captured_at?: number;
  creator?: { username?: string };
  is_pano?: boolean;
  thumb_2048_url?: string;
  thumb_original_url?: string;
}

const MAPILLARY_FIELDS = [
  "id",
  "computed_geometry",
  "geometry",
  "computed_compass_angle",
  "compass_angle",
  "captured_at",
  "creator",
  "is_pano",
  "thumb_2048_url",
  "thumb_original_url",
].join(",");

/** Mapillary imagery is CC BY-SA 4.0 throughout; it has no NonCommercial images. */
const mapillaryFrame = (image: MapillaryImage): Frame | null => {
  const [lon, lat] = (image.computed_geometry ?? image.geometry)?.coordinates ?? [];
  const compass = image.computed_compass_angle ?? image.compass_angle;
  const pano = image.is_pano === true;
  // A panorama is reprojected, so it needs more pixels than a 2048 px wide thumbnail gives.
  const imageUrl = pano ? (image.thumb_original_url ?? image.thumb_2048_url) : image.thumb_2048_url;
  const author = image.creator?.username;
  if (lat === undefined || lon === undefined || compass === undefined || !imageUrl || !author) {
    return null;
  }
  return {
    source: "mapillary",
    sourceId: image.id,
    at: { lat, lon },
    compass,
    pano,
    capturedAt: image.captured_at ? isoSeconds(new Date(image.captured_at)) : null,
    licence: "CC BY-SA 4.0",
    author,
    link: `https://www.mapillary.com/app/?pKey=${image.id}`,
    imageUrl,
  };
};

/** Mapillary Graph API v4 images in `area`; the token goes in a header, never in a URL. */
export const mapillaryFrames = async (
  sources: PhotoSources,
  area: SearchArea,
): Promise<Frame[]> => {
  const url = `https://graph.mapillary.com/images?fields=${MAPILLARY_FIELDS}&bbox=${bboxParam(area)}&limit=100`;
  const res = await getRetrying(sources, url, {
    authorization: `OAuth ${sources.mapillaryToken}`,
  });
  const body = (await res.json()) as { data?: MapillaryImage[] };
  return (body.data ?? []).map(mapillaryFrame).filter((f) => f !== null);
};

/** SPDX ids of the licences the app may show, in display form; NonCommercial ones are left out. */
const OPEN_LICENCES: Record<string, string> = {
  "CC-BY-SA-4.0": "CC BY-SA 4.0",
  "CC-BY-4.0": "CC BY 4.0",
  "CC0-1.0": "CC0 1.0",
  "etalab-2.0": "Etalab 2.0",
};

interface StacProvider {
  name?: string;
  roles?: string[];
}

interface PanoramaxItem {
  id: string;
  geometry?: { coordinates: [number, number] };
  providers?: StacProvider[];
  properties?: {
    datetime?: string;
    license?: string;
    providers?: StacProvider[];
    "view:azimuth"?: number;
    "pers:interior_orientation"?: { field_of_view?: number };
  };
  assets?: Record<string, { href?: string }>;
}

/** The photographer: the picture's own artist when it names one, else the uploading account. */
const producerOf = (item: PanoramaxItem): string | undefined =>
  (item.providers ?? item.properties?.providers ?? [])
    .filter((p) => p.roles?.includes("producer") && p.name)
    .at(-1)?.name;

const panoramaxFrame = (item: PanoramaxItem): Frame | null => {
  const [lon, lat] = item.geometry?.coordinates ?? [];
  const props = item.properties ?? {};
  const compass = props["view:azimuth"];
  const licence = OPEN_LICENCES[props.license ?? ""];
  const pano = props["pers:interior_orientation"]?.field_of_view === 360;
  const imageUrl = (pano ? item.assets?.hd : (item.assets?.sd ?? item.assets?.hd))?.href;
  const author = producerOf(item);
  if (
    lat === undefined ||
    lon === undefined ||
    compass === undefined ||
    !licence ||
    !imageUrl ||
    !author
  ) {
    return null;
  }
  return {
    source: "panoramax",
    sourceId: item.id,
    at: { lat, lon },
    compass,
    pano,
    capturedAt: props.datetime ? isoSeconds(new Date(props.datetime)) : null,
    licence,
    author,
    // The instance is private: there is no public page to link.
    link: null,
    imageUrl,
  };
};

/** Pictures in `area` on the private Panoramax instance (STAC `/api/search`). */
export const panoramaxFrames = async (
  sources: PhotoSources,
  area: SearchArea,
): Promise<Frame[]> => {
  const base = sources.panoramaxUrl?.replace(/\/+$/, "");
  const res = await getRetrying(sources, `${base}/api/search?bbox=${bboxParam(area)}&limit=100`);
  const body = (await res.json()) as { features?: PanoramaxItem[] };
  return (body.features ?? []).map(panoramaxFrame).filter((f) => f !== null);
};
