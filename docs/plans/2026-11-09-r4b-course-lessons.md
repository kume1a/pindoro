# R4b Course, Path and lessons Implementation Plan

> **For agentic workers:** Implement this plan one task at a time. Steps use checkbox (`- [ ]`)
> syntax for tracking. The user approved this batch's git flow: worktree `../pindoro-r4b`, branch
> `r4b-lessons`, one commit per task, PR, merge commit once CI is green; no stop between tasks.

**Goal:** The course (units per raion, 6 lessons of 4 streets, a Pit stop), the Path tab, lessons
with fixes, Practise again, the unit's Pit stop, Lesson complete and the unlock animation (spec:
`docs/specs/2026-11-09-r4b-course-lessons-design.md`).

**Architecture:** `pindoro_core` owns the rules: `buildCourse` and `courseProgress` (course.dart),
`planLesson`, `LessonRun` and the card facts (lesson.dart). The app stores a city's start raion and
finished lesson results in their own tables; `ProgressDao.finishLesson` writes a result, its
answers and the Pit stop updates in one transaction, and XP, known streets and Welcome read them
too. `features/course` builds the course for the open city and draws the Path; `features/lesson`
plays a step list on one map screen, reusing the Free play pin-drop view, which moves down to
`features/map`.

**Tech Stack:** Flutter 3.47, Riverpod 3 (no codegen), Drift (schema 8), go_router 17, gen-l10n.

## Global Constraints

- Design values only from `pindoro_design` tokens; bundle sizes with no token are literals named
  in a doc comment. Never hand-edit generated code; `just gen` after tokens, l10n or Drift changes.
- Never uppercase UI strings; every string in `app_en.arb` and `app_ka.arb` (Georgian drafts);
  numbers through `formatNumber`, distances through `formatDistance`.
- Layers: `l10n` → `core` → `features/progress` → `features/pack` → `features/map` →
  `features/course` → screen features (`home`, `setup`, `quiz`, `results`, `settings`, `streak`,
  `pitstop`, `me`, `lesson`) → `app`. Screen features never import each other.
- Arrow functions, explicit return types, named exports; no ticket ids in comments; clickable
  things go through `Tappable` (pointer cursor).
- Lesson rules: 4 streets a lesson, 6 lessons a unit, the Pit stop after lesson 3; name 50 / 0;
  fixes and practice half (rounded down); finishing +20; Perfect +50; max 570.
- Run only the touched tests locally; goldens only on Linux (`just goldens`); CI runs the rest.

---

### Task 1: Course rules (`pindoro_core`)

**Files:** create `packages/pindoro_core/lib/src/game/course.dart`, export it; modify
`pack/pack_repository.dart` (`lengthsByDistrict`), `apps/mobile/lib/features/pack/data/sqlite_pack_repository.dart`,
the fakes in `packages/pindoro_core/test/round_inputs_test.dart` and
`apps/mobile/test/features/quiz/round_controller_test.dart`; test
`packages/pindoro_core/test/course_test.dart`.

**Produces:**

- `PackRepository.lengthsByDistrict() → Map<String, Map<String, double>>` (district id → part id
  → metres in it).
- `abstract final class CourseRules { streetsPerLesson = 4; lessonsPerUnit = 6; pitStopAfter = 3 }`
- `enum LessonKind { lesson, practice, pitStop }`
- `typedef CourseLesson = ({int number, List<NamedStreet> streets})`
- `class CourseUnit { int number; District district; List<CourseLesson> lessons; int get
  pitStopAfter; List<NamedStreet> get streets; NamedStreet get … }`
- `List<CourseUnit> buildCourse({required List<District> districts, required Iterable<NamedStreet>
  streets, required Map<String, Map<String, double>> lengthsByDistrict, required String
  startDistrictId})`
- `String? startDistrict(List<District> districts, {LatLng? lastPlayed, required LatLng
  cityCenter})` (raions only: the one holding `lastPlayed`, else the city centre, else the nearest
  centre).
- `enum StopKind { lesson, pitStop, finalDrive }`, `enum StopState { locked, current, done,
  perfect }`, `typedef CourseStop = ({StopKind kind, int? lesson, StopState state})`,
  `typedef LessonOutcome = ({String unitId, LessonKind kind, int? lesson, bool perfect})`,
  `typedef UnitProgress = ({CourseUnit unit, bool open, List<CourseStop> stops, int lessonsDone})`
- `List<UnitProgress> courseProgress(List<CourseUnit> course, Iterable<LessonOutcome> results,
  {required Map<String, int> pitStopSizes})`; `extension on List<UnitProgress> { ({int unit, int
  stop})? get current }`.

- [ ] Tests: raions only; a street joins the raion with most of its length; streets under 150 m
  skipped; class then length order; 24 a unit in lessons of 4; a raion with 5 streets → 1 lesson;
  with 3 → no unit; start first, then by distance; `startDistrict` picks; progress: unit 1 lesson 1
  current; done / Perfect; the Pit stop current after lesson 3, done with a result or size 0;
  practice ignored; Final drive locked; next unit opens after lesson 6; a 2-lesson unit's Pit stop
  after lesson 2.
