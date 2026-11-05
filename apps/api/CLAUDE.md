# @pindoro/api

Fastify 5 + TypeBox type provider + Drizzle (postgres-js driver) on PostGIS 16. No build step:
Node 24 strips types natively (`node src/server.ts`), dev uses `tsx watch`. Relative imports carry
the `.ts` extension; only erasable TypeScript syntax (no enums, namespaces, parameter properties).

## Commands

```sh
pnpm --filter @pindoro/api dev          # tsx watch, needs PostGIS (just dev starts it on :5433)
pnpm --filter @pindoro/api test         # vitest + fastify.inject against a real PostGIS
pnpm --filter @pindoro/api typecheck
pnpm --filter @pindoro/api openapi      # writes shared/openapi/openapi.json (commit it)
pnpm --filter @pindoro/api db:generate  # drizzle-kit: schema.ts -> new SQL migration in drizzle/
pnpm --filter @pindoro/api db:migrate   # apply migrations (the server also does this on start)
docker build -f apps/api/Dockerfile .   # from the repo root
```

## Layout

- `src/config.ts` – env schema (TypeBox), validated at startup; dev defaults point at the compose
  PostGIS. Vars: `NODE_ENV`, `HOST`, `PORT`, `LOG_LEVEL`, `DATABASE_URL`, `PACKS_DIR`,
  `PACKS_PUBLIC_URL`.
- `src/app.ts` – `buildApp(config)`; registers sensible, swagger (+ swagger-ui at `/docs` outside
  production) and the route plugins. Closing the app ends the DB pool.
- `src/routes/` – `GET /health` (DB + PostGIS check, 503 when down), `GET /v1/catalog`.
- `src/db/schema.ts` – tables `city`, `district`, `street`, `street_district`, `pack`; geometry via
  a `customType` (`geometry(MultiPolygon|MultiLineString, 4326)`), PostGIS functions only through
  drizzle `sql```.
- `drizzle/` – migrations. `0000_postgis.sql` is custom (`CREATE EXTENSION postgis`) and must stay
  first. Never edit an applied migration; add a new one with `db:generate`
  (or `drizzle-kit generate --custom --name <x>` for hand-written SQL).

## Pack contract

`/v1/catalog` reads `<PACKS_DIR>/*/manifest.json` (written by `pipeline publish`, format in
`docs/pack-format.md`) and returns absolute URLs `PACKS_PUBLIC_URL/<city>/<file>`. Invalid or
missing manifests are skipped with a warning. The API never serves pack files itself; Caddy does.

## Rules

- Response shapes are TypeBox schemas on the route; after changing one, run `openapi` and commit
  `shared/openapi/openapi.json`.
- Tests use `TEST_DATABASE_URL` (default `postgres://pindoro:pindoro@localhost:5433/pindoro_test`);
  CI provides a PostGIS service container.
- OSM-derived data (city/district/street) is ODbL; anything served from it keeps the
  "© OpenStreetMap contributors" attribution.
