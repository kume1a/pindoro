import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import type { FastifyPluginAsyncTypebox } from "@fastify/type-provider-typebox";
import type { FastifyBaseLogger } from "fastify";
import { Value } from "typebox/value";
import { Catalog, Manifest } from "./catalog.schemas.ts";

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
