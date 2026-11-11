# pindoro_core

Pure Dart game logic. **No Flutter imports** — it must run under plain `dart test`.

```
lib/src/geo/        LatLng, LocalProjection, Bbox, pointToPolylineDistance, polyline6
lib/src/scoring/    Difficulty, Tier, ScoringConfig (half-widths, fixed distances), scoreAnswer,
                    RouteScoring + scoreRoute (road trips: % longer than the best drive)
lib/src/progress/   levels: requirement, totalXpToReach, levelForXp, progressWithinLevel;
                    league: the league week (Monday 00:00 at UTC+4) and the name rule;
                    badges: the starter eight and badgeProgress (Dart-only, like ReviewRules)
lib/src/game/       Area (districts/circle/rect, in-area rule), NamedStreet (nearby same-name parts),
                    QuestionSelector (10 names, 3 × 3 grid), knowledge (per street),
                    course (units per raion, stops, progress, Final drive gate, Jump ahead,
                    placement from known streets, the start-district order),
                    lesson (steps incl. the road trip, LessonRun, XP, card facts),
                    road_trip (pickTrip, RouteDraft drawing, turnsAt, routeLegs)
lib/src/pack/       City/District/Street (pack rows), PackRepository, RoadGraph (junctions,
                    edges, A* shortestRoute)
```

## Rules

- **In sync with `@pindoro/geo` (packages/geo).** Same algorithms, same constants, same rounding
  (polyline6 rounds half away from zero; XP uses `round()`). Both suites run the golden
  vectors in `shared/fixtures/*.json` (distance tolerance 0.5 m). Change one side → change the other
  and the vectors in the same commit.
- **Scoring constants live only in `ScoringConfig` and `RouteScoring`** (and their TS twins;
  `shared/fixtures/route_vectors.json` proves road-trip scoring). No magic numbers elsewhere.
  Game rules the server never scores stay Dart-only: `ReviewRules`, `CourseRules`, `LessonRules`,
  `TripRules`. `LeagueRules`' week and name rule are twinned in the API
  (`apps/api/src/modules/leagues/leagues.rules.ts`), proved by `shared/fixtures/league_vectors.json`;
  ranks and moves are the server's alone.
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
