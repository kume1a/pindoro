# R4c Road trips, Final drive and Jump ahead Implementation Plan

> **For agentic workers:** Implement this plan one task at a time. Steps use checkbox (`- [ ]`)
> syntax for tracking. The user approved this batch's git flow: worktree `../pindoro-r4c`, branch
> `r4c-road-trips`, one commit per task, PR, merge commit once CI is green; no stop between tasks.

**Goal:** A road graph in city packs (format 3), road trips drawn on the map and scored against the
shortest drive, the lesson's road-trip step, the Final drive, Jump ahead, Unit complete and the
R4-61 storyboard (spec: `docs/specs/2026-11-09-r4c-road-trips-design.md`).

**Architecture:** The pipeline turns the OSM node topology of the pack's street ways into
`junction` and `road_edge` tables. `pindoro_core` owns the graph (A*), trip picking, the drawing
state (`RouteDraft`), route scoring (twinned in `@pindoro/geo`) and the lesson and course rules.
The app stores trips in the R4b tables (new enum values, no migration); `features/map` gets the
shared road-trip view, `features/lesson` the Final drive and Unit complete, `features/course` the
Path changes.

**Tech Stack:** osm2pgsql flex (1.8 and 1.11), PostGIS, better-sqlite3, Flutter 3.47, Riverpod 3
(no codegen), Drift (schema 8, unchanged), maplibre_gl 0.27, go_router, gen-l10n.

## Global Constraints

- Pack format changes: `docs/pack-format.md`, pipeline export (`PACK_DDL`), Dart pack models and
  `format_version` together; stable street ids untouched (no identity diff from the same extract).
- Scoring constants only in `ScoringConfig`/`RouteScoring` (Dart) and `ScoringConfig`/
  `RouteScoring` (TS), matching `shared/fixtures/route_vectors.json`.
- Road-trip tiers: p = (drawn ÷ best − 1) × 100 ÷ difficulty factor; Perfect ≤ 3 (100), Great ≤ 25
  (`round(90 − 1.2p)`), Close ≤ 60 (`round(60 − (p − 25))`), Miss 0. Lesson max 670 XP; unit
  bonus +100; Final drive = 3 passed trips (Close or better).
- Design values only from `pindoro_design` tokens; map colours yellow = truth (best route), cobalt
  = you (drawn route), ink = measurement; every map keeps its attribution.
- Never uppercase UI strings; every string in `app_en.arb` and `app_ka.arb` (Georgian drafts);
  numbers through `formatNumber`, distances through `formatDistance`. Georgian never in repo text.
- Layers: `l10n` → `core` → `features/progress` → `features/pack` → `features/map` →
  `features/course` → screen features → `app`; screen features never import each other.
- Run only the touched tests locally; goldens only on Linux (`just goldens`); CI runs the rest.

---

### Task 1: Road graph in packs (format 3)

**Files:** modify `apps/pipeline/osm2pgsql/pindoro.lua` (`nodes` column), create
`apps/pipeline/sql/70_graph.sql`, modify `apps/pipeline/src/pack.ts` (DDL, format 3, graph export,
fixture subset), `apps/pipeline/src/validate.ts` (graph checks), `apps/pipeline/test/fixtures/synthetic.osm`
(a junction and a bridge), `apps/pipeline/test/sql.test.ts`, `docs/pack-format.md`,
`apps/pipeline/CLAUDE.md`; rebuild `apps/mobile/assets/packs_fixture/tbilisi_vake_fixture.sqlite`.

**Produces:** pack tables `junction(id, lat, lon)` and `road_edge(id, from_junction, to_junction,
street_id, length_m, geometry)` per the spec; `PACK_FORMAT_VERSION = 3`.

- [ ] Lua: `roads` gets `nodes text` = `table.concat(object.nodes, ',')`.
- [ ] `70_graph.sql`: `pipeline.graph_way` (way id, street key, UTM geom, node ids array) for ways
  in `pipeline.street.way_ids` whose `ST_NPoints = cardinality(nodes)`; `pipeline.junction` = nodes
  used ≥ 2 times across graph ways or at a way's ends, numbered; `pipeline.road_edge` = each way
  cut between consecutive junction positions (`ST_MakeLine` of the points), UTM length, WGS84
  geometry simplified 3 m (ends kept).
