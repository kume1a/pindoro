import { type Static, Type } from "typebox";

const Bbox = Type.Object({
  min_lat: Type.Number(),
  min_lon: Type.Number(),
  max_lat: Type.Number(),
  max_lon: Type.Number(),
});

// <PACKS_DIR>/<city>/manifest.json, written by `pipeline publish` (docs/pack-format.md).
export const Manifest = Type.Object({
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
export type Manifest = Static<typeof Manifest>;

const Pack = Type.Object({
  format_version: Type.Integer(),
  version: Type.String(),
  url: Type.String({ format: "uri" }),
  sha256: Type.String(),
  size: Type.Integer(),
  osm_timestamp: Type.String({ format: "date-time" }),
});

const AppRelease = Type.Object({
  build: Type.Integer({ minimum: 1 }),
  url: Type.String({ format: "uri" }),
});
export type AppRelease = Static<typeof AppRelease>;

export const Catalog = Type.Object({
  // The newest sideload build; older installs offer it (docs/deploy.md § 7).
  app: Type.Optional(AppRelease),
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
