# pipeline (@pindoro/pipeline)

OSM → PostGIS → SQLite city packs. TypeScript CLI (tsx) driving osmium-tool, osm2pgsql (flex/Lua) and
SQL. Configured per city by `data/cities/<city>/city.yaml`. The pack contract is
`docs/pack-format.md` — change it there first, then `src/pack.ts` (`PACK_DDL`) and the app.

## Commands

Run in the pipeline image (osmium/osm2pgsql/pmtiles are not needed on the host for `tiles --styles-only`,
`validate` and `publish`):

```sh
docker compose -f infra/docker-compose.yml run --rm pipeline fetch tbilisi
docker compose -f infra/docker-compose.yml run --rm pipeline build tbilisi [--fixture]
docker compose -f infra/docker-compose.yml run --rm pipeline validate <pack.sqlite[.gz]>
docker compose -f infra/docker-compose.yml run --rm pipeline publish tbilisi
docker compose -f infra/docker-compose.yml run --rm pipeline tiles [--styles-only]
pnpm pipeline <cmd> …                         # same CLI on the host (needs the tools on PATH)
pnpm --filter @pindoro/pipeline test          # DB tests skip without osm2pgsql/osmium
```

Env: `DATABASE_URL` (default `postgres://pindoro:pindoro@localhost:5433/pindoro`), `PACKS_DIR`
(default `infra/packs`). Tests: `TEST_DATABASE_URL` (default `…:5433/pindoro_pipeline_test`);
`PINDORO_REQUIRE_OSM_TOOLS=1` turns the skip into a failure (CI).

Outputs: cache `pipeline/.cache/<city>/`, builds `pipeline/out/<city>/` (pack, `.gz`, `manifest.json`,
`identity-diff-<version>.json`), fixture `apps/mobile/assets/packs_fixture/<city>_<name>_fixture.sqlite`,
styles `apps/mobile/assets/map_styles/pindoro_{light,dark}.json`, tiles `infra/tiles/georgia.pmtiles`.

## Build steps

1. `osmium getid -r` the city relation → `osmium export` its polygon → `osmium extract --strategy=smart`
   (multipolygon + boundary relations kept complete).
2. `osm2pgsql --output=flex --style=osm2pgsql/pindoro.lua` into schema `osm`: `roads`, `boundaries`,
   `subareas` (parent → child, role subarea), `places`. Lua must run on osm2pgsql 1.8 and 1.11.
3. `sql/*.sql` in file-name order into schema `pipeline` (recreated each run; inputs in
   `pipeline.params` and `pipeline.neighbourhood_raw`, never string-templated):
   `10_roads` filter + normalise names → `20_streets` DBSCAN 30 m merge, road class, difficulty →
   `30_districts` city + subarea districts, fails on missing `expect_relations` →
   `40_neighbourhoods` curated GeoJSON → `50_street_district` (≥ 150 m or ≥ 30 %) →
   `60_simplify` 3 m pack geometry + midpoints.
4. `src/identity.ts`: stable UUIDs in `data/cities/<city>/identity.json` (same normalised name + way-id
   Jaccard ≥ 0.3, one-to-one, best first; unmatched → new id; vanished → `retired_at`). Always computed
   over the whole city, also for `--fixture`. **Stable street ids are sacred**: never regenerate or
   hand-edit identity.json; review the diff report instead.
5. `src/pack.ts`: better-sqlite3 pack (polyline6 via `@pindoro/geo`) → gzip → `manifest.json`.

## ODbL

Packs, the fixture and identity.json are Derivative Databases of OSM (ODbL 1.0), see
`data/LICENSE-ODbL.md`. Keep `meta.attribution`/`meta.license` in every pack. Never use public OSM tile
servers or the Overpass API; data comes from Geofabrik extracts and Protomaps builds only.
