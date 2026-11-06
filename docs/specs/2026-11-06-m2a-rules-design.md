# Milestone 2a — MVP rules

- Date: 2026-11-06
- Status: implemented
- Builds on: Milestone 1 (`docs/specs/2026-11-06-m1-gameplay-design.md`)
- Source: `docs/design/v1-screens.md` § Scoring, XP and levels, and the canvas board M-01 "MVP rules"

## Goal

The game follows the design system's MVP rules. Scoring uses fixed distances per road class instead
of the play area's size. A "street" is every way with that name. Rounds pick 10 distinct names
spread over the area. The player can retry a round's Close and Miss streets. Saved rounds expire.
Areas can be districts, a circle or a rectangle.

This is part (a) of five. (b) foundation (strings, settings, assets), (c) the round screens, (d)
setup and Home, and (e) polish follow, each with its own spec. This milestone changes rules, data
and the controller; screens change only as much as they need to keep working.

## Decisions

| Topic            | Decision                                                                                     |
| ---------------- | -------------------------------------------------------------------------------------------- |
| Scoring          | Fixed distances per road class × difficulty (below); the area no longer matters              |
| XP               | XP = points. The per-difficulty XP bonus (×1.0–1.5) is removed: "XP values stay the same"    |
| What a street is | Every pack row with the same `name_ka`, grouped in `pindoro_core` at runtime                 |
| Pack format      | Unchanged; the database keeps storing stable street ids                                      |
| Areas            | Districts (multi-select), circle, rectangle. Whole city is removed                           |
| Picking          | Design rules: skip names under 150 m, 3 × 3 grid round-robin, prefer unknown then not recent |
| Known streets    | Known after any Great or Perfect, per city; never reverts in the MVP                         |
| Retry            | A retry round asks the round's Close and Miss streets, same city, area and difficulty        |
| Saved round      | One; expires 7 days after its last activity or when the city or area changes                 |
| Street data      | From the city pack, never Overpass or Nominatim                                              |

## Scoring (`pindoro_core`, `@pindoro/geo`, `shared/fixtures`)

`f` is the difficulty factor: Easy 1.5, Medium 1, Hard 0.7, Expert 0.5. `d` is the geodesic
distance from the pin to the nearest point on any part of the street's name in the city. The
nearest part's road class sets the half-width.

| Tier    | Distance                     | XP                                         |
| ------- | ---------------------------- | ------------------------------------------ |
| Perfect | `d ≤ (halfWidth + 20 m) × f` | 100                                        |
| Great   | `d ≤ 100 m × f`              | `round(90 − 0.25 × (d/f − 20))` (90 → 70)  |
| Close   | `d ≤ 300 m × f`              | `round(60 − 0.15 × (d/f − 100))` (60 → 30) |
| Miss    | farther                      | 0                                          |

- Half-widths: `motorway`, `trunk` 14 m; `primary` 10 m; `secondary` 8 m; `tertiary` 7 m; any
  other class 5 m.
- API: `scoreAnswer(distanceM, roadClass, difficulty)` returns `Score = (tier, xp)`. It replaces
  `scoreAnswer(distanceM, areaM2, difficulty)`; `TierThresholds.forArea` becomes
  `TierThresholds.forStreet(roadClass, difficulty)`.
- Constants live only in the Dart and TS `ScoringConfig`. Removed: `perfectFloorM`, `greatFloorM`,
  `closeFloorM`, the three ratios and `xpBonus`. Levels are unchanged (1 000 + 250 × (n − 1)).
- `scoring_vectors.json`: the `thresholds` and `score` cases take `road_class` + `difficulty`
  instead of `area_m2`. They include the canvas examples (84 m residential at Medium → Great 74;
  240 m → Close 39), each tier boundary, Easy and Expert scaling, and an unlisted class.

## Named streets (`pindoro_core`)

