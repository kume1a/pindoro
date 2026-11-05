# Milestone 1 — playable rounds and pack download

- Date: 2026-11-06
- Status: implemented (plan `docs/plans/2026-11-06-m1-gameplay.md`)
- Builds on: Milestone 0 (`docs/adr/0001-architecture.md`, `docs/pack-format.md`)

## Goal

A player can pick Tbilisi, an area (whole city or one district) and a difficulty, play 10-question
rounds on the unlabelled map, see each answer scored, review the round, and watch XP and level grow.
Rounds survive an app kill and resume. The app downloads the full Tbilisi pack from `/v1/catalog`
and keeps it up to date silently; the bundled Vake fixture is the offline fallback.

## Decisions

| Topic           | Decision                                                                                   |
| --------------- | ------------------------------------------------------------------------------------------ |
| Scope           | Playable loop + pack download.                                                             |
| Difficulty pool | Cumulative: easy = easy; medium = easy+medium; hard = +hard; expert = all four.            |
| Pack updates    | Automatic and silent; a new pack is used as soon as it is installed (rounds keep theirs).  |
| Round state     | Persisted and resumable (`round_question` table, schema v2).                               |
| Scoring area    | `areaM2` of the selected area: `city.area_m2` for the whole city, `district.area_m2` else. |

## Components

### pindoro_core (pure Dart)

- `Difficulty.pool` → `Set<Difficulty>`: the cumulative set for a round at that difficulty.
- `Area` (sealed): `WholeCity` | `DistrictArea(districtId)`.
  - `toJson()` / `Area.fromJson()` — the format stored in `user_settings.last_area_json` and
    `round.area_json`: `{"kind":"city"}` or `{"kind":"district","district_id":"osm:r11300449"}`.
  - `shapeIn(PackRepository)` → `AreaShape?` (`name`, `areaM2`, `bbox`, `boundary`) in one lookup;
    null when the pack lacks the area.
- `knowledgeFrom(Tier? lastTier)` → `StreetKnowledge`: `null` = unknown, perfect/great = known,
  close/miss = missed.
- `PackRepository.streetNames(ids)` → `name_ka` by id, so Results needn't decode geometry.
- Unchanged: `QuestionSelector`, scoring, levels, geometry.

### apps/mobile — database (schema v2)

New table:

```sql
CREATE TABLE round_question (
  round_id  TEXT    NOT NULL REFERENCES round (id),
  position  INTEGER NOT NULL,  -- 0..9
  street_id TEXT    NOT NULL,
  PRIMARY KEY (round_id, position)
);
```

- Migration v1 → v2 creates the table; `drift_dev make-migrations` output (v2 dump, generated
  helpers) is committed with a v1 → v2 migration test.
- New `AppDatabase` methods:
  - `startRound(...)` — inserts `round` + its `round_question` rows in one transaction.
  - `resumableRound()` — the most recent round if its `finished_at` is null, else null.
  - `roundProgress(roundId)` — planned street ids by position + the answers given so far; the
    current question is the first position without an answer (derived, never stored).
  - `finishRound(roundId)` — sets `finished_at`.
  - `lastTierByStreet()` — latest answer tier per answered street (for selection weights).
  - `recentlyAnsweredStreetIds(limit: 30)` — excluded from new rounds.
  - `answersForRound(roundId)` — for Results.
- The `answer` table stays append-only (existing trigger).

### apps/mobile — pack store (`features/pack/pack_store.dart`)

- `activePack()`: newest installed pack in `<documents>/packs/<city>/<version>.sqlite`, else the
  bundled fixture (copied as today).
- `refresh()`: `GET {API_BASE_URL}/v1/catalog` → if the city's `version` is newer than the newest
  installed one (versions are `YYYYMMDDTHHMMSSZ`, compared as strings): download `pack.url` to a temp file → check `size` and sha256 (`crypto` package) →
  gunzip (`dart:io`) → open read-only and check `meta.format_version == 1` → atomic rename to
  `<version>.sqlite`. Keeps the two newest versions, deletes older ones.
- Runs on launch (first launch finishes before the player reaches Area). Failures delete temp files, keep the current pack, and
  retry on the next launch; nothing is shown to the player (debug builds log).
- `packRepositoryProvider` opens the newest installed pack, else the fixture; it is invalidated as
  soon as a download installs, and a round in play is unaffected because it holds its `Street`s.

