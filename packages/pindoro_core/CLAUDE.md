# pindoro_core

Pure Dart game logic. **No Flutter imports** — it must run under plain `dart test`.

```
lib/src/geo/        LatLng, LocalProjection, Bbox, pointToPolylineDistance, polyline6
lib/src/scoring/    Difficulty, Tier, ScoringConfig (half-widths, fixed distances), scoreAnswer
lib/src/progress/   levels: requirement, totalXpToReach, levelForXp, progressWithinLevel
lib/src/game/       Area (districts/circle/rect, in-area rule), NamedStreet (same-name parts),
                    QuestionSelector (10 names, 3 × 3 grid), knowledge (known by name)
lib/src/pack/       City/District/Street/StreetDistrict (pack rows), PackRepository
```

## Rules

- **In sync with `@pindoro/geo` (packages/geo).** Same algorithms, same constants, same rounding
  (polyline6 rounds half away from zero; XP uses `round()`). Both suites run the golden
  vectors in `shared/fixtures/*.json` (distance tolerance 0.5 m). Change one side → change the other
  and the vectors in the same commit.
- **Scoring constants live only in `ScoringConfig`** (and its TS twin). No magic numbers elsewhere.
- Distances are measured to segments, not vertices, in a local equirectangular projection around
  the query point.
- **A street is a name.** Packs keep same-name parts as separate rows with stable ids;
  `groupByName` joins them at runtime. Rounds pick, score and count knowledge by name; the database
  stores a part's id, which resolves back to the name through the pack.
- Pack models map the columns in `docs/pack-format.md`; the format is the contract, not this code.

## Commands

```sh
dart test            # from packages/pindoro_core (fixtures resolve via ../../shared)
just test            # everything
```