- [ ] Synthetic OSM: Split Street's shared node 202 is a junction; add a crossing way that shares a
  node with Cross Avenue and a bridge way crossing it without one. Tests: the shared node is a
  junction, the bridge crossing isn't; edges of a way sum to its length; the fixture pack keeps only
  its streets' edges and their junctions; edges decode and start/end at their junctions.
- [ ] Validate: schema of the new tables, references, positive lengths, ends at junctions, largest
  component share (threshold from the Tbilisi build, printed in the summary).
- [ ] Run the pipeline tests in the image (`docker compose -f infra/docker-compose.yml run --rm
  --build -e PINDORO_REQUIRE_OSM_TOOLS=1 -e TEST_DATABASE_URL=… --entrypoint pnpm pipeline test`);
  build the Tbilisi pack (same cached extract, no identity diff) and the fixture; validate both;
  update the docs; commit `feat(pipeline): road graph in packs (format 3)`.

### Task 2: Graph, trips, drawing and route scoring (`pindoro_core`, `@pindoro/geo`)

**Files:** create `packages/pindoro_core/lib/src/pack/road_graph.dart`,
`packages/pindoro_core/lib/src/game/road_trip.dart`; modify `scoring/scoring.dart`
(`RouteScoring`, `scoreRoute`), `pack/pack_repository.dart` (`roadGraph()`), the export file,
`packages/geo/src/scoring.ts` (+ test), create `shared/fixtures/route_vectors.json`; modify
`apps/mobile/lib/features/pack/data/sqlite_pack_repository.dart` (`roadGraph`),
`pack_store.dart` (format 3), the repository fakes; tests `road_graph_test.dart`,
`road_trip_test.dart`, `vectors_test.dart`.

**Produces:**

- `class RoadEdge { int id; int from; int to; String streetId; double lengthM; Polyline get line;
  int other(int junction) }`, `class RoadGraph { RoadGraph(Map<int, LatLng> junctions,
  List<RoadEdge> edges); Map<int, LatLng> junctions; List<RoadEdge> edgesAt(int junction);
  Route? shortestRoute(int from, int to) }`, `class Route { List<int> junctions; List<RoadEdge>
  edges; double lengthM; MultiPolyline get lines }`.
- `PackRepository.roadGraph() → RoadGraph?` (null without the tables).
- `typedef Trip = ({int from, int to, NamedStreet destination, Route best})`;
  `Trip? pickTrip(RoadGraph graph, {required List<NamedStreet> destinations, required
  Iterable<NamedStreet> starts, required double minM, required double maxM,
  List<List<Polyline>>? within, required Random random})` (the caller leaves used
  destinations out);
  `abstract final class TripRules { lessonMinM 500, lessonMaxM 1500, driveMinM 800, driveMaxM
  2500 }`.
- `class RouteDraft { RouteDraft(RoadGraph graph, int start, int goal); List<RoadEdge> edges;
  List<int> junctions; int get end; bool get reached; double get lengthM; RouteDraft follow(LatLng
  finger, double snapM); RoadEdge? heading(LatLng finger, double snapM); RouteDraft undo();
  RouteDraft startOver(); RouteDraft take(RoadEdge edge) }`.
- `enum Turn { start, left, straight, right, back }`; `typedef TurnOption = ({RoadEdge edge, Turn
  turn, CompassPoint heading, bool towardGoal})`; `List<TurnOption> turnsAt(RouteDraft draft)`.
- `typedef RouteLeg = ({String streetId, CompassPoint heading, double lengthM})`;
  `List<RouteLeg> routeLegs(Route route)`.
- `abstract final class RouteScoring { perfectMaxPct 3; greatMaxPct 25; closeMaxPct 60; greatXpAt
  90; greatXpPerPct 1.2; closeXpAt 60; closeXpPerPct 1 }`; `Score scoreRoute(double drawnM, double
  bestM, Difficulty difficulty)`; TS `scoreRoute(drawnM, bestM, difficulty) → {tier, xp}`.

- [ ] Tests: A* equals a brute-force search on random small grids; unreachable → null;
  `pickTrip` respects distances, `within`, `avoid` and the destination; `RouteDraft` follows a
  drag across junctions, backs up along the last edge, ignores a finger off the road, stops at B;
  undo / start over / take; turns at a cross (left, straight, right, back) and the heading toward
  B; legs merge consecutive edges of one street; vectors (Perfect at 0 and 3, Great 22 → 64, Close
  26 → 59, Miss 61, Easy and Expert factors).
