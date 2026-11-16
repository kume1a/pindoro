import { createHash } from "node:crypto";
import {
  copyFileSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { gunzipSync } from "node:zlib";
import { decodePolyline6, type LatLng, type Polyline } from "@pindoro/geo";
import Database from "better-sqlite3";
import sharp, { type Sharp } from "sharp";
import { buildDir, packsDir } from "./config.ts";
import { isoSeconds, replaceAtomically, writeJson } from "./io.ts";
import { packVersion, readManifest } from "./pack.ts";
import {
  download,
  type Frame,
  mapillaryFrames,
  type PhotoSources,
  panoramaxFrames,
  type SearchArea,
} from "./photo-sources.ts";

/** SPEC §10 and §13 (the photo pack row). */
export const PhotoConfig = {
  formatVersion: 1,
  budget: 2100,
  approachMinM: 25,
  approachMaxM: 40,
  snapM: 12,
  flatAngleMaxDeg: 30,
  width: 960,
  height: 540,
  panoFovDeg: 100,
  /** About 80 KB a frame, SPEC §10's budget. */
  webpQuality: 70,
  /** Panoramas are scaled to this width first: 100° of it is still wider than the frame. */
  panoWidth: 4096,
  concurrency: 8,
  /** Targets looked up between two budget checks. */
  chunk: 64,
  keptVersions: 2,
} as const;

// Mirrors docs/pack-format.md (photo pack).
export const PHOTO_DDL = `
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);

CREATE TABLE scene_image (
  id            TEXT PRIMARY KEY,
  junction_node INTEGER NOT NULL,
  approach_node INTEGER NOT NULL,
  lat           REAL NOT NULL,
  lon           REAL NOT NULL,
  heading       REAL NOT NULL,
  distance_m    REAL NOT NULL,
  captured_at   TEXT,
  source        TEXT NOT NULL CHECK (source IN ('mapillary', 'panoramax')),
  licence       TEXT NOT NULL,
  author        TEXT NOT NULL,
  link          TEXT,
  width         INTEGER NOT NULL,
  height        INTEGER NOT NULL,
  webp          BLOB NOT NULL
);
`;

export type TargetLayer = "skeleton" | "gateway" | "street" | "district";

/** A junction approach to photograph. */
export interface Target {
  junction: number;
  approachEdge: number;
  junctionNode: number;
  approachNode: number;
  streetId: string | null;
  tier: string | null;
  layer: "skeleton" | "gateway" | "district" | "bridge";
  rank: number;
  /** The approach edge, from its far junction to this one. */
  line: Polyline;
}

/** The targets in the order the photo pack fills its budget (docs/pack-format.md). */
export interface TargetPlan {
  primary: Target[];
  /** Per tier A or B street, its other approaches by rank. */
  byStreet: Target[][];
  district: Target[];
}

const LAYERS: Record<string, Target["layer"]> = {
  skeleton: "skeleton",
  gateway_out: "gateway",
  gateway_in: "gateway",
  district: "district",
  bridge: "bridge",
};

interface ItemRow {
  junction_id: number;
  approach_edge: number;
  layer: string;
  rank: number;
  from_junction: number;
  to_junction: number;
  street_id: string | null;
  geometry: string;
  junction_node: number;
  approach_node: number;
  tier: string | null;
}

const byRank = (a: Target, b: Target): number =>
  a.rank - b.rank || (a.layer === b.layer ? 0 : a.layer === "skeleton" ? -1 : 1);

/**
 * The pack's junction approaches, each once (at its skeleton or gateway item first, then by rank),
 * planned per the doc.
 */
export const planTargets = (db: Database.Database): TargetPlan => {
  const rows = db
    .prepare(
      `SELECT i.junction_id, i.approach_edge, i.layer, i.rank, e.from_junction, e.to_junction,
              e.street_id, e.geometry, j.node_id AS junction_node, o.node_id AS approach_node, s.tier
       FROM junction_item i
       JOIN road_edge e ON e.id = i.approach_edge
       JOIN junction j ON j.id = i.junction_id
       JOIN junction o ON o.id = CASE WHEN e.to_junction = i.junction_id
                                      THEN e.from_junction ELSE e.to_junction END
       LEFT JOIN street s ON s.id = e.street_id
       ORDER BY i.layer NOT IN ('skeleton', 'gateway_out', 'gateway_in'), i.rank,
                i.junction_id, i.approach_edge, i.layer`,
    )
    .all() as ItemRow[];
  const targets = new Map<string, Target>();
  for (const r of rows) {
    const key = `${r.junction_id}:${r.approach_edge}`;
    const layer = LAYERS[r.layer];
    if (!layer || targets.has(key)) continue;
    const line = decodePolyline6(r.geometry);
    targets.set(key, {
      junction: r.junction_id,
      approachEdge: r.approach_edge,
      junctionNode: r.junction_node,
      approachNode: r.approach_node,
      streetId: r.street_id,
      tier: r.tier,
      layer,
      rank: r.rank,
      line: r.to_junction === r.junction_id ? line : line.toReversed(),
    });
  }
  const all = [...targets.values()].sort(byRank);
  const isPrimary = (t: Target): boolean => t.layer === "skeleton" || t.layer === "gateway";
  const primary = all.filter(isPrimary);
  const rest = all.filter((t) => !isPrimary(t));
  const streets = new Map<string, Target[]>();
  for (const t of rest) {
    if (t.streetId === null || (t.tier !== "A" && t.tier !== "B")) continue;
    streets.set(t.streetId, [...(streets.get(t.streetId) ?? []), t]);
  }
  return {
    primary,
    byStreet: [...streets.values()],
    district: rest.filter((t) => t.layer === "district"),
  };
};

const RAD = Math.PI / 180;
const M_PER_DEG = 6_371_008.8 * RAD;

type XY = [x: number, y: number];

/** Metres east and north of `origin` (the same local projection as `@pindoro/geo`). */
const toXY = (origin: LatLng, p: LatLng): XY => [
  (p.lon - origin.lon) * M_PER_DEG * Math.cos(origin.lat * RAD),
  (p.lat - origin.lat) * M_PER_DEG,
];

const bearingOf = ([dx, dy]: XY): number => (Math.atan2(dx, dy) / RAD + 360) % 360;

/** Smallest angle between two bearings, 0–180. */
export const angleOff = (a: number, b: number): number => {
  const d = Math.abs((((a - b) % 360) + 360) % 360);
  return d > 180 ? 360 - d : d;
};

interface Snap {
  offM: number;
  /** Metres along the line to the snapped point. */
  alongM: number;
  lengthM: number;
  /** The line's direction at the snapped point. */
  bearing: number;
}

/** Where `p` lands on `line`: how far off it is, how far along and the direction there. */
const snapToLine = (line: Polyline, p: LatLng): Snap => {
  const xy = line.map((q) => toXY(p, q));
  let best: Snap = { offM: Infinity, alongM: 0, lengthM: 0, bearing: 0 };
  let walked = 0;
  for (let i = 0; i + 1 < xy.length; i++) {
    const [ax, ay] = xy[i] as XY;
    const [bx, by] = xy[i + 1] as XY;
    const dx = bx - ax;
    const dy = by - ay;
    const len = Math.sqrt(dx * dx + dy * dy);
    const t = len === 0 ? 0 : Math.min(1, Math.max(0, -(ax * dx + ay * dy) / (len * len)));
    const off = Math.hypot(ax + t * dx, ay + t * dy);
    if (off < best.offM) {
      best = { offM: off, alongM: walked + t * len, lengthM: 0, bearing: bearingOf([dx, dy]) };
    }
    walked += len;
  }
  return { ...best, lengthM: walked };
};

/** The point `distanceM` along `line` (clamped to its ends). */
const pointAlong = (line: Polyline, distanceM: number): LatLng => {
  const origin = line[0] as LatLng;
  let left = distanceM;
  for (let i = 0; i + 1 < line.length; i++) {
    const a = line[i] as LatLng;
    const b = line[i + 1] as LatLng;
    const [dx, dy] = toXY(a, b);
    const len = Math.sqrt(dx * dx + dy * dy);
    if (left <= len && len > 0) {
      const t = left / len;
      return { lat: a.lat + t * (b.lat - a.lat), lon: a.lon + t * (b.lon - a.lon) };
    }
    left -= len;
  }
  return line.at(-1) ?? origin;
};

const lineLengthM = (line: Polyline): number => snapToLine(line, line[0] as LatLng).lengthM;

/** Where to search for a target's frames, or null when the approach is too short for the band. */
export const searchArea = (target: Target): SearchArea | null => {
  const length = lineLengthM(target.line);
  if (length < PhotoConfig.approachMinM) return null;
  const mid = (PhotoConfig.approachMinM + Math.min(PhotoConfig.approachMaxM, length)) / 2;
  const centre = pointAlong(target.line, length - mid);
  const reach = (PhotoConfig.approachMaxM - PhotoConfig.approachMinM) / 2 + PhotoConfig.snapM * 2;
  const dLat = reach / M_PER_DEG;
  const dLon = reach / (M_PER_DEG * Math.cos(centre.lat * RAD));
  return {
    minLat: centre.lat - dLat,
    minLon: centre.lon - dLon,
    maxLat: centre.lat + dLat,
    maxLon: centre.lon + dLon,
  };
};

/** A frame that fits a target: how far before the junction, the direction of travel there. */
export interface Fit {
  frame: Frame;
  distanceM: number;
  travel: number;
  angleOff: number;
}

/** The frame on the approach 25–40 m before the junction, looking ahead (a flat photo), or null. */
export const fitFrame = (target: Target, frame: Frame): Fit | null => {
  const snap = snapToLine(target.line, frame.at);
  const before = snap.lengthM - snap.alongM;
  const off = frame.pano ? 0 : angleOff(frame.compass, snap.bearing);
  const fits =
    snap.offM <= PhotoConfig.snapM &&
    before >= PhotoConfig.approachMinM &&
    before <= PhotoConfig.approachMaxM &&
    off <= PhotoConfig.flatAngleMaxDeg;
  return fits ? { frame, distanceM: before, travel: snap.bearing, angleOff: off } : null;
};

/** Among the fits: a panorama or the smallest angle off, then the newest. */
export const bestFit = (target: Target, frames: Frame[]): Fit | null =>
  frames
    .map((f) => fitFrame(target, f))
    .filter((f) => f !== null)
    .sort(
      (a, b) =>
        a.angleOff - b.angleOff ||
        (b.frame.capturedAt ?? "").localeCompare(a.frame.capturedAt ?? ""),
    )[0] ?? null;

const sample = (
  src: Buffer,
  width: number,
  height: number,
  channels: number,
  u: number,
  v: number,
  out: Buffer,
  at: number,
): void => {
  const x0 = Math.floor(u);
  const y0 = Math.min(height - 1, Math.max(0, Math.floor(v)));
  const y1 = Math.min(height - 1, y0 + 1);
  const fx = u - x0;
  const fy = Math.min(1, Math.max(0, v - y0));
  const xa = ((x0 % width) + width) % width;
  const xb = (xa + 1) % width;
  for (let c = 0; c < 3; c++) {
    const p = (x: number, y: number): number => src[(y * width + x) * channels + c] ?? 0;
    const top = p(xa, y0) * (1 - fx) + p(xb, y0) * fx;
    const bottom = p(xa, y1) * (1 - fx) + p(xb, y1) * fx;
    out[at + c] = Math.round(top * (1 - fy) + bottom * fy);
  }
};

/**
 * A rectilinear view of an equirectangular panorama: `yawDeg` right of the panorama's centre
 * column, horizon level, `PhotoConfig.panoFovDeg` wide. Raw RGB, `width` × `height`.
 */
export const reproject = (
  src: Buffer,
  srcWidth: number,
  srcHeight: number,
  channels: number,
  yawDeg: number,
  width: number = PhotoConfig.width,
  height: number = PhotoConfig.height,
): Buffer => {
  const out = Buffer.alloc(width * height * 3);
  const focal = width / 2 / Math.tan((PhotoConfig.panoFovDeg / 2) * RAD);
  for (let j = 0; j < height; j++) {
    const y = j + 0.5 - height / 2;
    for (let i = 0; i < width; i++) {
      const x = i + 0.5 - width / 2;
      const lon = yawDeg + Math.atan2(x, focal) / RAD;
      const lat = -Math.atan2(y, Math.hypot(x, focal)) / RAD;
      const u = (lon / 360 + 0.5) * srcWidth - 0.5;
      const v = (0.5 - lat / 180) * srcHeight - 0.5;
      sample(src, srcWidth, srcHeight, channels, u, v, out, (j * width + i) * 3);
    }
  }
  return out;
};

const toWebp = (image: Sharp): Promise<Buffer> =>
  image.webp({ quality: PhotoConfig.webpQuality }).toBuffer();

/** The stored frame: a flat photo centre-cropped to 16:9, a panorama looking along the approach. */
export const renderFrame = async (image: Buffer, fit: Fit): Promise<Buffer> => {
  const { width, height } = PhotoConfig;
  if (!fit.frame.pano) {
    return toWebp(sharp(image).rotate().resize(width, height, { fit: "cover" }));
  }
  const { data, info } = await sharp(image)
    .resize({ width: PhotoConfig.panoWidth, withoutEnlargement: true })
    .removeAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  // ponytail: assumes the panorama's centre column looks along its compass angle and the horizon
  // is level (no pitch/roll correction); add the source's pitch and roll if frames come out tilted.
  const view = reproject(
    data,
    info.width,
    info.height,
    info.channels,
    fit.travel - fit.frame.compass,
  );
  return toWebp(sharp(view, { raw: { width, height, channels: 3 } }));
};

interface Photo {
  target: Target;
  fit: Fit;
  webp: Buffer;
}

/** The first source with a fitting frame wins; a frame that fails to download falls through. */
const lookUp = async (sources: PhotoSources, target: Target): Promise<Photo | null> => {
  const area = searchArea(target);
  if (!area) return null;
  const search = [
    sources.mapillaryToken ? mapillaryFrames : null,
    sources.panoramaxUrl ? panoramaxFrames : null,
  ].filter((s) => s !== null);
  for (const frames of search) {
    const fit = bestFit(target, await frames(sources, area));
    if (!fit) continue;
    try {
      return {
        target,
        fit,
        webp: await renderFrame(await download(sources, fit.frame.imageUrl), fit),
      };
    } catch (e) {
      console.warn(`photo ${fit.frame.source} ${fit.frame.sourceId}: ${(e as Error).message}`);
    }
  }
  return null;
};

const mapLimit = async <T, R>(
  items: T[],
  limit: number,
  fn: (item: T) => Promise<R>,
): Promise<R[]> => {
  const out: R[] = new Array(items.length);
  let next = 0;
  const worker = async (): Promise<void> => {
    while (next < items.length) {
      const i = next++;
      out[i] = await fn(items[i] as T);
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return out;
};

interface LayerCoverage {
  layer: TargetLayer;
  targets: number;
  mapillary: number;
  panoramax: number;
  none: number;
  /** Not looked up, or found after the budget was full. */
  skipped: number;
}

type Outcome = Frame["source"] | "none" | "skipped";

/** The photos kept so far, and their image ids (one image never serves two targets). */
interface Kept {
  photos: Photo[];
  ids: Set<string>;
  budget: number;
}

/**
 * Looks `items` up in chunks, keeping photos in item order until the budget is full, so the
 * same answers always fill the same pack. Returns what each item gave.
 */
const fill = async <T>(
  items: T[],
  look: (item: T) => Promise<Photo | null>,
  kept: Kept,
): Promise<Outcome[]> => {
  const outcomes: Outcome[] = [];
  for (let i = 0; i < items.length && kept.photos.length < kept.budget; i += PhotoConfig.chunk) {
    const chunk = items.slice(i, i + PhotoConfig.chunk);
    for (const photo of await mapLimit(chunk, PhotoConfig.concurrency, look)) {
      const id = photo && imageId(photo.fit.frame);
      if (kept.photos.length >= kept.budget) outcomes.push("skipped");
      else if (!photo || !id || kept.ids.has(id)) outcomes.push("none");
      else {
        kept.photos.push(photo);
        kept.ids.add(id);
        outcomes.push(photo.fit.frame.source);
      }
    }
  }
  while (outcomes.length < items.length) outcomes.push("skipped");
  return outcomes;
};

const tally = (layer: TargetLayer, outcomes: Outcome[]): LayerCoverage => {
  const count = (o: Outcome): number => outcomes.filter((x) => x === o).length;
  return {
    layer,
    targets: outcomes.length,
    mapillary: count("mapillary"),
    panoramax: count("panoramax"),
    none: count("none"),
    skipped: count("skipped"),
  };
};

/** Each street's approaches in turn until one has a photo. */
const firstOf =
  (look: (t: Target) => Promise<Photo | null>) =>
  async (targets: Target[]): Promise<Photo | null> => {
    for (const t of targets) {
      const photo = await look(t);
      if (photo) return photo;
    }
    return null;
  };

const imageId = (frame: Frame): string =>
  `${frame.source === "mapillary" ? "m" : "p"}${frame.sourceId}`;

const writePhotoPack = (
  file: string,
  meta: { city: string; version: string; generatedAt: string },
  photos: Photo[],
): void => {
  rmSync(file, { force: true });
  const db = new Database(file);
  try {
    db.exec(PHOTO_DDL);
    const putMeta = db.prepare("INSERT INTO meta (key, value) VALUES (?, ?)");
    putMeta.run("format_version", String(PhotoConfig.formatVersion));
    putMeta.run("city", meta.city);
    putMeta.run("version", meta.version);
    putMeta.run("generated_at", meta.generatedAt);
    const put = db.prepare(
      `INSERT INTO scene_image VALUES
       (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    );
    db.transaction(() => {
      for (const { target, fit, webp } of photos) {
        const f = fit.frame;
        put.run(
          imageId(f),
          target.junctionNode,
          target.approachNode,
          f.at.lat,
          f.at.lon,
          Math.round((f.pano ? fit.travel : f.compass) * 10) / 10,
          Math.round(fit.distanceM * 10) / 10,
          f.capturedAt,
          f.source,
          f.licence,
          f.author,
          f.link,
          PhotoConfig.width,
          PhotoConfig.height,
          webp,
        );
      }
    })();
  } finally {
    db.close();
  }
};

export interface PhotosManifest {
  format_version: number;
  city: string;
  version: string;
  file: string;
  sha256: string;
  size: number;
  count: number;
  generated_at: string;
}

const coverageReport = (city: string, version: string, layers: LayerCoverage[]): string => {
  const rows = layers.map(
    (c) =>
      `| ${c.layer} | ${c.targets} | ${c.mapillary} | ${c.panoramax} | ${c.none} | ${c.skipped} |`,
  );
  return [
    `# Photo coverage: ${city} ${version}`,
    "",
    "Targets per layer (for `street`: tier A and B streets without a photo after the first layer).",
    "",
    "| Layer | Targets | Mapillary | Panoramax | None | Over budget |",
    "| --- | ---: | ---: | ---: | ---: | ---: |",
    ...rows,
    "",
  ].join("\n");
};

/** Gunzips the city's published pack into a temp dir; format 5 or later (junction items). */
const openPublishedPack = (
  city: string,
  packs: string,
): { db: Database.Database; done: () => void } => {
  const manifest = readManifest(join(packs, city, "manifest.json"));
  if (manifest.format_version < 5) {
    throw new Error(
      `${city}: the published pack is format ${manifest.format_version}, photos need 5`,
    );
  }
  const dir = mkdtempSync(join(tmpdir(), "pindoro-photos-"));
  const file = join(dir, "pack.sqlite");
  writeFileSync(file, gunzipSync(readFileSync(join(packs, city, manifest.file))));
  const db = new Database(file, { readonly: true });
  return {
    db,
    done: (): void => {
      db.close();
      rmSync(dir, { recursive: true, force: true });
    },
  };
};

/** Deletes all but the `keep` newest photo packs of `city` in `dir` (versions sort lexically). */
const pruneOld = (dir: string, city: string, keep: number): void => {
  const old = readdirSync(dir)
    .filter((f) => f.startsWith(`${city}-photos-`) && f.endsWith(".sqlite"))
    .sort()
    .reverse()
    .slice(keep);
  for (const f of old) rmSync(join(dir, f));
};

/** Copies the photo pack into PACKS_DIR, `photos.json` last; keeps the previous file. */
const publishPhotos = (
  city: string,
  packs: string,
  built: string,
  manifest: PhotosManifest,
): void => {
  const dest = join(packs, city);
  replaceAtomically(join(dest, manifest.file), (tmp) => copyFileSync(built, tmp));
  replaceAtomically(join(dest, "photos.json"), (tmp) => writeJson(tmp, manifest));
  pruneOld(dest, city, PhotoConfig.keptVersions);
};

export interface PhotoOptions extends PhotoSources {
  now?: Date;
  budget?: number;
  /** PACKS_DIR and the build dir, overridden in tests. */
  packsDir?: string;
  outDir?: string;
}

export const photoSourcesFromEnv = (): PhotoSources => {
  const mapillaryToken = process.env.MAPILLARY_TOKEN || undefined;
  const panoramaxUrl = process.env.PANORAMAX_URL || undefined;
  if (!mapillaryToken && !panoramaxUrl) {
    throw new Error("set MAPILLARY_TOKEN (and optionally PANORAMAX_URL) to build a photo pack");
  }
  return { fetch, mapillaryToken, panoramaxUrl };
};

/**
 * Builds the city's photo pack against its published pack, writes the coverage report and
 * publishes it (docs/pack-format.md, photo pack).
 */
export const photos = async (city: string, o: PhotoOptions): Promise<PhotosManifest> => {
  const packs = o.packsDir ?? packsDir();
  const out = o.outDir ?? buildDir(city);
  const budget = o.budget ?? PhotoConfig.budget;
  const now = o.now ?? new Date();
  const pack = openPublishedPack(city, packs);
  let plan: TargetPlan;
  try {
    plan = planTargets(pack.db);
  } finally {
    pack.done();
  }
  const kept: Kept = { photos: [], ids: new Set(), budget };
  const looked = new Set<Target>();
  const look = (t: Target): Promise<Photo | null> => {
    looked.add(t);
    return lookUp(o, t);
  };
  const primary = await fill(plan.primary, look, kept);
  const ofLayer = (layer: Target["layer"]): Outcome[] =>
    primary.filter((_, i) => plan.primary[i]?.layer === layer);
  const covered = new Set(kept.photos.map((p) => p.target.streetId));
  const uncovered = plan.byStreet.filter((ts) => !covered.has(ts[0]?.streetId ?? null));
  const streets = await fill(uncovered, firstOf(look), kept);
  const district = plan.district.filter((t) => !looked.has(t));
  const coverage = [
    tally("skeleton", ofLayer("skeleton")),
    tally("gateway", ofLayer("gateway")),
    tally("street", streets),
    tally("district", await fill(district, look, kept)),
  ];
  const found = kept.photos;
  const version = packVersion(now);
  const report = coverageReport(city, version, coverage);
  mkdirSync(out, { recursive: true });
  writeFileSync(join(out, "photo-coverage.md"), report);
  console.log(report);
  if (found.length === 0) throw new Error(`${city}: no photo fits any target; nothing published`);

  const file = `${city}-photos-${version}.sqlite`;
  const built = join(out, file);
  writePhotoPack(built, { city, version, generatedAt: isoSeconds(now) }, found);
  const manifest: PhotosManifest = {
    format_version: PhotoConfig.formatVersion,
    city,
    version,
    file,
    sha256: createHash("sha256").update(readFileSync(built)).digest("hex"),
    size: statSync(built).size,
    count: found.length,
    generated_at: isoSeconds(now),
  };
  writeJson(join(out, "photos.json"), manifest);
  publishPhotos(city, packs, built, manifest);
  pruneOld(out, city, 1);
  console.log(`published ${found.length} photos (${manifest.size} bytes) -> ${join(packs, city)}`);
  return manifest;
};
