# R5 · v2.1 — Leagues with anonymous accounts

- Date: 2026-11-10
- Status: implemented
- Builds on: R4e (`docs/specs/2026-11-10-r4e-finish-v2-design.md`)
- Source: `docs/design/v1-screens.md` § R5 · v2.1 Leagues; claude.ai screens canvas boards R5-01
  (League), R5-02 (Results), R5-03 (the Leagues tab); components `LeagueScreen`, `ResultsScreen`
  (`release=r5`); bundle classes `.pd-league-head`, `.pd-ladder`, `.pd-rank`, `.pd-avatar`,
  `.pd-zone`, `.pd-li.is-you`

## Goal

Friendly weekly competition: players are grouped into leagues of up to 30, ranked by this week's
XP; the top 5 move up a league and the bottom 5 move down. The design notes it "needs accounts and
sync (not designed yet)": this release adds anonymous accounts only. Sign-in and progress sync
across devices come later.

## Decisions

| Topic         | Decision                                                                                                                                                        |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Accounts      | Anonymous: the app registers with the API (`POST /v1/players`) and gets a player id and a secret token. No sign-in, no Apple/Google setup                       |
| What syncs    | Only this week's XP. All progress stays on the phone                                                                                                            |
| League name   | Typed by the player on the first open of the Leagues tab; Settings → League changes it. 2–20 characters after trimming: letters (any script), spaces, `. ' ’ -` |
| Scope         | Global: XP and levels are global already, so leagues are too                                                                                                    |
| Tiers         | Alley → Lane → Street → Avenue → Boulevard → Highway (0–5). New players start in Alley                                                                          |
| Week          | Monday 00:00 to Monday 00:00 Tbilisi time (fixed UTC+4; Georgia has no daylight saving). Keyed by the Monday's date (`2026-11-09`)                              |
| Joining       | The first sync of the week with XP > 0 joins the newest league of the player's tier with fewer than 30 members, or opens a new one. No XP, no league that week  |
| Ranking       | Week XP descending, then earliest join, then player id                                                                                                          |
| Moves         | Ranks 1–5 move up (not from Highway); ranks 26–30 move down (not from Alley): a league of 25 or fewer has no demotion zone                                      |
| Rollover      | Lazy: a player's tier for a new week comes from their last league's result, worked out when they first sync that week. No scheduled job                         |
| Late XP       | XP sent for a week that is over is ignored (the reply shows the current week)                                                                                   |
| Trust         | The server trusts the app's XP (no cheat detection). XP never goes down within a week                                                                           |
| Leaving       | Settings → League → Leave leagues deletes the player on the server (store rules require account deletion) and the token on the phone                            |
| Abuse         | `POST /v1/players` is rate-limited per client IP (`cf-connecting-ip`, else the socket address): `SIGNUP_LIMIT` per hour, default 10                             |
| Token storage | A one-row Drift table (`league_player`) in the app's sandbox                                                                                                    |
| Schema        | App schema 10: `league_player`. API: `player`, `league`, `league_member` in one Drizzle migration                                                               |
| Git           | Branch `r5-leagues` off `r4e-finish-v2` (PR #32 not merged yet), one commit per part, one PR                                                                    |

## Rules

The server is the authority on ranks, zones and moves. The app needs the week (to sum its XP and
count the days left), the tier count and the name rule. Those exist in Dart (pindoro_core
`progress/league.dart`) and TS (`apps/api/src/modules/leagues/leagues.rules.ts`), checked against
one shared fixture, `shared/fixtures/league_vectors.json` (`week`: an instant → key, start, end;
`name`: raw → normalised name and whether it is valid).

- `LeagueRules`: `tiers = 6`, `nameMin = 2`, `nameMax = 20`, `offset = Duration(hours: 4)`. TS adds
  `size = 30`, `promote = 5`, `demote = 5`.
- `leagueWeek(DateTime now) → ({String key, DateTime start, DateTime end})` (UTC instants).
- `leagueName(raw)`: trimmed, runs of whitespace as one space. `isLeagueName(name)`: 2–20
  characters (code points), the first a letter, the rest letters, spaces, `.`, `'`, `’`, `-`.
- TS only: `zone(rank, tier)` → `up` (rank ≤ 5 and tier < 5), `down` (rank > 25 and tier > 0), or
  `stay`; `nextTier(rank, tier)` = tier + 1 / − 1 / 0 by zone.

## API (`apps/api/src/modules/leagues`)

Tables (`src/db/schema.ts`):

- `player`: `id uuid pk default gen_random_uuid()`, `token_hash text unique` (sha256 hex of the
  token), `name text`, `created_at`.
- `league`: `id uuid pk`, `week date`, `tier smallint`, `created_at`; index on (`week`, `tier`).
- `league_member`: (`player_id` → player on delete cascade, `week`) pk, `league_id` → league on
  delete cascade, `xp integer`, `joined_at`.

Routes (TypeBox schemas, `openapi.json` regenerated):

| Route                   | Body         | Reply                                                                                                  |
| ----------------------- | ------------ | ------------------------------------------------------------------------------------------------------ |
| `POST /v1/players`      | `{name}`     | 201 `{player: {id, name}, token}`; 400 invalid name; 429 over the limit                                |
| `PATCH /v1/players/me`  | `{name}`     | 200 `{id, name}`; 400; 401                                                                             |
| `DELETE /v1/players/me` | —            | 204; 401                                                                                               |
| `PUT /v1/league/me`     | `{week, xp}` | 200 `{player: {id, name}, league: {tier, week, ends_at, members: [{rank, name, xp, zone, you}]}}`; 401 |

`/me` routes take `Authorization: Bearer <token>`. `PUT /v1/league/me` records `xp` for the
current week when `week` matches (`greatest(old, new)`), joins a league on the first XP (under a
transaction-scoped advisory lock per week and tier), then returns the player's league; `members`
is empty while they have no XP this week. `buildApp(config, {now})` takes a clock for tests.

## App

### Data (`features/league`, a layer between `course` and the screen features)

- `league_player` (schema 10): `id` (1), `player_id`, `token`, `name`. `LeagueDao`: `watchAccount`,
  `save`, `rename`, `drop`.
- `ProgressDao.xpBetween(start, end)`: answers and lesson results in [start, end); `xpOn` uses it.
- `LeagueApi` (package:http, 10 s timeout): `join(name)`, `rename(token, name)`, `leave(token)`,
  `sync(token, week:, xp:)`; non-2xx throws `LeagueException(status)`.
- `standingProvider`: null without an account; else syncs this week's XP and returns the
  `Standing` (`name`, `tier`, `endsAt`, `members`). A 401 drops the local account (the player is
  gone on the server) and returns null. Selecting the Leagues tab and opening Results refresh it.
- `LeagueActions`: `join`, `rename`, `leave` (a 401 on leave still drops the local account).
- `rankBefore(members, gained)`: the player's rank before their last `gained` XP, from the other
  members' XP (ties keep the current order); null when that XP is what put them in the league.

### Screens

- **Bottom bar:** Path · Free play · Pit stop · Leagues (`flag`) · Me; `/leagues` is the fourth
  branch.
- **Leagues tab** (`LeagueScreen`):
  - No account: Pindo, "Pick a league name", "Players in your league see it next to your XP.", the
    name field (`SearchField` with an optional glyph: `user`), Join (enabled when
    `isLeagueName`). A failed join shows a toast.
  - Loading: `LaneLoader`. Error: Pindo, "Can't reach the league", Try again.
  - No XP this week: the header, then "Earn XP to join this week's league" with a short line.
  - Otherwise: `LeagueHeader` (flag, "Avenue league", "Top 5 move up · 3 days left" — Highway says
    "Bottom 5 move down" — and the ladder), then one `ListGroup` of `LeagueRow`s with a
    `ZoneDivider` after the last promotion row and before the first demotion row. Your row reads
    "You" on `color.primary.soft`. Rows read "4th, You, 1 410 XP, promotion zone."
- **Results:** a chip "Up to 4th in Avenue league" (`flag`, primary) when this round's XP (its
  answers in this league week) moved the player up (`rankBefore` > rank now); taps open Leagues.
