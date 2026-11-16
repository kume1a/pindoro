import { mkdirSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { gzipSync } from "node:zlib";
import { encodePolyline6, type LatLng } from "@pindoro/geo";
import Database from "better-sqlite3";
import sharp from "sharp";
import { beforeAll, describe, expect, it } from "vitest";
import { writeJson } from "../src/io.ts";
import { PACK_DDL } from "../src/pack.ts";
import type { Frame } from "../src/photo-sources.ts";
import {
  bestFit,
  fitFrame,
  type PhotosManifest,
  photos,
  planTargets,
  reproject,
  type Target,
} from "../src/photos.ts";

const J = { lat: 41.7, lon: 44.8 };
const M_PER_DEG = (6_371_008.8 * Math.PI) / 180;
/** `n` metres north and `e` metres east of the junction. */
const at = (n: number, e = 0): LatLng => ({
  lat: J.lat + n / M_PER_DEG,
  lon: J.lon + e / (M_PER_DEG * Math.cos((J.lat * Math.PI) / 180)),
});

/**
 * Junction 1 (node 100) with arms 100 m long: from 2 (south, node 200, street sA tier A),
 * to 3 (west, node 300, sB tier B), from 4 (north, node 400, sC tier C), to 5 (east, node 500,
 * sB2 tier B). Edges 1–4 in that order; items make (1, e1) skeleton, (1, e3) gateway and the
 * other two district turns.
 */
const writeTestPack = (file: string): void => {
  const db = new Database(file);
  db.exec(PACK_DDL);
  const junction = db.prepare("INSERT INTO junction VALUES (?, ?, ?, ?)");
  for (const [id, node, p] of [
    [1, 100, at(0)],
    [2, 200, at(-100)],
    [3, 300, at(0, -100)],
    [4, 400, at(100)],
    [5, 500, at(0, 100)],
  ] as const) {
    junction.run(id, node, p.lat, p.lon);
  }
  const street = db.prepare(
    `INSERT INTO street VALUES (?, 'x', NULL, 'residential', 'medium', 100, 0, 0, 0, 0, 0, 0, '[]',
     ?, 0, 'L', NULL, NULL)`,
  );
  for (const [id, tier] of [
    ["sA", "A"],
    ["sB", "B"],
    ["sC", "C"],
    ["sB2", "B"],
  ]) {
    street.run(id, tier);
  }
  const edge = db.prepare("INSERT INTO road_edge VALUES (?, ?, ?, ?, 0, NULL, 100, ?)");
  edge.run(1, 2, 1, "sA", encodePolyline6([at(-100), at(0)]));
  edge.run(2, 1, 3, "sB", encodePolyline6([at(0), at(0, -100)]));
  edge.run(3, 4, 1, "sC", encodePolyline6([at(100), at(0)]));
  edge.run(4, 1, 5, "sB2", encodePolyline6([at(0), at(0, 100)]));
  const item = db.prepare(
    "INSERT INTO junction_item VALUES (1, ?, ?, ?, ?, NULL, NULL, NULL, NULL, NULL)",
  );
  item.run(1, 2, "skeleton", 1);
  item.run(1, 4, "district", 1);
  item.run(3, 1, "gateway_out", 2);
  item.run(2, 1, "district", 3);
  item.run(4, 1, "district", 4);
  const meta = db.prepare("INSERT INTO meta VALUES (?, ?)");
  meta.run("format_version", "5");
  db.close();
};

/** A pack dir with the test pack published for `city`. */
const publishTestPack = (packs: string, city: string): void => {
  const work = mkdtempSync(join(tmpdir(), "pindoro-photos-test-"));
  const file = join(work, "pack.sqlite");
  writeTestPack(file);
  mkdirSync(join(packs, city), { recursive: true });
  writeFileSync(join(packs, city, "pack.sqlite.gz"), gzipSync(readFileSync(file)));
  writeJson(join(packs, city, "manifest.json"), { format_version: 5, file: "pack.sqlite.gz" });
};

const openTestPack = (): Database.Database => {
  const file = join(mkdtempSync(join(tmpdir(), "pindoro-photos-test-")), "pack.sqlite");
  writeTestPack(file);
  return new Database(file, { readonly: true });
};

const frame = (p: LatLng, compass: number, more: Partial<Frame> = {}): Frame => ({
  source: "mapillary",
  sourceId: "1",
  at: p,
  compass,
  pano: false,
  capturedAt: null,
  licence: "CC BY-SA 4.0",
  author: "someone",
  link: null,
  imageUrl: "https://img.test/flat.jpg",
  ...more,
});

describe("planTargets", () => {
  it("orders skeleton and gateway approaches, then tier A/B streets, then district turns", () => {
    const plan = planTargets(openTestPack());
    const key = (t: Target): string => `${t.layer}:${t.approachEdge}`;
    // (1, e1) is both a skeleton and a district turn: it counts as skeleton.
    expect(plan.primary.map(key)).toEqual(["skeleton:1", "gateway:3"]);
    expect(plan.byStreet.map((ts) => ts.map(key))).toEqual([["district:2"], ["district:4"]]);
    expect(plan.district.map(key)).toEqual(["district:2", "district:4"]);
    const [skeleton] = plan.primary;
    expect(skeleton).toMatchObject({ junctionNode: 100, approachNode: 200, streetId: "sA" });
    // Oriented towards the junction: e2 runs 1 → 3, so its approach is reversed.
    expect(plan.district[0]?.line.at(-1)?.lon).toBeCloseTo(J.lon, 9);
    expect(plan.district[0]?.approachNode).toBe(300);
  });
});

describe("fitFrame", () => {
  const plan = (): Target => planTargets(openTestPack()).primary[0] as Target;

  it("keeps a flat photo 25–40 m before the junction looking along the approach", () => {
    const fit = fitFrame(plan(), frame(at(-30, 3), 10));
    expect(fit?.distanceM).toBeCloseTo(30, 0);
    expect(fit?.travel).toBeCloseTo(0, 3);
    expect(fit?.angleOff).toBeCloseTo(10, 3);
  });

  it("drops frames outside the band, off the road or looking elsewhere", () => {
    expect(fitFrame(plan(), frame(at(-60), 0))).toBeNull();
    expect(fitFrame(plan(), frame(at(-20), 0))).toBeNull();
    expect(fitFrame(plan(), frame(at(-30, 15), 0))).toBeNull();
    expect(fitFrame(plan(), frame(at(-30), 45))).toBeNull();
    expect(fitFrame(plan(), frame(at(-30), 340))).not.toBeNull();
  });

  it("keeps a panorama whatever its compass, and prefers it, then the newest", () => {
    const target = plan();
    expect(fitFrame(target, frame(at(-30), 135, { pano: true }))).not.toBeNull();
    const flat = frame(at(-30), 5, { sourceId: "flat" });
    const old = frame(at(-35), 90, { sourceId: "old", pano: true, capturedAt: "2020-01-01" });
    const recent = frame(at(-35), 90, { sourceId: "new", pano: true, capturedAt: "2025-01-01" });
    expect(bestFit(target, [flat, old, recent])?.frame.sourceId).toBe("new");
    expect(bestFit(target, [frame(at(-30), 20, { sourceId: "a" }), flat])?.frame.sourceId).toBe(
      "flat",
    );
    expect(bestFit(target, [frame(at(-80), 0)])).toBeNull();
  });
});

describe("reproject", () => {
  const grey = 100;
  /** 720 × 360 equirectangular, grey with a red column band 90° right of centre. */
  const pano = (): Buffer => {
    const src = Buffer.alloc(720 * 360 * 3, grey);
    for (let y = 0; y < 360; y++) {
      for (let x = 530; x <= 550; x++) {
        src.set([255, 0, 0], (y * 720 + x) * 3);
      }
    }
    return src;
  };
  const centre = (view: Buffer): number[] => {
    const i = (27 * 96 + 48) * 3;
    return [...view.subarray(i, i + 3)];
  };

  it("looks at the yaw asked, relative to the panorama's centre", () => {
    expect(centre(reproject(pano(), 720, 360, 3, 90, 96, 54))).toEqual([255, 0, 0]);
    expect(centre(reproject(pano(), 720, 360, 3, 0, 96, 54))).toEqual([grey, grey, grey]);
    expect(centre(reproject(pano(), 720, 360, 3, -270, 96, 54))).toEqual([255, 0, 0]);
  });
});

describe("photos", () => {
  let flat: Buffer;
  let panorama: Buffer;
  const uuid = "6b1f5a0e-1111-4c2d-9a8b-000000000001";

  beforeAll(async () => {
    const solid = (width: number, height: number): Promise<Buffer> =>
      sharp({ create: { width, height, channels: 3, background: { r: 90, g: 120, b: 150 } } })
        .jpeg()
        .toBuffer();
    flat = await solid(1600, 1000);
    panorama = await solid(1024, 512);
  });

  const mapillary = [
    {
      id: "11",
      computed_geometry: { type: "Point", coordinates: [at(-30, 1).lon, at(-30, 1).lat] },
      computed_compass_angle: 3,
      captured_at: Date.parse("2025-06-01T10:00:00Z"),
      creator: { username: "driver1" },
      is_pano: false,
      thumb_2048_url: "https://img.test/flat.jpg",
    },
    {
      id: "33",
      geometry: { type: "Point", coordinates: [at(0, -32).lon, at(0, -32).lat] },
      compass_angle: 0,
      creator: { username: "driver2" },
      is_pano: true,
      thumb_2048_url: "https://img.test/small.jpg",
      thumb_original_url: "https://img.test/pano.jpg",
    },
  ];
  const panoramax = [
    {
      id: "nc",
      geometry: { type: "Point", coordinates: [at(30).lon, at(30).lat] },
      properties: {
        datetime: "2026-01-01T00:00:00Z",
        license: "CC-BY-NC-SA-4.0",
        "view:azimuth": 180,
      },
      providers: [{ name: "me", roles: ["producer"] }],
      assets: { sd: { href: "https://img.test/flat.jpg" } },
    },
    {
      id: uuid,
      geometry: { type: "Point", coordinates: [at(30).lon, at(30).lat] },
      properties: {
        datetime: "2025-01-01T00:00:00Z",
        license: "CC-BY-SA-4.0",
        "view:azimuth": 178,
      },
      providers: [
        { name: "instance account", roles: ["producer"] },
        { name: "Nino", roles: ["producer"] },
      ],
      assets: { sd: { href: "https://img.test/flat.jpg" } },
    },
  ];

  const inBbox = (bbox: string, [lon, lat]: [number, number]): boolean => {
    const [minLon, minLat, maxLon, maxLat] = bbox.split(",").map(Number) as number[];
    return (
      lon >= (minLon ?? 0) && lon <= (maxLon ?? 0) && lat >= (minLat ?? 0) && lat <= (maxLat ?? 0)
    );
  };

  const fakeFetch = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = new URL(String(input));
    const bbox = url.searchParams.get("bbox") ?? "";
    if (url.hostname === "graph.mapillary.com") {
      expect(url.searchParams.has("access_token")).toBe(false);
      expect(new Headers(init?.headers).get("authorization")).toBe("OAuth test-token");
      const data = mapillary.filter((m) =>
        inBbox(bbox, (m.computed_geometry ?? m.geometry)?.coordinates as [number, number]),
      );
      return Response.json({ data });
    }
    if (url.hostname === "panoramax.test" && url.pathname === "/api/search") {
      const features = panoramax.filter((p) =>
        inBbox(bbox, p.geometry.coordinates as [number, number]),
      );
      return Response.json({ type: "FeatureCollection", features });
    }
    if (url.href === "https://img.test/flat.jpg") return new Response(flat);
    if (url.href === "https://img.test/pano.jpg") return new Response(panorama);
    return new Response("missing", { status: 404 });
  }) as typeof fetch;

  const run = (packs: string, now: Date, budget?: number): Promise<PhotosManifest> =>
    photos("testcity", {
      fetch: fakeFetch,
      mapillaryToken: "test-token",
      panoramaxUrl: "https://panoramax.test/",
      now,
      budget,
      packsDir: packs,
      outDir: join(packs, "out"),
    });

  it("builds and publishes the photo pack, Mapillary first, then Panoramax", async () => {
    const packs = mkdtempSync(join(tmpdir(), "pindoro-photos-packs-"));
    publishTestPack(packs, "testcity");
    const manifest = await run(packs, new Date("2026-11-16T10:15:00Z"));
    expect(manifest).toMatchObject({
      format_version: 1,
      city: "testcity",
      version: "20261116T101500Z",
      file: "testcity-photos-20261116T101500Z.sqlite",
      count: 3,
    });
    const published = join(packs, "testcity", manifest.file);
    expect(JSON.parse(readFileSync(join(packs, "testcity", "photos.json"), "utf8"))).toEqual(
      manifest,
    );
    const db = new Database(published, { readonly: true });
    const rows = db
      .prepare(
        `SELECT id, junction_node, approach_node, heading, round(distance_m) AS d, captured_at,
                source, licence, author, link, width, height
         FROM scene_image ORDER BY id`,
      )
      .all();
    expect(rows).toEqual([
      {
        id: "m11",
        junction_node: 100,
        approach_node: 200,
        heading: 3,
        d: 30,
        captured_at: "2025-06-01T10:00:00Z",
        source: "mapillary",
        licence: "CC BY-SA 4.0",
        author: "driver1",
        link: "https://www.mapillary.com/app/?pKey=11",
        width: 960,
        height: 540,
      },
      {
        id: "m33",
        junction_node: 100,
        approach_node: 300,
        heading: 90,
        d: 32,
        captured_at: null,
        source: "mapillary",
        licence: "CC BY-SA 4.0",
        author: "driver2",
        link: "https://www.mapillary.com/app/?pKey=33",
        width: 960,
        height: 540,
      },
      {
        id: `p${uuid}`,
        junction_node: 100,
        approach_node: 400,
        heading: 178,
        d: 30,
        captured_at: "2025-01-01T00:00:00Z",
        source: "panoramax",
        licence: "CC BY-SA 4.0",
        author: "Nino",
        link: null,
        width: 960,
        height: 540,
      },
    ]);
    const blob = db.prepare("SELECT webp FROM scene_image WHERE id = 'm33'").get() as {
      webp: Buffer;
    };
    expect(await sharp(blob.webp).metadata()).toMatchObject({
      format: "webp",
      width: 960,
      height: 540,
    });
    expect(db.prepare("SELECT value FROM meta WHERE key = 'format_version'").get()).toEqual({
      value: "1",
    });
    db.close();
    const coverage = readFileSync(join(packs, "out", "photo-coverage.md"), "utf8");
    expect(coverage).toContain("| skeleton | 1 | 1 | 0 | 0 | 0 |");
    expect(coverage).toContain("| gateway | 1 | 0 | 1 | 0 | 0 |");
    expect(coverage).toContain("| street | 2 | 1 | 0 | 1 | 0 |");
    expect(coverage).toContain("| district | 0 | 0 | 0 | 0 | 0 |");
  });

  it("publishes nothing when no photo fits", async () => {
    const packs = mkdtempSync(join(tmpdir(), "pindoro-photos-packs-"));
    publishTestPack(packs, "testcity");
    const empty = (async () => Response.json({ data: [] })) as typeof fetch;
    await expect(
      photos("testcity", {
        fetch: empty,
        mapillaryToken: "t",
        packsDir: packs,
        outDir: join(packs, "out"),
      }),
    ).rejects.toThrow(/nothing published/);
    expect(readdirSync(join(packs, "testcity"))).not.toContain("photos.json");
  });

  it("stops at the budget and keeps the two newest photo packs", async () => {
    const packs = mkdtempSync(join(tmpdir(), "pindoro-photos-packs-"));
    publishTestPack(packs, "testcity");
    for (const hour of ["10", "11", "12"]) {
      await run(packs, new Date(`2026-11-16T${hour}:00:00Z`), 1);
    }
    const files = readdirSync(join(packs, "testcity")).filter((f) => f.includes("-photos-"));
    expect(files.sort()).toEqual([
      "testcity-photos-20261116T110000Z.sqlite",
      "testcity-photos-20261116T120000Z.sqlite",
    ]);
    const coverage = readFileSync(join(packs, "out", "photo-coverage.md"), "utf8");
    expect(coverage).toContain("| gateway | 1 | 0 | 0 | 0 | 1 |");
    expect(coverage).toContain("| street | 2 | 0 | 0 | 0 | 2 |");
  });
});
