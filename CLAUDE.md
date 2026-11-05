# Pindoro (პინდორო)

Mobile game for learning a city's streets: the player sees a street name, drops a pin on an
**unlabelled** map and is scored by the distance to the real street. First city: Tbilisi.

## Repo map

| Path                      | What                                                                        |
| ------------------------- | --------------------------------------------------------------------------- |
| `apps/mobile`             | Flutter app (Android + iOS), offline-first, Drift progress DB, MapLibre map |
| `apps/api`                | `@pindoro/api` Fastify 5 + Drizzle + PostGIS (health, catalog)              |
| `packages/pindoro_core`   | Pure Dart: geometry, scoring, levels, question selection, pack models       |
| `packages/pindoro_design` | Flutter design system: tokens → generated Dart, theme, widgets, FiraGO font |
| `packages/geo`            | `@pindoro/geo`: TS twin of pindoro_core geometry + scoring + levels         |
| `pipeline`                | `@pindoro/pipeline`: OSM → PostGIS → city packs; tiles + map styles         |
| `data/cities/<city>`      | `city.yaml`, curated neighbourhoods, `identity.json` (stable street ids)    |
| `shared/fixtures`         | Golden vectors used by BOTH Dart and TS tests                               |
| `shared/openapi`          | `openapi.json` exported from the API                                        |
| `infra`                   | Docker Compose (dev + prod), Caddyfile, `tiles/`, `backups/`                |
| `docs`                    | ADRs, `pack-format.md`, `deploy.md`, `design/`, `TODO.md`                   |

## Architecture

Offline-first app + static, versioned SQLite city packs + self-hosted Fastify/PostGIS/Martin behind
a Cloudflare Tunnel, all in Docker Compose on one Ubuntu server. No Python anywhere, no paid cloud,
no S3/R2 (packs are static files served by Caddy). See `docs/adr/0001-architecture.md`.

## Golden rules

- **Design values only from** `packages/pindoro_design/tokens/tokens.json` and `docs/design/*.md`.
  Edit tokens, then `just gen`; never hand-edit generated code.
- **Never uppercase UI strings.** FiraGO everywhere, tabular figures for numbers.
- **Scoring constants live only in** pindoro_core `ScoringConfig` and `@pindoro/geo`
  `ScoringConfig`, and they must match `shared/fixtures/*.json`. Change all three together.
- **Stable street ids are sacred.** Never regenerate or hand-edit `identity.json` ids; the pipeline
  matches, retires and adds — progress in the app references these ids.
- **Every map shows OSM attribution** ("© OpenStreetMap contributors, Protomaps").
- **Never use public OSM tile servers or the public Overpass API** (app, CI or production).
- Map colours: yellow = truth, cobalt = you, ink = measurement.

## Commands (`just --list`)

| Command             | Does                                                                 |
| ------------------- | -------------------------------------------------------------------- |
| `just setup`        | `pnpm install` + `melos bootstrap`                                   |
| `just gen`          | Regenerate design tokens and Drift code                              |
| `just tokens-check` | Regenerate tokens and fail on a diff                                 |
| `just lint`         | Biome, tsc, dart format, flutter analyze                             |
| `just test`         | Melos tests, geo + API tests, pipeline tests in the pipeline image   |
| `just dev`          | PostGIS, API (tsx watch), Martin, packs server                       |
| `just fixture`      | Fetch OSM, build + validate the Vake fixture pack bundled in the app |
| `just pack CITY`    | Fetch, build, validate and publish a full city pack                  |
| `just tiles`        | Georgia PMTiles extract + regenerate the app map styles              |
| `just openapi`      | Write `shared/openapi/openapi.json`                                  |
| `just run-mobile`   | `flutter run` in `apps/mobile` (args pass through)                   |
| `just deploy`       | On the server: `git pull` + prod compose up                          |

On Windows run `just` from Git Bash. Dev PostGIS listens on host port 5433.

## Definition of done

- `just lint` and `just test` green; `just tokens-check` clean.
- Both scoring implementations pass the shared vectors when either changes.
- API route changes → `just openapi` committed. Pack format changes → `docs/pack-format.md`,
  pipeline export, Dart pack models and `format_version` updated together.
- New UI uses `pindoro_design` widgets and tokens only; no uppercase strings; maps keep attribution.
- Remaining work and placeholders are tracked in `docs/TODO.md`.
