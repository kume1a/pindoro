import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import type { FastifyPluginAsyncTypebox } from "@fastify/type-provider-typebox";
import type { FastifyBaseLogger } from "fastify";
import type { Static, TSchema } from "typebox";
import { Value } from "typebox/value";
import { type AppRelease, Catalog, Manifest, PhotosManifest } from "./catalog.schemas.ts";

const isMissing = (err: unknown): boolean => (err as NodeJS.ErrnoException).code === "ENOENT";

const listDirs = async (dir: string): Promise<string[]> => {
  try {
    const entries = await readdir(dir, { withFileTypes: true });
    return entries.filter((e) => e.isDirectory()).map((e) => e.name);
  } catch (err) {
    if (isMissing(err)) return [];
    throw err;
  }
};

/**
 * A JSON file of a pack dir checked against `schema`, or undefined (logged with the reason) when it
 * is unreadable or invalid. A missing file is logged only when `required`.
 */
const readChecked = async <S extends TSchema>(
  schema: S,
  path: string,
  log: FastifyBaseLogger,
  required: boolean,
): Promise<Static<S> | undefined> => {
  let json: unknown;
  try {
    json = JSON.parse(await readFile(path, "utf8"));
  } catch (err) {
    if (required || !isMissing(err)) log.warn({ path, err }, "skipping an unreadable pack file");
    return undefined;
  }
  if (Value.Check(schema, json)) return json;
  const [error] = Value.Errors(schema, json);
  log.warn({ path, error }, "skipping an invalid pack file");
  return undefined;
};

interface CityPacks {
  manifest: Manifest;
  photos?: PhotosManifest;
}

const readCities = async (dir: string, log: FastifyBaseLogger): Promise<CityPacks[]> => {
  const names = (await listDirs(dir)).sort();
  const cities = await Promise.all(
    names.map(async (name): Promise<CityPacks | undefined> => {
      const manifest = await readChecked(Manifest, join(dir, name, "manifest.json"), log, true);
      if (!manifest) return undefined;
      const photos = await readChecked(PhotosManifest, join(dir, name, "photos.json"), log, false);
      return { manifest, photos };
    }),
  );
  return cities.filter((c) => c !== undefined);
};

export const catalogRoutes: FastifyPluginAsyncTypebox<{
  packsDir: string;
  packsPublicUrl: string;
  app?: AppRelease;
}> = async (app, { packsDir, packsPublicUrl, app: release }) => {
  const base = packsPublicUrl.replace(/\/+$/, "");
  app.get(
    "/v1/catalog",
    { schema: { tags: ["catalog"], response: { 200: Catalog } } },
    async (req, reply) => {
      const cities = await readCities(packsDir, req.log);
      reply.header("cache-control", "public, max-age=60");
      return {
        app: release,
        cities: cities.map(({ manifest: m, photos: p }) => ({
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
          photos: p && {
            format_version: p.format_version,
            version: p.version,
            url: `${base}/${m.city}/${p.file}`,
            sha256: p.sha256,
            size: p.size,
            count: p.count,
          },
        })),
      };
    },
  );
};
