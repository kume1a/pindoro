# R4c · v2.0 — road trips, the Final drive and Jump ahead

- Date: 2026-11-09
- Status: implemented
- Builds on: R4b (`docs/specs/2026-11-09-r4b-course-lessons-design.md`)
- Source: `docs/design/v1-screens.md` § R4 · v2.0; claude.ai screens canvas boards R4-02 rules,
  R4-12 (Final drive and locked unit sheets), R4-30 to R4-34 (road trip), R4-40 (Final drive and
  Unit complete), R4-61 unit storyboard, R4-63 motion table; components `RouteScreen`,
  `PathScreen`, `LessonDoneScreen` (state `unit`), `MeScreen`; bundle classes `.pd-pin--endpoint`,
  `.pd-map-junction`, `.pd-map-finger`, `.pd-map-ghost`, `.pd-map-car`

## Goal

Road trips arrive. The player drags a drive from A to B along the streets; the route snaps junction
by junction, and the game compares it with the shortest drive. A lesson ends with one road trip,
and each unit ends with the Final drive: three road trips across the raion. Passing it opens the
next unit with a reward screen and the R4-61 storyboard on the Path. A player who already knows a
raion can jump ahead by passing that unit's Final drive early.

Packs get a road graph for this (format 3). What's new, placement and the start-district picker
stay R4d.

## Decisions

| Topic         | Decision                                                                                                                   |
| ------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Road graph    | The pack's named drivable streets only (the ways behind `street`); every edge belongs to a street. One-way ignored         |
| Pack format   | 3: tables `junction` and `road_edge`. The app still opens format 2 packs; without a graph there are no road trips          |
| Jump ahead    | Any locked unit. Passing its Final drive marks it and every unit before it done (checks, no stars)                         |
| Final drive   | 3 passed trips (Close or better). A Miss offers a new trip; passed trips are kept when leaving                             |
| Trip storage  | No schema change: `lesson_result.kind` gains `finalDrive`, `lesson_answer.kind` gains `trip` (text enums)                  |
| Route scoring | `RouteScoring` next to `ScoringConfig` in pindoro_core and `@pindoro/geo`, proven by `shared/fixtures/route_vectors.json`  |
| In R4c        | The R4-61 unit storyboard; the first-trip ghost tutorial; turn by turn for screen readers                                  |
| Later         | Settings "Choose turns from a list"; the detour sentence and its chip (docs/TODO.md)                                       |
| R4b progress  | Not carried over: a unit opens only once the one before it is done, so a unit opened by lesson 6 waits for the Final drive |

## Pack format 3 (`apps/pipeline`, `docs/pack-format.md`)

```sql
CREATE TABLE junction (
  id  INTEGER PRIMARY KEY,   -- pack-local; not stable across pack versions
  lat REAL NOT NULL,
  lon REAL NOT NULL
);

CREATE TABLE road_edge (
  id            INTEGER PRIMARY KEY,
  from_junction INTEGER NOT NULL REFERENCES junction (id),
  to_junction   INTEGER NOT NULL REFERENCES junction (id),
  street_id     TEXT NOT NULL REFERENCES street (id),
  length_m      REAL NOT NULL,   -- along the unsimplified way, metres in UTM
  geometry      TEXT NOT NULL    -- polyline6 from from_junction to to_junction, simplified to 3 m
);
```

- osm2pgsql keeps each road's node ids (`osm.roads.nodes`, text, comma-separated, so the Lua runs
  on osm2pgsql 1.8 and 1.11).
- `sql/70_graph.sql`: graph ways are the ways of `pipeline.street` (named, drivable, not private). A
  junction is an OSM node shared by two graph ways (or met twice by one), or a way's end. An edge
  is a way's stretch between two consecutive junctions; edges are undirected. Ways whose point
  count differs from their node count are skipped.
- A fixture pack keeps the edges of its streets and the junctions they use.
- `validate` adds: the new tables match the DDL; every edge references existing junctions and
  streets, has a positive length and a geometry that starts and ends at its junctions; the largest
  connected part holds at least a share of the edges (set from the Tbilisi build).