### apps/mobile — round controller (`features/quiz/round_controller.dart`)

Riverpod `Notifier` with states `Loading → Asking(question, pin?) → Revealed(answer) → … → Finished`
and `NotEnough(count)`.

- `start(area, difficulty)`: pool = pack streets in `area` with difficulty in `difficulty.pool`;
  candidates get `knowledgeFrom(lastTierByStreet)`; `QuestionSelector.select(pool,
  recentlyAsked: recentlyAnsweredStreetIds(30))`; `NotEnoughStreets` → `NotEnough(count)`; otherwise
  `startRound` and ask question 0.
- `resume(roundId)`: loads `roundProgress`, skips planned streets missing from the active pack
  (street ids are stable across versions); all remaining missing → `finishRound` → `Finished`.
- `placePin(latLng)`: sets or moves the pin (no write).
- `confirm()`: `pointToPolylineDistance(pin, street.geometry)` → `scoreAnswer(distance,
  area.areaM2, difficulty)` → insert `answer` (pin, distance, tier, xp, pack version) → `Revealed`.
- `next()`: next unanswered position, or `finishRound` → `Finished(roundId)`.

### apps/mobile — screens

- **Area**: "whole city" plus every district from the active pack (Georgian name, English below).
- **Home**: level + XP bar (`progressWithinLevel(totalXp)`), current area and difficulty with
  change buttons; primary button "continue (n/10)" when `resumableRound()` exists, else "play";
  secondary "new round" when resumable.
- **Quiz**: `StreetPlate` with the street name; map framed on the area with `area-mask` dimming
  outside it; tap places/moves the cobalt pin; "confirm" enabled once a pin exists. Reveal: yellow
  `truth-street`, camera fits street + pin, ink dashed `measure` line, `FeedbackBadge`,
  "523 m · +88 xp" (tabular figures), "next". `NotEnough(count)` shows the count and links to
  Area and Difficulty.
- **Results** (`/results?round=<id>`): per question street name, distance, badge, xp; round total;
  level bar, marking a level-up.
- The map is provided through a Riverpod provider so widget tests replace it and never build the
  MapLibre platform view.

### Design tokens (placeholders)

`color.map.light.mask`, `color.map.dark.mask`, `opacity.map.mask` for the area mask.

## Error handling

| Case                                           | Behaviour                                                             |
| ---------------------------------------------- | --------------------------------------------------------------------- |
| Catalog/download/verify/open fails             | Delete temp, keep current pack, retry next launch, silent.            |
| Catalog `format_version` > 1                   | Ignore that pack (needs an app update).                               |
| Pool < 10 streets                              | `NotEnough(count)` screen with links to Area / Difficulty.            |
| Resume: some planned streets missing from pack | Skip them; all missing → finish the round and open Results.           |
| No pin placed                                  | Confirm disabled.                                                     |
| Saved area not in the active pack              | Open Area to pick again (e.g. offline, fixture has only Vake).        |
| Tiles unreachable                              | Rounds still work; MapLibre's ambient cache shows tiles already seen. |

## Testing

- **pindoro_core**: `Difficulty.pool`, `Area` JSON round-trip and `areaM2`, `knowledgeFrom`;
  existing golden vectors unchanged.
- **Database**: generated v1 → v2 migration test; `startRound` transaction; `roundProgress` current
  position; `resumableRound` (only the most recent unfinished round); `lastTierByStreet`;
  `recentlyAnsweredStreetIds`.
- **RoundController** (in-memory Drift, fixture pack, seeded `Random`): start plans 10 streets;
  confirm writes tier and xp matching `scoreAnswer`; a new controller resumes at the right position;
  the 10th answer finishes the round; `NotEnough` for a tiny pool.
- **PackStore** (`http` `MockClient`, temp dir): installs a gzipped fixture as a new version;
  rejects size and sha256 mismatches; keeps the two newest versions; falls back to the fixture.
- **Widgets**: quiz confirm → reveal → next with a fake map; Results from database rows; Home shows
  "continue" for a resumable round.
- **Emulator**: full round on the full Tbilisi pack downloaded from `just dev`; kill the app
  mid-round and resume.

## Out of scope

Server sync and leaderboards, settings (theme, language), offline tile packs, curated
neighbourhoods, localised UI copy (English placeholders remain), streaks and achievements.
