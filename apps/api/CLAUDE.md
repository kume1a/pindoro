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
  `PACKS_PUBLIC_URL`, `SIGNUP_LIMIT` (new league players, and new accounts, per client IP per
  hour, default 10).
- `src/app.ts` – `buildApp(config, {now})`; registers sensible, swagger (+ swagger-ui at `/docs`
  outside production), `@fastify/rate-limit` (routes opt in with `config.rateLimit`) and one
  plugin per module. `now` is the clock of leagues and backups (tests move it across weeks).
  Closing the app ends the DB pool.
- `src/modules/<module>/` – one vertical slice per feature, registered in `app.ts` as a Fastify
  plugin (its hooks and decorators stay private to it): `<module>.routes.ts` (HTTP),
  `<module>.schemas.ts` (TypeBox contract, when the module has more than a route-local schema), and
  a `<module>.service.ts` only once logic outgrows the handler. Modules never import each other;
  shared infrastructure lives in `src/db/` and `src/http.ts` (bearer token, client IP, per-token
  rate limit, token hashing, the `Problem` schema). Today: `health` (`GET /health`, DB + PostGIS
  check, 503 when down), `catalog` (`GET /v1/catalog`), `leagues` and `accounts` (below).
- `src/db/schema.ts` – the leagues' tables `player`, `league`, `league_member`, and `account`.
  City data never lives here: packs are static files from the pipeline. PostGIS functions only
  through drizzle `sql```.
- `drizzle/` – migrations. `0000_postgis.sql` is custom (`CREATE EXTENSION postgis`) and must stay
  first. Never edit an applied migration; add a new one with `db:generate`
  (or `drizzle-kit generate --custom --name <x>` for hand-written SQL).

## Pack contract

`/v1/catalog` reads `<PACKS_DIR>/*/manifest.json` (written by `pipeline publish`, format in
`docs/pack-format.md`) and returns absolute URLs `PACKS_PUBLIC_URL/<city>/<file>`. Invalid or
missing manifests are skipped with a warning. The API never serves pack files itself; Caddy does.

## Leagues

Anonymous players and weekly leagues (`docs/specs/2026-11-10-r5-leagues-design.md`).
`POST /v1/players {name}` returns a player and a random token (only its sha256 is stored; the
route is rate-limited per `cf-connecting-ip`); `PATCH`/`DELETE /v1/players/me` and
`PUT /v1/league/me {week, xp}` take `Authorization: Bearer <token>` (PATCH and PUT: 30 a minute
per token). DELETE forgets the player: the name is blanked, the token dies and this week's place
goes (with its league, under the join lock, when that empties it), but past weeks keep the row so a finished week's ranks never shift. A PATCH or PUT that lands mid-leave re-checks the
player row (the leave locks it first) and answers 401. The PUT records the week's XP
(never lower, only for the current week), joins the newest league of the player's tier with room
(30 a league, under an advisory lock per week and tier) on the first XP, and returns the player's
league ranked (XP, then earliest join). Rules live in `leagues.rules.ts`: weeks start Monday 00:00
at UTC+4, ranks 1–5 move up and 26–30 down; the week and name rules match pindoro_core
`progress/league.dart` through `shared/fixtures/league_vectors.json`. Rollover is lazy: a player's
tier for a new week comes from their last league's result when they first sync that week.

## Accounts

Optional username + password accounts that keep one progress backup each (the app's SQLite file,
gzipped, in `account.backup`; the nightly `pg_dump` covers it). Not league players: leaving Leagues
never touches an account. `POST /v1/accounts {username, password}` (409 when taken; usernames are
trimmed and lowercased, `^[a-z0-9._-]{3,24}$`, passwords 8–200; `SIGNUP_LIMIT` per IP an hour) and
`POST /v1/sessions` (10 a minute per IP) return `{token, account, backupAt}`. Passwords are salted
`scrypt` (node:crypto), tokens sha256 like the leagues'. A sign-in issues a new token, so the phone
signed in before gets 401: one phone at a time. `PUT /v1/accounts/me/backup` takes
`application/octet-stream` (gzip only, at most 10 MiB) and `GET` returns it (404 before the first);
both 30 a minute per token. No password reset, sign-out or account delete.

## Rules

- Response shapes are TypeBox schemas on the route; after changing one, run `openapi` and commit
  `shared/openapi/openapi.json`.
- Tests use `TEST_DATABASE_URL` (default `postgres://pindoro:pindoro@localhost:5433/pindoro_test`);
  CI provides a PostGIS service container. Test files run one at a time (`vitest.config.ts`): they
  share the database.
- OSM-derived data (city/district/street) is ODbL; anything served from it keeps the
  "© OpenStreetMap contributors" attribution.