- [ ] Implement; `dart test` (road graph, road trip, vectors), `pnpm --filter @pindoro/geo test`,
  mobile pack repository test; commit `feat(core): road graph, trips, drawing and route scoring`.

### Task 3: Lessons with trips, the Final drive gate and Jump ahead (`pindoro_core`)

**Files:** modify `packages/pindoro_core/lib/src/game/lesson.dart`, `course.dart`; tests
`lesson_test.dart`, `course_test.dart`.

**Produces:**

- `LessonKind.finalDrive`; `CourseRules.finalDriveTrips = 3`, `CourseRules.unitBonusXp = 100`.
- `final class TripStep extends TestStep { TripStep(Trip trip, {bool fix}); Trip trip }`;
  `planLesson(..., Trip? trip)` appends it after the tests (lesson, practice).
- `LessonRun.answerTrip(Score score, DateTime at)`; `bool isMistake(StepAnswer a)` (trip: Miss;
  pin: Close/Miss; name: wrong); `mistakes`, `rightFirst`, segments use it; fixes rebuild a
  `TripStep(trip, fix: true)`; `reviewAnswers` skips trips; `LessonRules.tripXp = 100`, `maxXp` 670.
- `LessonOutcome` gains `bool passed`; `UnitProgress` gains `bool done`, `int tripsPassed`;
  `courseProgress` per the spec (driven at 3 passed trips, done when it or a later unit is driven,
  next unit opens when done, Final drive current after the stops before it, `perfect` when passed).

- [ ] Tests: lesson with a trip (11 steps, the trip last before fixes), a Miss trip comes back as
  the same trip at half XP, a Close trip isn't a mistake and keeps Perfect, practice halves it,
  no trip without one; reviewAnswers skips trips. Progress: Final drive locked → current after
  lesson 6 and the Pit stop, ring counts passed trips, 3 passes → done and next unit open,
  a Miss doesn't count, Jump ahead on unit 3 marks units 1–3 done and opens 4, lessons played
  keep Perfect in a jumped unit, practice and Pit stop unchanged.
- [ ] Implement; `dart test` (lesson, course); commit `feat(core): road-trip step, Final drive
  gate and Jump ahead`.

### Task 4: Trip data (`apps/mobile` progress, pack, course)

**Files:** modify `apps/mobile/lib/core/database/database.dart` (`LessonAnswerKind.trip`),
`features/progress/data/progress_dao.dart`, `features/course/data/course_data.dart`
(`passed`, `roadGraphProvider`), `features/me/…` (Road trips count source); tests
`test/features/progress/progress_dao_test.dart`.

**Produces:**

- `ProgressDao.finishLesson` writes trip answers (kind trip, destination, no distance);
  `Future<String> finishTrip({required String cityId, required String unitId, required Difficulty
  difficulty, required Trip trip, required Score score, required bool completesUnit, required
  DateTime startedAt})`; `Future<int> roadTrips()`; `Future<({int xp, int trips})>
  unitSummary(String cityId, String unitId)`; `unitMistakes`, `bestTierByPart` skip trips.
- `final roadGraphProvider = FutureProvider<RoadGraph?>` (keepAlive, from the open pack).
- `courseProvider` passes `passed` (Final drive results: `rightFirst > 0`).

- [ ] Tests: a lesson with a trip answer saves kind trip without a distance, isn't a unit mistake,
  doesn't make its street known, doesn't change last distances; `finishTrip` saves a result and
  its answer, adds XP and the bonus, marks the goal; `roadTrips` counts lesson and drive trips;
  `unitSummary`.
- [ ] Implement; `just gen`; run the DAO test; commit `feat(mobile): road trips in lesson results`.

### Task 5: Route marks in the design system

**Files:** modify `packages/pindoro_design/lib/src/widgets/map_marks.dart` (`PinMark.endpoint`,
`CarMark`), `progress.dart` (`LevelBadge.glyph`); `test/components_test.dart`,
`test/goldens_test.dart` (`route_*`).

**Produces:** `PinMark.endpoint(String letter, {required PindoroColors colors})` rendering like
`PinMark` with `toPng(pixelRatio)`; `class CarMark { const CarMark(this.colors); Future<Uint8List>
toPng(double pixelRatio) }`; `LevelBadge(glyph: PindoroGlyph.trophy, …)`.

