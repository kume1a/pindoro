# ADR 0001 — Architecture

- Status: accepted
- Date: 2026-11-05

## Context

Pindoro teaches a city's streets: the player sees a street name, drops a pin on an unlabelled map
and is scored by the distance to the real street. It must work offline on Android and iOS, start
with Tbilisi, and run on a single self-hosted Ubuntu server with no paid cloud services.

## Decision

1. **Offline-first Flutter app.** Gameplay never needs the network. Progress lives in a local
   Drift (SQLite) database with an immutable answer log (client UUIDv7 ids, ready for later sync).
2. **City data as static, versioned SQLite packs.** A pack holds the city, districts, streets
   (polyline6) and street↔district membership (`docs/pack-format.md`). Packs are immutable files
   served by Caddy with long-lived cache headers; `catalog.json` points to the current version.
   No S3/R2. (Amended 2026-11-12: `catalog.json` is gone; each city's `manifest.json` points to
   its current pack and the API's `/v1/catalog` lists them.)
3. **Self-hosted backend.** TypeScript on Node 24 LTS: Fastify 5 API, PostgreSQL 16 + PostGIS,
   Martin for vector tiles, Caddy as the host router, all in Docker Compose on one Ubuntu box,
   exposed only through a token-based Cloudflare Tunnel (no open inbound ports).
4. **Own map tiles.** A Protomaps (PMTiles) extract of Georgia served by Martin, styled from
   design tokens with every symbol layer removed (the map must not give away street names). The app
   and CI never call public OSM tile servers or the public Overpass API.
5. **OSM pipeline without Python.** osmium-tool cuts the city, osm2pgsql (flex output, Lua) loads
   it into PostGIS, ordered SQL steps do the geometry work, and a TypeScript CLI exports packs.
   Street ids are stable UUIDs persisted in `data/cities/<city>/identity.json`.
6. **One scoring truth, two languages.** Geometry, scoring and levels exist in Dart
   (`pindoro_core`) and TypeScript (`@pindoro/geo`); both must pass the same golden vectors in
   `shared/fixtures/`.
7. **Monorepo tooling.** Each language uses its own native workspace: a Dart pub workspace (root
   `pubspec.yaml`) and a pnpm workspace + Biome + Vitest + tsx. A root `justfile` is the single
   command entry point. Runnable things live in `apps/`, libraries in `packages/`. There is no
   monorepo framework. Turborepo only sees the JS half. The TS packages have no build step to
   cache. Nx and moon are too heavy for six packages. Melos was dropped once pub workspaces made
   its bootstrap redundant.

## Consequences

- The app is fully playable without a server once a pack is installed; the server only serves
  static packs, tiles and (later) sync/leaderboards.
- Changing a scoring constant means changing Dart, TypeScript and the shared vectors together.
- Packs are ODbL derivative databases: attribution in every map and in the pack metadata.
- One home server is a single point of failure; nightly `pg_dump` backups plus a second-disk copy
  and immutable packs/tiles (rebuildable from OSM) keep recovery simple.