- `PACK_FORMAT_VERSION = 3`; the manifest and `PRAGMA user_version` follow. The app installs format
  3 (`PackStore.supportedFormatVersion`) and still opens a format 2 pack already on the phone; the
  background refresh replaces it when online.

## Rules (`pindoro_core`)

**Road graph (`road_graph.dart`).** `RoadGraph(junctions, edges)` with the edges at each junction.
`RoadEdge` holds its ends, street part id, length and its polyline6, decoded on first use.
`PackRepository.roadGraph()` returns null for a pack without the tables.

- `shortestRoute(from, to)`: A* on edge lengths with a straight-line heuristic. A `Route` is its
  junctions (from A), its edges and its length.

**Picking a trip (`road_trip.dart`).** `pickTrip(graph, destinations, starts, minM, maxM, within,
random)`: B is a junction on a destination street (its middle junction first), A a junction on
another of the `starts` streets, straight-line `minM`–`maxM` from B, both inside `within` when
given, joined by a route at most 1.6 times the straight line (so A or B never sits where only a
long loop reaches). Null when nothing qualifies (the step is skipped).

- Lesson: destination = one of the lesson's 4 streets; A on the unit's other streets; 500–1 500 m.
- Final drive: destinations = the unit's streets, a different one per trip; A on the unit's streets;
  both inside the raion; 800–2 500 m.

**Drawing (`RouteDraft`).** Starts at A. `follow(finger, snapM)` walks while the finger passes
junctions: of the edges at the route's end, the one nearest the finger (within `snapM`) is taken
when the finger comes within `snapM` of its far junction; taking the edge just driven backs up
instead. It stops at B. `heading(finger, snapM)` is the edge being followed (the next-junction
ring). `undo()` drops the last edge, `startOver()` all of them; `take(edge)` adds one (turn by turn).
Dead ends and U-turns are allowed; they only cost distance.

- `turnsAt(draft, goal)`: the edges at the route's end as turn options (left, straight, right,
  back; from A just the heading), each with its compass heading and whether it heads towards B.
- `routeLegs(route)`: the route as legs of one street each (street id, compass heading, metres),
  for "East on Chavchavadze Avenue, then south on Paliashvili Street: 822 m".

**Scoring (`scoring.dart`, both twins).** p = (drawn ÷ best − 1) × 100, divided by the difficulty
factor as pin distances are. Perfect p ≤ 3 (100 XP), Great p ≤ 25 (`round(90 − 1.2 × p)`), Close
p ≤ 60 (`round(60 − (p − 25))`), else Miss (0). "Show the route" is a Miss.

**Lessons (`lesson.dart`).**

- `TripStep(trip)`: a test step on the trip's destination street, after the 6 shuffled tests (step
  11). `planLesson(trip:)` adds it to lessons and practice; a unit's Pit stop has none. A pack
  without a graph, or no qualifying trip, plays the 10 steps of R4b.
- `LessonRun.answerTrip(score, at)`: XP halved for a fix and in practice.
- A mistake is a Close or Miss pin, a wrong name, or a Miss trip. A trip mistake comes back once as
  the same trip. Accuracy counts a trip as right when it isn't a Miss.