- **Settings → League** (only with an account): League name (subtitle the name) opens
  `/league-name` (the same form, Save); Leave leagues asks in a `PindoroDialog`, then leaves.
- **Strings:** en + ka drafts; ordinals through `formatOrdinal` (en 1st/2nd/3rd/4th, 11th–13th; ka
  1-ლი, მე-2…). Initials come from the name as typed (never uppercased).

### Design package

- `LeagueHeader({title, subtitle, tier, tiers, semanticLabel})`: street-card plate (`e2` lip, a
  thick `street-card.rule` inner border), `flag` in `league.gold`, `headline.sm` title, ladder of
  `tiers` 12 × 20 dp steps in `color.league.ladder`, the current 28 dp in `league.gold`.
- `LeagueRow({rank, name, xp, initials, avatar, you, semanticLabel})`: a 30 dp rank (a `medal` in
  gold/silver/bronze for 1–3), a 40 dp initials avatar, the name, the XP; `primary.soft` when
  `you`.
- `ZoneDivider({label, up})`: chevron + text in `league.promote` / `league.demote`.
- App tokens (`tokens/app.json`): `color.league.ladder` (cobalt.400), `color.avatar.1–4`
  (cobalt.500, aqua.700, orange.700, red.700), `color.avatar.text` (asphalt.0).
- Goldens regenerated (`just goldens`).

## Left out (to `docs/TODO.md`)

Sign-in and progress sync across devices; name moderation and reporting; cheat detection; XP
synced after the week ends; a "You moved up" moment at the week's end (the header shows the new
league); keychain storage for the token; the Results chip after lessons (the design has it on
Results only); league names other players see in Georgian vs Latin are shown as typed.

## Testing

- pindoro_core: `league_test.dart` reads the shared vectors (week, name).
- API (vitest + PostGIS): rules vectors and zones; create (normalised, invalid, rate limit);
  401 without a token; sync with 0 XP (no members); join, ranks, `you`, XP never decreasing; the
  31st player opens a second league; stale week ignored; rollover promotes the top 5; rename;
  delete (token stops working).
- Mobile: `LeagueApi` against `MockClient`; `rankBefore`; League tab states (join, board with
  zones and row semantics, empty week, error); Results chip; the 5-tab bar; Settings rename and
  leave; schema 10 migration.
- Design: the three widgets in the component gallery and goldens.
