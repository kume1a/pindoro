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
  `PACKS_PUBLIC_URL`, `SIGNUP_LIMIT` (new accounts per client IP per hour, default 10).
- `src/app.ts` – `buildApp(config, {now})`; registers sensible, swagger (+ swagger-ui at `/docs`
  outside production), `@fastify/rate-limit` (routes opt in with `config.rateLimit`) and one
  plugin per module. `now` is the clock backups read (tests move it).
  Closing the app ends the DB pool.
- `src/modules/<module>/` – one vertical slice per feature, registered in `app.ts` as a Fastify
  plugin (its hooks and decorators stay private to it): `<module>.routes.ts` (HTTP),
  `<module>.schemas.ts` (TypeBox contract, when the module has more than a route-local schema), and
  a `<module>.service.ts` only once logic outgrows the handler. Modules never import each other;
  shared infrastructure lives in `src/db/` and `src/http.ts` (bearer token, client IP, per-token
  rate limit, token hashing, the `Problem` schema). Today: `health` (`GET /health`, DB + PostGIS
  check, 503 when down), `catalog` (`GET /v1/catalog`) and `accounts` (below).
- `src/db/schema.ts` – `account`.
  City data never lives here: packs are static files from the pipeline. PostGIS functions only
  through drizzle `sql```.
- `drizzle/` – migrations. `0000_postgis.sql` is custom (`CREATE EXTENSION postgis`) and must stay
  first. Never edit an applied migration; add a new one with `db:generate`
  (or `drizzle-kit generate --custom --name <x>` for hand-written SQL).

## Pack contract

`/v1/catalog` reads `<PACKS_DIR>/*/manifest.json` (written by `pipeline publish`, format in
`docs/pack-format.md`) and returns absolute URLs `PACKS_PUBLIC_URL/<city>/<file>`. Invalid or
missing manifests are skipped with a warning. The API never serves pack files itself; Caddy does.

## Accounts

Optional username + password accounts that keep one progress backup each (the app's SQLite file,
gzipped, in `account.backup`; the nightly `pg_dump` covers it).
Username, password and recovery-code rules live in `accounts.rules.ts`,
twinned with pindoro_core `progress/account.dart` through `shared/fixtures/account_vectors.json`.
Passwords are salted `scrypt` (node:crypto; an unknown username still costs one, so timing hides
which exist); tokens and recovery codes are stored as sha256. One `toSession` mapper builds every
`{token, account, backupAt, recoveryCode?}` answer.

- `POST /v1/accounts {username, password}`: 201 with a one-time `recoveryCode` (409 when taken;
  `SIGNUP_LIMIT` per IP an hour).
- `POST /v1/sessions` and `POST /v1/accounts/reset {username, recoveryCode, password}` (which also
  replaces the code): 10 a minute per IP plus 10 per 15 minutes per username from anywhere
  (`createRateLimit`, checked once the body is parsed). Both issue a new token in the same
  `UPDATE … RETURNING backup_at`, so the phone signed in before gets 401: one phone at a time.
- `PUT /v1/accounts/me/password {password, newPassword}` (403 for a wrong current password),
  `DELETE /v1/sessions/me` (sign out: the token dies) and `DELETE /v1/accounts/me` (account and
  backup gone): 30 a minute per token.
- `PUT /v1/accounts/me/backup` takes `application/octet-stream` (gzip only, at most 5 MiB); a
  `preParsing` hook turns a dead token away before the body is read, and the save itself is
  conditional on the token. `GET` returns it (404 before the first). Both 30 a minute per address.

`clientIp` counts an IPv6 client as its /64. The root error handler logs a 5xx by its cause only
(Drizzle puts a failed query's parameters, password hashes and backups included, in its message).

## Rules

- Response shapes are TypeBox schemas on the route; after changing one, run `openapi` and commit
  `shared/openapi/openapi.json`.
- Tests use `TEST_DATABASE_URL` (default `postgres://pindoro:pindoro@localhost:5433/pindoro_test`);
  CI provides a PostGIS service container. Test files run one at a time (`vitest.config.ts`): they
  share the database.
- OSM-derived data (city/district/street) is ODbL; anything served from it keeps the
  "© OpenStreetMap contributors" attribution.
