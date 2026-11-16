# Pindoro

Mobile game for learning a city's streets: the player sees a street name, drops a pin on an
**unlabelled** map and is scored by the distance to the real street. First city: Tbilisi.

## Repo map

| Path                        | What                                                                                |
| --------------------------- | ----------------------------------------------------------------------------------- |
| `apps/mobile`               | Flutter app (Android + iOS), offline-first, Drift progress DB, MapLibre map         |
| `apps/api`                  | `@pindoro/api` Fastify 5, Drizzle, PostGIS (health, catalog, accounts)              |
| `packages/pindoro_core`     | Pure Dart: geometry, scoring, question selection, streaks, pack models              |
| `packages/pindoro_learning` | Pure Dart v3 learning: FSRS-6, grading, session planner, curriculum, stats          |
| `packages/pindoro_design`   | Flutter design system: tokens → generated Dart, theme, widgets, FiraGO font         |
| `packages/geo`              | `@pindoro/geo`: TS twin of pindoro_core geometry + scoring                          |
| `apps/pipeline`             | `@pindoro/pipeline`: OSM → PostGIS → city packs; tiles + map styles                 |
| `data/cities/<city>`        | `city.yaml`, curated neighbourhoods, `identity.json` (seed of the street ids)       |
| `shared/fixtures`           | Golden vectors used by BOTH Dart and TS tests                                       |
| `shared/openapi`            | `openapi.json` exported from the API                                                |
| `tools`                     | One-off generators run in Docker (e.g. `fsrs-vectors`), never in CI                 |
| `infra`                     | Docker Compose (dev + prod), Caddyfile, `tiles/`, `backups/`                        |
| `docs`                      | ADRs, `pack-format.md`, `deploy.md`, `design/`, `learning/`, `research/`, `TODO.md` |

## Design and planning on claude.ai

Research, features and design happen on claude.ai; coding happens here. Read them with the Artifact
tool (`action: "read"`, `path` for one file) and the docs with the Claude Docs tools. Private links:

| Artifact                                                                               | Holds                                                                                 |
| -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| [Pindoro design system](https://claude.ai/artifact/5hFQnWQ3hn8o7G4Fjy6y7K)             | `project/tokens.json`, `README.md`, `v1-screens.md`, `flutter-handoff.md`, components |
| [Pindoro screens: MVP and releases](https://claude.ai/artifact/Q2dLJn2NTaWESxWgYy9EGb) | Design canvas, one `project/*.dc.html` per screen (MVP, R2–R5, stress tests)          |
| [Learning Every Tbilisi Route](https://claude.ai/artifact/6W921EaUJ4rjA833Aq8XRi)      | Product plan doc                                                                      |

claude.ai is the source of truth for design; pull changes in by copying its files verbatim
(`docs/design/README.md` lists which), then `just gen`. Where it conflicts with this file (e.g.
CARTO / `flutter_map` vs our self-hosted Protomaps + MapLibre), this file wins.

## Architecture

Offline-first app + static, versioned SQLite city packs + self-hosted Fastify/PostGIS/Martin behind
a Cloudflare Tunnel, all in Docker Compose on one Ubuntu server. No Python in the product (one-off
generators in `tools/` run only in Docker), no paid cloud, no S3/R2 (packs are static files served
by Caddy). See `docs/adr/0001-architecture.md`.

**No App Store or Play Store release is planned.** The app is sideloaded to friends (an Android APK
from `just release apk`, an iOS IPA through SideStore from the iOS release workflow), so store-only work is parked in `docs/TODO.md` and is
never a priority. The production server still matters: it serves packs, tiles and account backups.

## Golden rules

- **Design values only from** `packages/pindoro_design/tokens/` (`tokens.json` from claude.ai,
  app-only `app.json`) and `docs/design/*.md`. Change tokens, then `just gen`; never hand-edit
  generated code.
- **Never uppercase UI strings.** FiraGO everywhere, tabular figures for numbers.
- **Scoring constants live only in** pindoro_core `ScoringConfig` and `@pindoro/geo`
  `ScoringConfig`, and they must match `shared/fixtures/*.json`. Change all three together.
  The v3 rating rules (FSRS ratings, response times, unlocks) live only in pindoro_learning
  `constants.dart`, which references `ScoringConfig` for distances instead of copying them.
- **Stable street ids are sacred.** Never regenerate or hand-edit `identity.json` ids; the pipeline
  matches, retires and adds — progress in the app references these ids. The live ids sit on the
  server next to the packs (`docs/deploy.md` § 5); `data/cities` only seeds a new city.
- **Every map shows OSM attribution** ("© OpenStreetMap contributors, Protomaps").
- **Never use public OSM tile servers or the public Overpass API** (app, CI or production).
- Map colours: yellow = truth, cobalt = you, ink = measurement.

## Commands (`just --list`)

| Command             | Does                                                                 |
| ------------------- | -------------------------------------------------------------------- |
| `just setup`        | `pnpm install` + `flutter pub get`, then `just gen`                  |
| `just gen`          | Generate tokens, l10n and Drift code (gitignored, never committed)   |
| `just gen-check`    | `gen`, then fail if it needed an uncommitted source (CI)             |
| `just api-check`    | Regenerate `openapi.json` + Drizzle migrations, fail on a diff (CI)  |
| `just goldens`      | Regenerate design goldens on Linux (pinned Flutter, as CI)           |
| `just branding`     | App icon + splash from `apps/mobile/assets/branding` (design assets) |
| `just lint`         | Biome, tsc, dart format, flutter analyze                             |
| `just format`       | Biome fixes + dart format, in place                                  |
| `just test`         | `test-dart`, geo + API tests, pipeline tests in the pipeline image   |
| `just test-dart`    | pindoro_core, pindoro_learning, pindoro_design and mobile tests      |
| `just fsrs-vectors` | Regenerate `shared/fixtures/fsrs_vectors.json` with py-fsrs (Docker) |
| `just dev`          | PostGIS, API (tsx watch), Martin, packs server                       |
| `just fixture H`    | Vake fixture pack bundled in the app, on the street ids live at `H`  |
| `just pack CITY`    | Fetch, build, validate and publish a full city pack                  |
| `just tiles`        | Georgia PMTiles extract + regenerate the app map styles              |
| `just openapi`      | Write `shared/openapi/openapi.json`                                  |
| `just run-mobile`   | `flutter run` in `apps/mobile` (args pass through)                   |
| `just release T H`  | Sideload build (`apk`) against the server at public host `H`         |

On Windows `just` works from PowerShell or Git Bash: recipes run in Git for Windows' `sh`
(`justfile` `windows-shell`). Dev PostGIS listens on host port 5433.

## Definition of done

- `just lint` and `just test` green; `just gen-check` and `just api-check` clean.
- Both scoring implementations pass the shared vectors when either changes.
- API route changes → `just openapi` committed; schema changes → `pnpm --filter @pindoro/api
  db:generate` committed. Pack format changes → `docs/pack-format.md`,
  pipeline export, Dart pack models and `format_version` updated together.
- New UI uses `pindoro_design` widgets and tokens only; no uppercase strings; maps keep attribution.
- Visual changes to design widgets → `just goldens` and commit the PNGs (goldens are Linux-only).
- Remaining work and placeholders are tracked in `docs/TODO.md`.

## v3 learning system (read before touching learning, scoring, sessions or progress)

- Spec: `docs/learning/SPEC.md` (decisions and numbers; §16 records the decisions taken where the
  rest of the spec is silent). Plan: `docs/learning/PLAN.md` (do steps in order). Screens:
  `docs/design/v3-screens.md`; board markup copies in `docs/design/v3-boards/` (reference only, not
  app code). Research behind the spec: `docs/research/`.
- Design canvas: https://claude.ai/artifact/Q2dLJn2NTaWESxWgYy9EGb (page "v3 · Learn the whole
  city"). Design system: https://claude.ai/artifact/5hFQnWQ3hn8o7G4Fjy6y7K. If you can open these
  links, prefer them over the copies; otherwise use the copies. New icons and components are added
  on claude.ai first, then copied in.
- All learning logic goes in `packages/pindoro_learning`: pure Dart, no Flutter imports, no I/O, no
  `DateTime.now()` (inject the clock), seeded randomness. The app only stores and displays.
- Every tunable number lives in `packages/pindoro_learning/lib/src/constants.dart` and matches SPEC
  §13. Never inline a threshold elsewhere.
- Write tests first for scheduler, grader, planner, curriculum and recital grading. FSRS must match
  `shared/fixtures/fsrs_vectors.json` to 1e-4 (`just fsrs-vectors` regenerates it).
- `review_log` is append-only. Never delete or rewrite rows; migrations add columns only.
- Map colours: yellow = the truth, cobalt = you, ink = measurement. Labels on learning maps show only
  streets the player already knows. Never show the answer street before Confirm.
- No XP, levels or leagues in new code. Tier visuals (Perfect, Great, Close, Miss) stay as feedback.
- Google Street View: deep link to the Google Maps app only. No Maps API keys, no cached Google
  imagery.
- If SPEC and a board disagree, follow SPEC and note the mismatch in the PR description. If SPEC is
  silent, ask before inventing behaviour.
