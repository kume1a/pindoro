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

/** A pack dir's manifest, or undefined (logged with the reason) when it is missing or invalid. */
const readManifest = async (
  path: string,
  log: FastifyBaseLogger,
): Promise<Manifest | undefined> => {
  let json: unknown;
  try {
    json = JSON.parse(await readFile(path, "utf8"));
  } catch (err) {
    log.warn({ path, err }, "skipping pack dir without a readable manifest.json");
    return undefined;
  }
  if (Value.Check(Manifest, json)) return json;
  const [error] = Value.Errors(Manifest, json);
  log.warn({ path, error }, "skipping pack dir with an invalid manifest.json");
  return undefined;
};

const readManifests = async (dir: string, log: FastifyBaseLogger): Promise<Manifest[]> => {
  const names = (await listDirs(dir)).sort();
  const manifests = await Promise.all(
    names.map((name) => readManifest(join(dir, name, "manifest.json"), log)),
  );
  return manifests.filter((m) => m !== undefined);
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