- [ ] Implement; `dart test` in pindoro_core (course, round inputs) and the mobile quiz controller
  test pass; commit `feat(core): course units, stops and progress`.

### Task 2: Lesson rules (`pindoro_core`)

**Files:** create `packages/pindoro_core/lib/src/game/lesson.dart`, export it; test
`packages/pindoro_core/test/lesson_test.dart`.

**Produces:**

- `abstract final class LessonRules { nameXp = 50; finishXp = 20; perfectXp = 50; tests = 6;
  nameTests = 2; static int half(int xp); static int maxXp }` (570).
- `sealed class LessonStep { NamedStreet street }`: `CardStep(street, number)`,
  `PinStep(street, {bool fix, double? lastDistanceM})`, `NameStep(street, options, {bool fix})`.
- `List<LessonStep> planLesson({required LessonKind kind, required List<NamedStreet> streets,
  required List<NamedStreet> unitStreets, Map<String, double> lastDistances = const {}, Random?
  random})`.
- `typedef StepAnswer = ({LessonStep step, Tier tier, int xp, double? distanceM, DateTime at})`
  (a name answer: Great when right, Miss when wrong; `distanceM` null).
- `class LessonRun` (immutable): `kind`, `steps`, `index`, `answers`, `step`, `total` (steps +
  pending fixes), `finished`, `mistakes`, `answerPin(Score, double distanceM, DateTime at)`,
  `answerName(bool right, DateTime at)`, `next()` (appends the fixes once after the last regular
  step of a lesson), `stepXp`, `bonusXp`, `xp`, `perfect`, `rightFirst`, `tests`, `fixXp`.
- `List<({String streetId, Tier tier})> reviewAnswers(LessonRun run, {required Set<String>
  inPitStop})`.
- `enum RoadType { mainRoad, street, sideStreet }`, `RoadType roadTypeOf(String roadClass)`,
  `int crossingCount(NamedStreet street, Iterable<NamedStreet> others)`,
  `CompassPoint? directionFromCentre(NamedStreet street, LatLng cityCenter)` (null within 1 km).

- [ ] Tests: 4 cards then 6 tests, every street a pin, 2 names, no street twice in a row (many
  seeds); name options distinct names, include the answer; practice no cards; Pit stop pins with
  last distances; XP (pin, name, fix half, practice half, finish, Perfect); fixes appended once in
  order; accuracy; `reviewAnswers` (in the Pit stop: all; not: failed fixes only; practice and Pit
  stop: all); road types; crossings (crossing, touching, parallel); directions.
- [ ] Implement; `dart test test/lesson_test.dart`; commit `feat(core): lesson steps, XP and card facts`.

### Task 3: Data — schema 8

**Files:** `apps/mobile/lib/core/database/database.dart` (`Courses`, `LessonResults`,
`LessonAnswers`, `enum LessonAnswerKind`, v8, `from7To8`), `features/progress/data/progress_dao.dart`,
`drift_schemas/` v8 dump, `test/drift/app_database/migration_test.dart`,
`test/features/progress/progress_dao_test.dart`; callers of `hasFinishedRound` / `firstRoundAt`
(`app/router.dart`, `features/me/data/me_data.dart`).

**Produces (`ProgressDao`):** `courseStart(cityId) → Future<String?>`, `saveCourseStart(cityId,
districtId)`, `lastFreePlayArea(cityId) → Future<Area?>`, `lessonResults(cityId) →
Future<List<LessonResult>>`, `lessonResult(id) → Future<LessonResult>`, `unitMistakes(cityId,
unitId, {required int throughLesson}) → Future<List<String>>`, `lastDistances(cityId, streetIds) →
Future<Map<String, double>>`, `finishLesson({cityId, unitId, kind, lesson, difficulty, LessonRun
run, startedAt, reviews}) → Future<String>`, `lessonsDone() → Future<int>`, `hasPlayed()`,
`firstPlayedAt()`; `totalXp`, `xpOn`, `bestTierByPart`, `recentCityIds` include lessons;
`progressChangesProvider` ticks on the new tables.

- [ ] Tests: migration 7 → 8; `finishLesson` writes the result and answers; total and today's XP
  add it; known from a Great pin, a right first name, not a right name fix; reviews applied only as
  given; the goal day marked; `unitMistakes` first tries in order through lesson 3; `lastDistances`
  latest of rounds and lessons; `hasPlayed` with only a lesson; `lessonsDone`.
- [ ] `just gen`; migration and progress tests pass; commit `feat(mobile): lesson results and the
  course start in the database`.

### Task 4: Design widgets

**Files:** create `packages/pindoro_design/lib/src/widgets/lesson_path.dart` (`PathStop`,
`Signpost`, `LessonRoad`) and `lesson.dart` (`PlateChoice`, `FeedbackBar`), exports,
`packages/pindoro_design/CLAUDE.md`, `test/components_test.dart` (+ goldens `path_*`,
`lesson_*` via `just goldens`).

**Produces:**