- [ ] Component tests (letter drawn, semantics), golden scene `route` (A and B, car, trophy
  shield, light and dark); `just goldens`; existing goldens unchanged; commit
  `feat(design): endpoint pins, the car and the trophy shield`.

### Task 6: The road trip view and the lesson's step

**Files:** create `apps/mobile/lib/features/map/ui/route_view.dart`,
`features/map/ui/route_projection.dart`, `features/map/ui/widgets/route_draw_layer.dart`,
`features/map/ui/widgets/turn_list.dart`; modify `features/map/ui/pindoro_map.dart` (route
overlays: drawn route, best route + chevrons, A/B pins, junction ring, car, ghost, so-far chip;
`trackCameraPosition`, `onCamera`), `features/lesson/ui/lesson_controller.dart` (trip picking,
draft, check, show), `lesson_screen.dart`, `core/settings.dart` (`junction()` haptic), l10n arbs;
tests `test/features/map/route_projection_test.dart`, `test/features/lesson/…`.

**Produces:** `RouteView({area, plateAsk, trip, draft, reveal, topBar, onDraft, onCheck, onShow,
onNext, ghost, nextLabel})`; `typedef RouteReveal = ({Object key, Score score, double drawnM, Route
best, bool shown, List<Widget> chips, String action})`; `LessonPlaying.draft`; controller
`drawTo(RouteDraft)`, `checkRoute()`, `showRoute()`.

- [ ] Projection test: screen ↔ LatLng round trip at zooms 12–17 against MapLibre's 512 px
  world; metres per dp.
- [ ] Spike on the emulator first: drag from A draws, drag elsewhere pans (arena); fix before
  building the rest.
- [ ] Controller tests: a lesson with a graph gets a trip step; drawing to B and Check scores it;
  Show the route is a Miss; the Miss comes back. Widget test: the plate, Check disabled until B,
  the tier sheet, the turn list under `accessibleNavigation` (pick turns to B, check).
- [ ] Implement; run the touched tests; commit `feat(mobile): road trips in lessons`.

### Task 7: Final drive, Jump ahead, Unit complete, R4-61 and Me

**Files:** create `features/lesson/ui/drive_controller.dart`, `drive_screen.dart`,
`unit_done_screen.dart`, `features/lesson/data/unit_done_data.dart`; modify
`features/course/ui/path_screen.dart` (Final drive stop, sheets, locked-unit sheet, R4-61),
`widgets/stop_sheet.dart` (secondary action), `widgets/path_unit.dart` (dim fade),
`core/routes.dart`, `app/router.dart`, `features/me/ui/me_screen.dart`, l10n; tests
`test/features/lesson/drive_controller_test.dart`, `test/app/routing_test.dart`,
`test/features/home_results_test.dart`.

**Produces:** routes `/drive?unit=` (`Routes.driveOf`), `/unit-done?unit=` (`Routes.unitDoneOf`);
`DriveController` (start, drawTo, checkRoute, showRoute, next, retry) saving via `finishTrip`.

- [ ] Tests: drive controller passes a unit after 3 passes (bonus on the third, Unit complete
  next), a Miss offers a new trip and isn't counted, leaving keeps passed trips, Jump ahead on a
  locked unit; routing: Final drive sheet → drive → Unit complete → Path with the next unit open;
  locked-unit sheet buttons; Me's Road trips tile.
- [ ] Implement; run the touched tests; commit `feat(mobile): Final drive, Jump ahead and Unit
  complete`.

### Task 8: Docs, device check, PR

- [ ] Spec status implemented; `docs/TODO.md` (R4c left-outs, R4b lines moved); `apps/mobile/CLAUDE.md`,
  `packages/pindoro_core/CLAUDE.md`, `packages/pindoro_design/CLAUDE.md`, `docs/pack-format.md`;
  `just format`, `just lint`, `just gen-check`.
- [ ] Emulator: publish the format 3 Tbilisi pack to the dev packs server, debug build; play a
  lesson's road trip (ghost, draw, off-road, undo, check, replay, sheet), a Final drive with a
  Miss, Unit complete, R4-61, Jump ahead, Me, dark theme; fixes in their own commit.
- [ ] Push, PR, CI green, merge commit; clean up the worktree.
