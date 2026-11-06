import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import type { FastifyPluginAsyncTypebox } from "@fastify/type-provider-typebox";
import type { FastifyBaseLogger } from "fastify";
import { type Static, Type } from "typebox";
import { Value } from "typebox/value";

const Bbox = Type.Object({
  min_lat: Type.Number(),
  min_lon: Type.Number(),
  max_lat: Type.Number(),
  max_lon: Type.Number(),
});

// <PACKS_DIR>/<city>/manifest.json, written by `pipeline publish` (docs/pack-format.md).
const Manifest = Type.Object({
  format_version: Type.Integer(),
  city: Type.String({ pattern: "^[a-z0-9-]+$" }),
  name_ka: Type.String(),
  name_en: Type.String(),
  version: Type.String(),
  file: Type.String({ pattern: "^[A-Za-z0-9._-]+$" }),
  sha256: Type.String({ pattern: "^[0-9a-f]{64}$" }),
  size: Type.Integer({ minimum: 0 }),
  osm_timestamp: Type.String(),
  bbox: Type.Optional(Bbox),
});
type Manifest = Static<typeof Manifest>;

const Pack = Type.Object({
  format_version: Type.Integer(),
  version: Type.String(),
  url: Type.String({ format: "uri" }),
  sha256: Type.String(),
  size: Type.Integer(),
  osm_timestamp: Type.String({ format: "date-time" }),
});

const Catalog = Type.Object({
  cities: Type.Array(
    Type.Object({
      id: Type.String(),
      name_ka: Type.String(),
      name_en: Type.String(),
      // Missing for packs published before the manifest carried it.
      bbox: Type.Optional(Bbox),
      pack: Pack,
    }),
  ),
});

const listDirs = async (dir: string): Promise<string[]> => {
  try {
    const entries = await readdir(dir, { withFileTypes: true });
    return entries.filter((e) => e.isDirectory()).map((e) => e.name);
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw err;
  }
};

const readManifests = async (dir: string, log: FastifyBaseLogger): Promise<Manifest[]> => {
  const manifests: Manifest[] = [];
  for (const name of (await listDirs(dir)).sort()) {
    const path = join(dir, name, "manifest.json");
    const json: unknown = await readFile(path, "utf8")
      .then(JSON.parse)
      .catch(() => undefined);
    if (Value.Check(Manifest, json)) manifests.push(json);
    else log.warn({ path }, "skipping pack dir without a valid manifest.json");
  }
  return manifests;
};

export const catalogRoutes: FastifyPluginAsyncTypebox<{
  packsDir: string;
  packsPublicUrl: string;
}> = async (app, { packsDir, packsPublicUrl }) => {
  const base = packsPublicUrl.replace(/\/+$/, "");
  app.get(
    "/v1/catalog",
    { schema: { tags: ["catalog"], response: { 200: Catalog } } },
    async (req, reply) => {
      const manifests = await readManifests(packsDir, req.log);
      reply.header("cache-control", "public, max-age=60");
      return {
        cities: manifests.map((m) => ({
          id: m.city,
          name_ka: m.name_ka,
          name_en: m.name_en,
          bbox: m.bbox,
          pack: {
            format_version: m.format_version,
            version: m.version,
            url: `${base}/${m.city}/${m.file}`,
            sha256: m.sha256,
            size: m.size,
            osm_timestamp: m.osm_timestamp,
          },
        })),
      };
    },
  );
};