- `enum PathStopLook { done, perfect, current, review, locked }`;
  `PathStop({required PathStopLook look, required PindoroGlyph glyph, bool big = false, double?
  ring, String? tip, double scale = 1, required String semanticLabel, VoidCallback? onTap})`
  (current floats ±4 dp over 1.6 s unless reduce motion).
- `Signpost({required int number, required String line, required String title, bool locked =
  false, required String semanticLabel, VoidCallback? onTap})`.
- `LessonRoad({required List<Offset> points, required double driven, double opacity = 1})`:
  asphalt + kerbs + lane up to `driven` (segment units), soft road after; the part from
  `driven.floor()` to `driven` gets accent dashes while `driven` is fractional.
- `enum PlateChoiceState { idle, selected, right, wrong, dim }`; `PlateChoice({required String
  name, String? sub, required PlateChoiceState state, VoidCallback? onTap, String? semanticLabel})`
  (shakes 3 × 6 dp over 300 ms when it turns wrong).
- `FeedbackBar({required bool right, required String title, String? body, String? xpLabel,
  required String action, required VoidCallback onAction})`.

- [ ] Tests: a stop reads its label and taps; a locked stop still taps; the signpost label; a plate
  choice is a selectable radio and reports taps; the feedback bar action; goldens.
- [ ] `flutter test test/components_test.dart` (goldens skipped off Linux); `just goldens`;
  commit `feat(design): lesson path stops, signpost, road, plate choice and feedback bar`.

### Task 5: The Path tab

**Files:** create `features/course/data/course_data.dart` (`coursePlanProvider`,
`courseProvider`, `pathRetapProvider`, `pathUnlockProvider`), `features/course/ui/path_screen.dart`,
`features/course/ui/widgets/{path_unit.dart,stop_sheet.dart}`; move Home's top row into
`features/progress/ui/play_top_bar.dart`; modify `app/router.dart` (4 branches, `/path`,
`startLocation`), `app/tab_shell.dart`, `core/routes.dart`, `features/me` (Lessons tile, unit line,
row opens the Path), `test/architecture_test.dart`, `.arb` files; tests `test/app/routing_test.dart`,
`test/features/course/path_test.dart`, `test/app/home_results_test.dart` (Me).

**Produces:** `Routes.path = '/path'`, `Routes.lesson(unitId, n)`, `Routes.practice(unitId, n)`,
`Routes.unitPitStop(unitId)`, `Routes.lessonDone(resultId)`;
`typedef CourseData = ({PackRepository pack, Map<String, NamedStreet> streets, List<UnitProgress>
units, Map<String, LessonResult> firstResults, Map<String, List<String>> pitStops})` (null when the
city has no raions); `pathUnlockProvider` holds the stop to play the unlock from.

- [ ] Tests: the app opens on the Path after Welcome; Path · Free play · Pit stop · Me; back from
  Free play lands on the Path; the Path shows unit 1 with lesson 1 current; tap → lesson sheet;
  a locked stop shows its bubble; a done lesson's sheet offers Practise again; a city without
  raions shows the Free play message; Me's Lessons tile and city row.
- [ ] Implement; touched tests pass; commit `feat(mobile): the Path tab with the course`.

### Task 6: Lessons

**Files:** move `features/quiz/ui/widgets/{question_plate,reticle,round_reveal}.dart` to
`features/map/ui/widgets/` and extract `features/map/ui/pin_drop_view.dart` from `QuizScreen`;
move `features/results/ui/level_up_screen.dart` and Results' level row to `features/progress/ui/`;
create `features/lesson/ui/{lesson_controller.dart,lesson_screen.dart,lesson_done_screen.dart}`,
`features/lesson/ui/widgets/{new_street_sheet.dart,name_question.dart,fixes_intro.dart}`,
`features/lesson/data/lesson_done_data.dart`; router routes; `.arb` files; tests
`test/features/lesson/lesson_test.dart` and the quiz tests.

- [ ] Tests: a lesson played through (cards, pins, names, a wrong name and its fix) writes one
  result and lands on Lesson complete; leaving asks and writes nothing; practice has no cards and
  half XP; the unit's Pit stop plays its streets; Lesson complete numbers; quiz tests unchanged.
- [ ] Implement; touched tests pass; commit `feat(mobile): lessons, practice, the unit's Pit stop
  and Lesson complete`.

### Task 7: Unlock animation

**Files:** `features/course/ui/path_screen.dart`, `features/course/ui/widgets/path_unit.dart`,
`features/lesson/ui/lesson_done_screen.dart` (sets `pathUnlockProvider`), test
`test/features/course/path_test.dart`.

- [ ] Tests: after Continue the Path settles with the next stop current; reduce motion shows the
  final state at once.
- [ ] Implement; commit `feat(mobile): the Path unlocks the next stop`.

### Task 8: Docs, checks, PR

- [ ] `apps/mobile/CLAUDE.md`, `packages/pindoro_core` notes, `docs/TODO.md` (out of scope list),
  spec status implemented; `just lint`, `just gen-check`; emulator check (fixture + Tbilisi, dark,
  200 %); commit `docs: R4b course and lessons in the spec, plan, mobile guide and TODO`; push; PR;
  merge commit once CI is green.