- `LessonRules.maxXp` becomes 670 (the trip's 100 added).
- `reviewAnswers` and known streets skip trips: a trip is about the route, not one street.

**Course (`course.dart`).** `LessonKind.finalDrive`; `CourseRules.finalDriveTrips = 3`,
`CourseRules.unitBonusXp = 100`.

- `LessonOutcome` gains `passed` (a Final drive trip that was Close or better).
- A unit is driven when 3 of its Final drive trips passed, and done when it or any later unit is
  driven. The first unit is open; every other one opens when the unit before it is done.
- In a done unit every stop shows done; stops done by their own result keep their look (Perfect
  stars stay), the Final drive turns yellow (`perfect`).
- The Final drive is current once every stop before it is done; `UnitProgress.tripsPassed` drives
  its ring.

## Data (`apps/mobile`, no schema change)

- A lesson's trip answer: `lesson_answer.kind = trip`, the destination street, its tier and XP, no
  distance.
- A Final drive trip is saved as soon as it is answered: its own `lesson_result` (kind
  `finalDrive`, the unit, no lesson number, the trip's XP plus `unitBonusXp` on the trip that
  completes the unit, `tests` 1, `rightFirst` 1 when passed) and its one trip answer.
  `ProgressDao.finishTrip` writes it in one transaction and marks the daily goal.
- Total XP and today's XP already sum `lesson_result.xp`. `unitMistakes`, `bestTierByPart` and the
  last pin distances skip trip answers.
- New reads: `roadTrips()` (Me's tile, and the first trip ever when it is 0) and
  `unitSummary(cityId, unitId)` (XP and road trips in the unit, for Unit complete).
- `roadGraphProvider`: the open pack's graph, built once and kept while the pack stays open.

## Screens

**Road trip (`features/map/ui/route_view.dart`, shared by lessons and the Final drive; R4-30 to
R4-34).**

- The map frames A and B. The plate asks "Road trip: draw the shortest drive to" (the Final drive:
  "Final drive 2 of 3: draw the shortest drive to") with the destination street and "Start at A".
  A and B are yellow endpoint pins with their letter.
- Drawing: a one-finger drag that starts within 40 dp of the route's end draws; any other drag pans
  or zooms the map. The route grows edge by edge (cobalt 5 dp dashes 8/7 over a 9 dp white halo), a
  ring marks the next junction, a light tick (`selectionClick`) plays per junction, and an ink chip
  at the route's end shows "420 m so far". Off the road the line stops, a thin rubber band follows
  the finger, and after 1 s a toast says "Your route only follows streets. Drag along a white road."
- ← undoes the last street; holding it starts over. Map controls as the pin drop.
- Reaching B pops B with a light impact and enables **Check route** (before that its label reads
  "Check route. Reach B first."). **Show the route** asks first ("Show the best route?" · "This road
  trip will count as a Miss and come back at the end of the lesson." · Keep driving / Show the best
  route; the Final drive says "This trip will count as a Miss.").
- Check: the map fits both routes; a car drives the best route in 1 200 ms (linear) with the yellow
  route paint drawing behind it and chevrons every 80 dp; "Driving the best route…" with **Skip**
  (a tap anywhere skips too). Reduce motion shows both routes at once. Then the map leaves room and
  the tier sheet rises: Perfect "Best route!" ("822 m. You found the shortest drive."), Great
  "Great drive" and Close "Close" ("22 % longer than the best route.", chip "1 006 m · best
  822 m"), Miss "Here's the best drive" (its legs: "East on Chavchavadze Avenue, then south on
  Paliashvili Street: 822 m."). Celebration, tier haptics and the "Comes back at the end" chip as a
  pin drop.
- Turn by turn (R4-34) when a screen reader is on (`MediaQuery.accessibleNavigation`): under the
  map, "Turn by turn · 40 m from A", "At the junction, go" and a list of turn options ("Left onto
  Paliashvili Street", "Heads east, towards B"), **Undo last turn**, **Check route**. Each choice is
  announced ("Turned left onto Paliashvili Street. 160 metres so far."; at B "You reached B. Check
  route is available.").
- First road trip ever (no trip saved yet): a dotted ghost route along the first streets of the
  best drive with a finger dot looping twice, and a coach bubble "Drag from A along the streets to
  B" · "Your route snaps to the roads. The shorter the drive, the more XP." Both hide on the first
  touch.

**Lesson.** Step 11 is the road trip; the step bar has 11 segments; the lesson sheet says up to
670 XP. A Miss trip comes back among the fixes as the same trip.

**Final drive (`/drive?unit=`, R4-40).**

- Path: the Final drive stop is locked until lesson 6 (and the Pit stop) are done ("The Final drive
  is locked" · "Finish lesson 6 first."), then current (72 dp, trophy, a ring for trips passed,
  tip "Final drive"), yellow once passed.
- Its sheet: "Final drive · Unit 2 · Vake", "Drive across Vake", "Three road trips on the streets
  you learned in this unit. Finish to open Unit 3 · Vere." (passed trips: "You passed 1 of 3."),
  chips "3 road trips" and "up to 400 XP", **Start the drive**. Without a road graph: "Road trips
  need the newest Tbilisi pack. Connect to the internet to get it." and **OK**.
- The drive screen: ✕ (dialog "Leave the Final drive?" · "The trips you passed are kept." · Keep
  driving / Leave), a 3-segment bar (passed trips filled), the XP of this drive. Each trip is a
  road trip; a Miss offers **Try this trip again** (a new A and B); the third pass opens Unit
  complete.

**Jump ahead (R4-12).** A locked unit's signpost opens its sheet instead of R4b's bubble: "Unit 3 ·
Locked", "Vere", "Finish Vake's Final drive to open Vere. Know Vere already? Pass its Final drive to
jump ahead.", **Keep going in Vake** (closes and scrolls to the current stop) and **Jump ahead** (the
drive screen for that unit). Locked stops inside it keep their bubble.

**Unit complete (`/unit-done?unit=`, LessonDoneScreen state `unit`).** A trophy shield pops
(spring.bouncy) with a 12-dash burst, the medium celebration and a medium impact; "Unit 2
complete", "Vake complete!", "You learned 24 streets in Vake and drove across it three times.";
stat tiles Streets, Road trips and XP (the unit's totals); the next unit's signpost ("Next · Unit 3
· Vere") and **Continue to Vere** (**Continue** after the last unit). Continue goes to the Path and
plays R4-61.

**Next unit opens (R4-61, 900 ms).** 0 ms: the trophy turns yellow with a pop and the burst.
280 ms: the next signpost flips (rotate on X to 90° on its locked face, back to 0° on its open face,
`duration.base`, medium impact), its road fades from 55 % to 100 % (`duration.slow`). Then the path
scrolls the new unit up and its first stop pops current. Reduce motion: a 150 ms cross-fade.

**Me.** The Road trips tile counts every road trip answered (lessons and Final drives).

## Design system (`packages/pindoro_design`)

- `PinMark.endpoint(letter)`: the A/B pin (`.pd-pin--endpoint`: route-line face, casing stroke and
  lip, the letter in route-arrow ink), rendered to PNG for the map like the player pin.
- `CarMark`: the replay car (`.pd-map-car`: route-arrow disc, route-line car glyph, white halo).
- `LevelBadge` takes a glyph instead of the level number (the Unit complete trophy shield).
- Goldens: `route_{light,dark}.png` (A and B pins, the car, the trophy shield). Existing goldens
  don't change.

## Testing

- Pipeline (synthetic OSM, in the pipeline image): ways sharing a node meet at a junction; a bridge
  crossing without a shared node doesn't; edge lengths; a fixture pack keeps only its streets'
  edges; `validate` passes the new checks.
- pindoro_core: A* against a brute-force search on small graphs; `pickTrip` limits; `RouteDraft`
  following, backing up, undo and stopping at B; turn options and legs; the route vectors (also in
  `@pindoro/geo`); a lesson with a trip (mistake, fix, practice, XP, accuracy); `courseProgress`
  with the Final drive gate and Jump ahead.
- Mobile: the DAO's trip writes and reads (Pit stop, known streets and last distances unaffected);
  the lesson controller plays a trip; the drive controller passes a unit and keeps passed trips;
  widget tests for the road trip (drawing through the controller, the turn list), the Final drive
  to Unit complete to the Path, the locked-unit sheet and Me.
- Emulator (debug build, a format 3 Tbilisi pack built locally): a lesson's road trip (ghost
  tutorial, drawing, off-road toast, undo, check, replay, sheet), a Final drive with a Miss and a
  new trip, Unit complete, R4-61, Jump ahead from a locked unit, dark theme.

## Out of scope (docs/TODO.md)

- Settings → Accessibility "Choose turns from a list" (turn by turn follows the screen reader only).
- The detour sentence ("Turning north for the main road added 212 m") and its ink chip.
- The lane loader while checking (the best route is computed at once).
- One-way streets (ignored, as the rules say).
- Caching tiles around a lesson; resuming a killed lesson or drive at its step.
- The road trip sound and every other sound (no sound kit).