- `NamedStreet`: `name` (`name_ka`), `nameEn`, `parts` (every pack `Street` with that exact
  `name_ka`), `id` (the longest part's street id). `round_question` stores the id the picker chose
  (the longest in-area part) and the answer stores that same planned id, so resume and retries match
  by id even when a newer pack makes another part the longest.
- `groupByName(List<Street>) → List<NamedStreet>`, one pass.
- Scoring, the reveal and known counts use all of a name's parts in the city. Picking uses only the
  parts inside the area.
- Any stored id maps back to its name through `PackRepository.streetNames(ids)`, so knowledge holds
  when a newer pack picks a different longest part.

## Areas (`pindoro_core`)

`Area` is sealed: `DistrictsArea(Set<String> ids)`, `CircleArea(LatLng center, double radiusM)`,
`RectArea(Bbox bounds)`.

- JSON: `{"kind":"districts","ids":[…]}`, `{"kind":"circle","lat":…,"lon":…,"radius_m":…}`,
  `{"kind":"rect","min_lat":…,"min_lon":…,"max_lat":…,"max_lon":…}`. The M1 form
  `{"kind":"district","district_id":…}` reads as a one-district set. `{"kind":"city"}` and anything
  unreadable read as no area.
- Limits as constants for the picker: circle radius 500–5 000 m; rectangle sides 500–10 000 m.
- `shapeIn(pack)` → `AreaShape = (String? name, Bbox bbox, List<List<Polyline>> boundary)`, or
  null when a district is missing from the pack. `name` is the districts' `name_ka` joined with ", "
  and null for circles and rectangles (display copy arrives in (d)). A circle's boundary is a
  64-point polygon. `areaM2` is removed.
- In-area rule, one for every shape: a part counts when ≥ 150 m or ≥ 30 % of it lies inside.
  - Districts: the union of the picked districts' `street_district` rows (the pipeline applies the
    same rule).
  - Circle and rectangle: parts whose bbox intersects the area's, then
    `lengthInside(MultiPolyline, bool Function(LatLng) contains)`, which walks each part in steps of
    at most 25 m and sums the steps whose midpoint is inside.

## Knowledge (`pindoro_core` + database)

- Per city and by name: **known** = at least one Great or Perfect ever; **missed** = answered, never
  Great or Perfect; **unknown** = never asked. `knowledgeFrom` takes the best tier instead of the
  last.
- `newlyKnown` → the names with a Great or Perfect in a round and none in the city's answers created
  before the round's `started_at` (the "+n streets known" figure). Retries cannot count a name
  twice.
- `knownCounts` → known / total names for the city and per district. Totals count every named
  street in the pack at every difficulty. Home shows them in (d).

## Picking the streets (`QuestionSelector`, rewritten)

1. Candidates: named streets with in-area parts whose difficulty is in the round's pool. A name
   whose in-area pool parts total under 150 m is skipped.
2. Fewer than 10 candidates → `NotEnoughStreets(count)`.
3. Split the area's bbox 3 × 3. Each candidate belongs to the cell holding the midpoint of its
   longest in-area part (clamped to the grid when that point lies just outside).
4. Rank inside a cell: unknown, then missed, then known; within each, names not asked in the city's
   last 3 rounds before recent ones; seeded random breaks ties.
5. Shuffle the non-empty cells once, then go round-robin, taking each cell's best-ranked remaining
   candidate until 10 are picked. Spread wins over preference.

Removed: the 3 : 2 : 0.5 weights, the 30-answer exclusion and the 300 m consecutive spacing.

## Database (`apps/mobile`, schema v3)

- `round.retry_of TEXT NULL REFERENCES round (id)`. Migration v2 → v3; the `drift_dev
  make-migrations` dump and helpers are committed with a v2 → v3 migration test.
