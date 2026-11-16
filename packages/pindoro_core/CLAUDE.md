# pindoro_core

Pure Dart game logic. **No Flutter imports** — it must run under plain `dart test`.

```
lib/src/geo/        LatLng, LocalProjection, Bbox, pointToPolylineDistance, polyline6
lib/src/scoring/    Difficulty, Tier, ScoringConfig (half-widths, fixed distances, difficulty
                    factors), TierThresholds, scoreAnswer (the tier of a pin)
lib/src/progress/   account: the account's username, password and recovery-code rules;
                    streak: calendar days, streakOf, freezes and the pill (Dart-only)
lib/src/game/       Area (districts/circle/rect, in-area rule), NamedStreet (nearby same-name parts),
                    QuestionSelector (10 names, 3 × 3 grid), knowledge (per street, Explore),
                    street_facts (road type, crossings, direction from the centre: the intro),
                    route_draft (RouteDraft drag and tap drawing, kept for M6 recitals)
lib/src/pack/       City/District/Street (pack rows; format 4 adds the curriculum columns and
                    FamilyLink), PackRepository, RoadGraph (junctions, edges, A* shortestRoute
                    to a goal set, edgeNear)
```

## Rules

- **In sync with `@pindoro/geo` (packages/geo).** Same algorithms, same constants, same rounding
  (polyline6 rounds half away from zero). Both suites run the golden
  vectors in `shared/fixtures/*.json` (distance tolerance 0.5 m). Change one side → change the other
  and the vectors in the same commit.
- **Scoring constants live only in `ScoringConfig`** (and its TS twin). No magic numbers elsewhere.
  Rules the server never scores stay Dart-only: `StreakRules`. `AccountRules` (username,
  password, recovery code) is twinned in `apps/api/src/modules/accounts/accounts.rules.ts`, proved
  by `shared/fixtures/account_vectors.json`. Learning rules live in pindoro_learning.
- Distances are measured to segments, not vertices, in a local equirectangular projection around
  the query point.
- **A street is a name in one place.** Packs keep same-name parts as separate rows with stable ids;
  `groupByName` joins parts within 500 m at runtime, so same-name streets in different suburbs stay
  apart. Rounds pick distinct names; scoring and knowledge are per street (`NamedStreet.id`). The
  database stores a part's id, which resolves through `streetsByPartId`.
- Pack models map the columns in `docs/pack-format.md`; the format is the contract, not this code.

## Commands

```sh
dart test            # from packages/pindoro_core (fixtures resolve via ../../shared)
just test            # everything
```