- New or changed `AppDatabase` methods:
  - `retrySet(roundId)` → the round's planned street ids answered Close or Miss, in position order.
  - `bestTierByStreet(cityId)` → best tier per street id over the city's rounds (replaces
    `lastTierByStreet()`).
  - `askedInLastRounds(cityId, 3)` → street ids planned in the city's 3 most recent rounds
    (replaces `recentlyAnsweredStreetIds(30)`).
  - `resumableRound(now)` → the most recent unfinished round, unless its last activity (latest
    answer, else `started_at`) is more than 7 days before `now`.
- The app also rejects a saved round whose city or area differs from the current settings. Starting
  a new round supersedes the saved one; its answers and XP stay.

## Round controller (`apps/mobile`)

- `start(area, difficulty)`: pool from the area (above) → `QuestionSelector` → `startRound`.
- `startRetry(roundId)`: plans `retrySet(roundId)` in a new round with `retry_of`, copying the
  city, area and difficulty. An empty set starts nothing. A retry round can itself be retried.
- The question count is the number of planned rows (10, or 1–10 for a retry).
- Named streets are resolved once at start and on resume (id → name → every part in the city) and
  held by the round, so a pack update mid-round changes nothing. Planned ids missing from the pack
  are skipped; all missing → the round finishes.
- `confirm()`: distance to the nearest part → `scoreAnswer` with that part's road class → `answer`
  row under the representative id.
- `Revealed` carries every part, so the truth line shows the whole street.

## Screens (only what keeps the app working)

- Area: a district tap stores a one-district `DistrictsArea`; the whole-city row is removed.
- Quiz: the truth line draws every part of the name.
- Results: "retry n missed" when the retry set is not empty → `/quiz?retry=<roundId>`.
- Home: "continue" only for a resumable round.
- UI copy stays English placeholders until (b).

## Error handling

| Case                                                   | Behaviour                                               |
| ------------------------------------------------------ | ------------------------------------------------------- |
| Road class missing from the half-width table           | 5 m                                                     |
| Stored area unreadable or `{"kind":"city"}`            | No area; the Area screen opens                          |
| Saved districts missing from the active pack           | `shapeIn` null; the Area screen opens                   |
| Circle or rectangle with fewer than 10 candidates      | `NotEnough(count)`                                      |
| Empty retry set                                        | Retry button hidden; `startRetry` starts nothing        |
| Resume: planned streets missing from the pack          | Skipped; all missing → the round finishes, Results open |
| Saved round older than 7 days, or another city or area | Not resumable; Home shows Play                          |

## Testing

Locally only the touched modules' tests; CI runs every suite.

- `pindoro_core`: scoring per road class and difficulty; shared vectors (also run by
  `@pindoro/geo`); `groupByName` (representative = longest part, all parts kept); `Area` JSON
  round-trips including the M1 forms; `lengthInside` for a circle and a rectangle (a line half
  inside measures half); the 150 m / 30 % rule; the selector (cells spread, rank order, distinct
  names, 150 m skip, `NotEnough`, deterministic with a seeded `Random`); knowledge (known never
  reverts, `newlyKnown`, `knownCounts` per district).
- Database: v2 → v3 migration; `retrySet` order; the 7-day boundary of `resumableRound`;
  `bestTierByStreet` scoped to one city; `askedInLastRounds`.
- `RoundController` (in-memory Drift, fixture pack, seeded `Random`): confirm scores against the
  nearest same-name part with its class; `startRetry` plans the Close and Miss set with
  `retry_of`; resume rebuilds named streets; question count follows the planned rows.
- Widgets: Results shows the retry button only with Close or Miss answers; Area stores a district
  set.

## Docs

- `docs/TODO.md`: remove "Same-name street parts" (resolved here).
- `apps/mobile/CLAUDE.md`: note named streets and `retry_of`.

## Out of scope

Screen redesigns; the circle and rectangle picking UI (model and rules only); Georgian strings and
settings; the "n in a row" counter and the level-up moment (UI derivations in (c)); streaks and
everything in R2–R5.
