# R4d First Launch Implementation Plan

> **For agentic workers:** Implement this plan one task at a time. Steps use checkbox (`- [ ]`)
> syntax for tracking. The user approved building without a pause per task; each task ends in one
> commit (git-flow answer: worktree, commit per part, PR, merge commit when CI is green).

**Goal:** Existing players get What's new and a placement from their known streets; new players
pick their first district; a fresh course shows a "Start here" coach mark.

**Architecture:** Placement is a pindoro_core rule (`placeLessons`, `LessonKind.placed` read by
`courseProgress`) saved as 0-XP `lesson_result` rows, so no schema change. The start location is
derived (`course` row → Path, played → What's new). What's new, placement and the picker live in
`features/setup`; their data comes from `features/course/data` and `features/progress/data`.

**Tech Stack:** Dart 3 / Flutter, Riverpod 3 (no codegen), go_router, Drift, gen-l10n ARB.

## Global Constraints

- Spec: `docs/specs/2026-11-09-r4d-first-launch-design.md`.
- No schema change: `lesson_result.kind` gains the text-enum value `placed`.
- `CourseRules.placedKnown = 3`.
- Every UI string from `app_en.arb` + `app_ka.arb` (Georgian drafts); never uppercase; numbers via
  `formatNumber`.
- `pindoro_core` has no Flutter imports. Screen features never import each other
  (`test/architecture_test.dart`).
- Run only the touched tests locally; CI runs the rest. No ticket ids in comments.

---

### Task 1: Placement and the start-district order in pindoro_core

**Files:**

- Modify: `packages/pindoro_core/lib/src/game/course.dart`
- Test: `packages/pindoro_core/test/course_test.dart`

**Interfaces:**

- Produces: `CourseRules.placedKnown` (int 3); `LessonKind.placed`;
  `List<(String, int)> placeLessons(List<CourseUnit> units, Set<String> known)`;
  `List<District> raionsFrom(List<District> raions, LatLng from)`; `courseProgress` reading
  placed outcomes.

- [ ] **Step 1: Failing tests** (append to `course_test.dart`, in `main`)

```dart
LessonOutcome _placed(String unit, int n) => (
  unitId: unit,
  kind: LessonKind.placed,
  lesson: n,
  perfect: false,
  passed: false,
);

group('placement', () {
  final inA = _many('a', 24);
  final inB = _many('b', 24);
  final inC = _many('c', 24);
  final three = buildCourse(
    districts: [a, b, c],
    streets: [...inA.streets, ...inB.streets, ...inC.streets],
    lengthsByDistrict: {'a': inA.lengths, 'b': inB.lengths, 'c': inC.lengths},
    startDistrictId: 'a',
  ); // a, c, b

  test('a lesson is placed with 3 of its 4 streets known', () {
    final lesson1 = [for (final s in three.first.lessons.first.streets) s.id];
    expect(placeLessons(three, lesson1.take(2).toSet()), isEmpty);
    expect(placeLessons(three, lesson1.take(3).toSet()), [('a', 1)]);
    expect(placeLessons(three, lesson1.toSet()), [('a', 1)]);
  });

  test('placed lessons are done, never Perfect, and counted', () {
    final p = courseProgress(three, [
      _placed('a', 1),
      _placed('a', 2),
      _placed('a', 5),
    ], pitStopSizes: const {});
    expect(p.first.stops.take(3).map((s) => s.state), [
      StopState.done,
      StopState.done,
      StopState.current,
    ]);
    expect(p.first.stops[5].state, StopState.done, reason: 'lesson 5');
    expect(p.first.lessonsDone, 3);
    expect(p.current, (unit: 0, stop: 2));
  });

  test('a fully placed unit is done once the one before it is', () {
    final p = courseProgress(three, [
      for (var n = 1; n <= 6; n++) _placed('a', n),
      for (var n = 1; n <= 6; n++) _placed('b', n),
      _placed('c', 1),
    ], pitStopSizes: const {});
    expect([for (final u in p) u.done], [true, false, false]);
    expect(p.first.stops.last.state, StopState.done, reason: 'a check');
    expect(p[1].stops.first.state, StopState.done, reason: 'c is open');
    expect(p[2].open, isFalse);
    expect(p[2].stops.first.state, StopState.locked, reason: 'b is locked');
    expect(p[2].lessonsDone, 0);
    expect(p.current, (unit: 1, stop: 1));

    final cDriven = courseProgress(three, [
      for (var n = 1; n <= 6; n++) _placed('a', n),
      for (var n = 1; n <= 6; n++) _placed('b', n),
      for (var i = 0; i < 3; i++) _trip('c'),
    ], pitStopSizes: const {});
    expect([for (final u in cDriven) u.done], [true, true, true]);
    expect(cDriven.current, isNull);
  });

  test('raionsFrom: the raion holding the point, then by distance', () {
    const inB = LatLng(41.705, 44.755);
    expect([for (final d in raionsFrom([a, b, c], inB)) d.id], ['b', 'c', 'a']);
    const westOfA = LatLng(41.705, 44.60);
    expect([for (final d in raionsFrom([c, b, a], westOfA)) d.id], [
      'a',
      'c',
      'b',
    ]);
  });
});
```

- [ ] **Step 2: Run, expect compile failures** —
  `cd packages/pindoro_core && dart test test/course_test.dart` → `placed`, `placeLessons`,
  `raionsFrom` undefined.

- [ ] **Step 3: Implement** in `course.dart`:

```dart
// CourseRules
  /// Known streets (of 4) that place a lesson for a player who already played.
  static const int placedKnown = 3;

/// ... or a lesson marked done by placement.
enum LessonKind { lesson, practice, pitStop, finalDrive, placed }

/// The lessons a player who already knows [known] (street ids) skips: every
/// lesson with [CourseRules.placedKnown] of its streets known, in course order.
List<(String, int)> placeLessons(List<CourseUnit> units, Set<String> known) => [
  for (final u in units)
    for (final l in u.lessons)
      if (l.streets.where((s) => known.contains(s.id)).length >=
          CourseRules.placedKnown)
        (u.id, l.number),
];

/// [raions] from [from]: the one holding it first, then by distance.
List<District> raionsFrom(List<District> raions, LatLng from) {
  double away(District d) =>
      boundaryContains(d.boundary, from) ? -1 : distanceBetween(from, d.center);
  return [...raions]..sort((a, b) => away(a).compareTo(away(b)));
}
```

`courseProgress`: collect `placed` (`case LessonKind.placed: placed.add((r.unitId, r.lesson!))`),
then after the backward Jump-ahead pass:

```dart
  bool allPlaced(CourseUnit u) =>
      u.lessons.every((l) => placed.contains((u.id, l.number)));
  for (var i = 0; i < course.length; i++) {
    if (!done[i] && allPlaced(course[i]) && (i == 0 || done[i - 1])) {
      done[i] = true;
    }
  }
```

and per unit `bool lessonDone(int n) => lessons.containsKey((unit.id, n)) ||
(unitOpen && placed.contains((unit.id, n)));`. Doc comments say what placement adds.

- [ ] **Step 4: Run** `dart test test/course_test.dart` → all pass; `dart analyze`.
- [ ] **Step 5: Commit** `feat(core): placement from known streets and the start-district order`.

---

### Task 2: Placement data and the first-launch start location (app)

**Files:**

- Modify: `apps/mobile/lib/features/progress/data/progress_dao.dart` (`hasCourse`, `place`)
- Modify: `apps/mobile/lib/app/router.dart` (`startLocation`, `/whats-new` route added in Task 3)
- Modify: `apps/mobile/lib/core/routes.dart` (`whatsNew`, `startDistrict`, `cityForCourse`)
- Modify: `apps/mobile/lib/core/location.dart` (`ifAllowed`)
- Modify: `apps/mobile/lib/features/course/data/course_data.dart` (`CourseData.placed`,
  `CourseData.fresh`, `Placement`, `placementProvider`)
- Modify: `apps/mobile/lib/features/lesson/data/unit_done_data.dart` (next = first not done)
- Modify: `apps/mobile/lib/features/lesson/ui/lesson_done_screen.dart` (`placed` arm)
- Test: `apps/mobile/test/features/progress/progress_dao_test.dart`

**Interfaces:**

- Consumes: Task 1.
- Produces:
  - `Future<bool> ProgressDao.hasCourse()`
  - `Future<void> ProgressDao.place(String cityId, List<(String, int)> lessons)`
  - `Routes.whatsNew = '/whats-new'`, `Routes.startDistrict = '/start-district'`,
    `Routes.cityForCourse = '/city?course=1'`
  - `Future<LatLng?> LocationService.ifAllowed()`
  - `typedef Placement = ({CoursePlan plan, Set<String> known, List<(String, int)> placed,
    List<UnitProgress> units})`; `placementProvider` (`FutureProvider.autoDispose<Placement?>`)
  - `CourseData.placed: Set<(String, int)>`, `CourseData.fresh: bool` (no results in the city)

- [ ] **Step 1: Failing tests** in `progress_dao_test.dart`:
  - replace "welcome shows until a first round is finished or saved; then the Path" with the
    table: nothing → welcome; saved first round → home; finished round → whats-new; plus a course
    row → path; a course row alone (new player who picked) → path.
  - the lesson test's final `startLocation` expectation saves a course start first.
  - `place` writes `placed` rows that leave `totalXp`, `lessonsDone` and `bestTierByPart`
    unchanged and come back from `lessonResultsIn`.
- [ ] **Step 2: Run** `flutter test test/features/progress/progress_dao_test.dart` → fails.
- [ ] **Step 3: Implement.**

```dart
  /// Whether any city's course has started (its start raion is saved).
  Future<bool> hasCourse() async =>
      await (select(courses)..limit(1)).getSingleOrNull() != null;

  /// Marks [lessons] (unit id, lesson number) of [cityId] done by placement:
  /// 0 XP, no answers.
  Future<void> place(String cityId, List<(String, int)> lessons) =>
      batch((b) => b.insertAll(lessonResults, [
        for (final (unitId, n) in lessons)
          LessonResultsCompanion.insert(
            cityId: cityId,
            unitId: unitId,
            kind: LessonKind.placed,
            lesson: Value(n),
            difficulty: Difficulty.medium,
            xp: 0,
            perfect: false,
            rightFirst: 0,
            tests: 0,
            durationMs: 0,
          ),
      ]));
```

```dart
/// A started course opens on the Path. A player with a finished round and
/// no course yet (an update from Free play only) sees What's new; a saved
/// first round reopens Free play; anyone else starts at Welcome.
Future<String> startLocation(AppDatabase db) async {
  final progress = ProgressDao(db);
  if (await progress.hasCourse()) return Routes.path;
  if (await progress.hasPlayed()) return Routes.whatsNew;
  return await progress.resumableRound(DateTime.now()) != null
      ? Routes.home
      : Routes.welcome;
}
```

```dart
  /// The last known position when location is on and already allowed; never
  /// asks and never waits for a fix.
  Future<LatLng?> ifAllowed() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return null;
      }
      final p = await Geolocator.getLastKnownPosition();
      return p == null ? null : LatLng(p.latitude, p.longitude);
    } on Object {
      return null;
    }
  }
```

`course_data.dart`: `courseProvider` adds `placed: {for (r in results) if (r.kind ==
LessonKind.placed) (r.unitId, r.lesson!)}` and `fresh: results.isEmpty`.

```dart
/// What placement gives the open city's course: the streets the player
/// knows, the lessons they place and the course with them. Reading it saves
/// the course's default start (`coursePlanProvider`). Null without a course.
typedef Placement = ({
  CoursePlan plan,
  Set<String> known,
  List<(String, int)> placed,
  List<UnitProgress> units,
});

final placementProvider = FutureProvider.autoDispose<Placement?>((ref) async {
  final plan = await ref.watch(coursePlanProvider.future);
  if (plan == null) return null;
  final dao = ref.watch(progressDaoProvider);
  final known = knownStreetIds(
    await dao.bestTierByPart(plan.pack.city().id),
    plan.streets,
  );
  final placed = placeLessons(plan.units, known);
  return (
    plan: plan,
    known: known,
    placed: placed,
    units: courseProgress(plan.units, [
      for (final (unitId, n) in placed)
        (unitId: unitId, kind: LessonKind.placed, lesson: n, perfect: false,
         passed: false),
    ], pitStopSizes: const {}),
  );
});
```

`unitDoneProvider`: `next` = the first unit after `unitId` in `courseProvider`'s progress that
isn't done. `lesson_done_screen.dart`: `LessonKind.lesson || LessonKind.finalDrive ||
LessonKind.placed => l10n.lessonDoneTitle` (a placed result never opens it).

- [ ] **Step 4: Run** the progress DAO test and `flutter analyze` → green.
- [ ] **Step 5: Commit** `feat(mobile): placement rows and the first-launch start location`.

---

### Task 3: What's new and placement

**Files:**

- Create: `apps/mobile/lib/features/setup/ui/whats_new_screen.dart`
- Create: `apps/mobile/lib/features/setup/ui/widgets/whats_new_road.dart` (the intro's road)
- Modify: `apps/mobile/lib/app/router.dart` (`GoRoute(path: Routes.whatsNew, ...)`)
- Modify: `apps/mobile/lib/l10n/app_en.arb`, `app_ka.arb`
- Test: `apps/mobile/test/features/setup/whats_new_test.dart`

**Interfaces:**

- Consumes: `placementProvider`, `ProgressDao.place`, `Routes.whatsNew`, `Routes.lessonOf`.
- Produces: `WhatsNewScreen` (route `/whats-new`).

Strings (en): `whatsNewChip` "New in 2.0"; `whatsNewTitle` "{city} is now a course";
`whatsNewBody` "Learn the city district by district. Everything you’ve already learned counts.";
`whatsNewLessons` / `whatsNewLessonsLine` "Lessons on a path" / "New streets first, then a short
test and a road trip."; `whatsNewTrips` / `whatsNewTripsLine` "Road trips" / "Draw the shortest
drive between two points."; `whatsNewFreePlay` / `whatsNewFreePlayLine` "Free play is still here" /
"Quick rounds in any area, just like before."; `whatsNewShowPath` "Show me my path";
`placementTitle` "You start in Unit {number}"; `placementAllTitle` "You know every unit";
`placementBody` "You already know {count} streets in {city}, so your course skips what you know."
(count as a formatted String); `placementUnit` "Unit {number} · {district}"; `placementComplete`
"Complete · you know {known} of its {total} streets"; `placementCurrent` "{done} of {total}
lessons done · lesson {lesson} is next"; `placementOpensAfter` "Opens after {district}";
`placementFromUnit1` "Start from Unit 1 instead"; `placementStartLesson` "Start lesson {number}".

Screen: a `ConsumerStatefulWidget` with `Placement? _placed` (null = intro) and `bool _busy`.

- Intro: `PageScaffold(title: whatsNewTitle(city), showBack: false, footer: PindoroButton(
  whatsNewShowPath, onPressed: _busy ? null : _showPath))` with children `WhatsNewRoad()`, a chip
  (`LipBox` in `primarySoft`, `labelMd`, `primaryText`), the body and a `ListGroup` of three
  `ListRow`s with `RowTile(PindoroGlyph.signpost | car | map)`. The city name comes from the open
  pack's `city()` (`packRepositoryProvider`), falling back to an empty title while it loads.
- `_showPath`: `_busy = true`; `final p = await ref.read(placementProvider.future)` (catch →
  null). No placement or nothing placed → `context.go(Routes.path)`. `p.units.current == (unit: 0,
  stop: 0)` → `await dao.place(...)`, go to the Path. Otherwise `setState(() => _placed = p)`.
- Placement: `PageScaffold(title: placementTitle(n) | placementAllTitle, showBack: false,
  footer: Column(tertiary placementFromUnit1, primary placementStartLesson(m) | whatsNewShowPath))`,
  children: `Pindo(PindoExpression.proud, height: 104)`, the body, a `ListGroup` with up to three
  rows (previous unit complete: `RowTile(check)`; current: `RowTile(play, face: primary, ink:
  onPrimary, lip: primaryLip)`; next: `RowTile(lock, face: path node locked fill, ink: locked
  icon)`), built from `p.units` and `p.units.current`.
- Start lesson: `await dao.place(city, p.placed)`; `final router = GoRouter.of(context);
  router.go(Routes.path); router.push(Routes.lessonOf(unitId, m))`.
- From Unit 1: `context.go(Routes.path)` (nothing saved).
- `PopScope(canPop: false)`: back in the placement state → intro; in the intro → go to the Path.

`WhatsNewRoad`: a 170 dp tall `Stack` with `LessonRoad(points: [start, done, perfect, current],
driven: 2)` and three non-interactive `PathStop`s (done/check, perfect/star, current/play with
`big: true, ring: 0`), wrapped in `ExcludeSemantics` + `IgnorePointer`; x positions at 116, 210
and 300 of 358 dp, y at 74, 124 and 72 (canvas `WhatsNewScreen` intro).

- [ ] **Step 1: Failing widget test** `whats_new_test.dart` (same harness as `routing_test`: memory
  DB, fixture pack, `pindoroMapBuilderProvider` → `SizedBox`): seed a finished round whose answers
  make lesson 1 and 2 of the fixture's unit known (Great on 3 of 4 streets each), no course row.
  - pump `/whats-new` → "Tbilisi is now a course"; tap "Show me my path" → "You start in Unit 1",
    "2 of 6 lessons done · lesson 3 is next"; tap "Start lesson 3" → the lesson screen; the DB has
    2 `placed` rows.
  - "Start from Unit 1 instead" → the Path, no `placed` rows, a course row exists.
  - nothing known → "Show me my path" lands on the Path.
- [ ] **Step 2: Run** → fails (no route / screen).
- [ ] **Step 3: Implement** the screen, the road widget, the route and the strings (+ ka drafts);
  `just gen` for l10n.
- [ ] **Step 4: Run** the test + `flutter analyze` → green.
- [ ] **Step 5: Commit** `feat(mobile): What's new and placement for players from Free play`.

---

### Task 4: The start-district picker for new players

**Files:**

- Create: `apps/mobile/lib/features/setup/data/start_districts.dart`
- Create: `apps/mobile/lib/features/setup/ui/start_district_screen.dart`
- Modify: `apps/mobile/lib/features/setup/ui/city_screen.dart` (`course` flag)
- Modify: `apps/mobile/lib/features/setup/ui/welcome_screen.dart` (Choose a city → for the course)
- Modify: `apps/mobile/lib/app/router.dart` (`/city?course=1`, `/start-district`)
- Modify: `app_en.arb`, `app_ka.arb`
- Test: `apps/mobile/test/app/routing_test.dart`

**Interfaces:**

- Consumes: `raionsFrom`, `buildCourse`, `knownCounts`, `compassPoint`, `LocationService.ifAllowed`,
  `ProgressDao.saveCourseStart`, `coursePlanProvider`.
- Produces: `StartDistrict = ({District district, int streets, StartHint hint, CompassPoint
  direction})`, `enum StartHint { nearYou, centre, direction }`, `startDistrictsProvider`
  (`FutureProvider.autoDispose<({City city, List<StartDistrict> rows})>`), `StartDistrictScreen`,
  `CityScreen(course: bool)`.

```dart
final startDistrictsProvider = FutureProvider.autoDispose((ref) async {
  final streetsFuture = ref.watch(cityStreetsProvider.future);
  final pack = await ref.watch(packRepositoryProvider.future);
  final streets = await streetsFuture;
  final city = pack.city();
  final raions = [
    for (final d in pack.districts())
      if (d.kind == DistrictKind.district) d,
  ];
  final taught = {
    for (final u in buildCourse(
      districts: raions,
      streets: {...streets.values},
      lengthsByDistrict: pack.lengthsByDistrict(),
      startDistrictId: raions.firstOrNull?.id ?? '',
    ))
      u.id,
  };
  final here = await ref.watch(locationServiceProvider).ifAllowed();
  final located = here != null && city.bbox.contains(here);
  final counts = knownCounts(
    streets: streets,
    partsByDistrict: pack.partsByDistrict(),
    known: const {},
  ).byDistrict;
  final ordered = raionsFrom(
    [for (final d in raions) if (taught.contains(d.id)) d],
    located ? here : city.center,
  );
  return (
    city: city,
    rows: [
      for (final (i, d) in ordered.indexed)
        (
          district: d,
          streets: counts[d.id]?.total ?? 0,
          hint: located && i == 0
              ? StartHint.nearYou
              : boundaryContains(d.boundary, city.center)
              ? StartHint.centre
              : StartHint.direction,
          direction: compassPoint(city.center, d.center),
        ),
    ],
  );
});
```

Screen: `PackPending` until the pack is open; then a page with a back row (`PindoroIconButton(back,
semanticLabel: startBack)` + the city name in `labelLg`), headline `startTitle`, body `startBody`,
a `ListGroup` of `ListRow`s (title = `districtName`, subtitle = `startStreets(n) · hint`, trailing
`PindoroIcon(checkCircle)` on the selected row, wrapped in `Semantics(inMutuallyExclusiveGroup:
true, checked: selected)`), the footer label `startCount(n)` and the button `startIn(district)`.
Start in: `await dao.saveCourseStart(city.id, selected.id)`; `ref.invalidate(coursePlanProvider)`;
`context.go(Routes.path)`. No rows (no raions) → `context.go(Routes.path)` once loaded.

Strings (en): `startTitle` "Where do you want to start?";
`startBody` "Your course goes district by district. Start where you live or where you need it
most; the rest follow, nearest first."; `startStreets` plural "{count} streets"; `startHint`
"{hint, select, near{nearest to you} centre{city centre} n{north} ne{north-east} e{east}
se{south-east} s{south} sw{south-west} w{west} nw{north-west} other{}}"; `startCount` "{count}
districts · from OpenStreetMap" (plural); `startIn` "Start in {district}".

City: `CityScreen({super.key, this.course = false})`; `_pick` pushes `Routes.startDistrict` when
`course`, else `Routes.area`. Router: `CityScreen(course: state.uri.queryParameters
.containsKey('course'))`. Welcome: the first-run button pushes `Routes.cityForCourse`; the resume
branch's "Find a city" keeps `Routes.city`.

- [ ] **Step 1: Failing test** in `routing_test.dart`: "first run: welcome → city → first district
  → the Path": Welcome → Choose a city → Tbilisi → "Where do you want to start?" shows the
  fixture's raion with "city centre" or a direction → Start in … → the Path with lesson 1 current;
  `courseStart('tbilisi')` is the raion. The old first-run test now starts at `/city` (Free play):
  Tbilisi → Area → Difficulty → round.
- [ ] **Step 2: Run** → fails.
- [ ] **Step 3: Implement.** `just gen`.
- [ ] **Step 4: Run** `flutter test test/app/routing_test.dart test/architecture_test.dart` and
  `flutter analyze` → green.
- [ ] **Step 5: Commit** `feat(mobile): new players pick the district their course starts in`.

---

### Task 5: The Path's "Start here" coach mark and placed lessons

**Files:**

- Modify: `apps/mobile/lib/features/course/ui/widgets/path_unit.dart` (`coach`)
- Modify: `apps/mobile/lib/features/course/ui/path_screen.dart`
- Modify: `apps/mobile/lib/features/course/data/course_data.dart` (`pathCoachProvider`)
- Modify: `app_en.arb`, `app_ka.arb`
- Test: `apps/mobile/test/app/routing_test.dart` (group "the Path")

**Interfaces:**

- Consumes: `CourseData.fresh`, `CourseData.placed`.
- Produces: `PathUnit.coach: ({int stop, LockedNote note})?`; `pathCoachProvider`
  (`NotifierProvider<PathCoach, bool>`, true once hidden this launch).

- `PathUnit`: a `coach` shows the same `CoachBubble(pointsUp: true)` under its stop while no
  locked note is showing.
- `PathScreen._path`: `coach` for unit 0 when `data.fresh && current == (unit: 0, stop: 0) &&
  !ref.watch(pathCoachProvider)`: title `pathCoachTitle` "Start here", body `pathCoachBody` "Your
  first lesson: {count} streets in {district}, then a short test."; the current stop's `tip` is
  null while it shows. The scroll view is wrapped in `Listener(onPointerDown: (_) =>
  ref.read(pathCoachProvider.notifier).hide())`.
- `_openStop` for a done lesson without a first result that is in `data.placed`: body
  `[pathSheetPlacedBody, pathSheetPractiseBody]`, `pathSheetPlacedBody` "You already knew these
  streets when the course started."

- [ ] **Step 1: Failing tests**: "a new course shows Start here until a tap" (fresh course → "Start
  here" visible, tap anywhere → gone); "a placed lesson's sheet" (seed a course row + a placed row
  for lesson 1 → tap lesson 1 → "You already knew these streets when the course started." and
  "Practise again"; no "Start here").
- [ ] **Step 2: Run** → fails.
- [ ] **Step 3: Implement.** `just gen`.
- [ ] **Step 4: Run** `flutter test test/app/routing_test.dart` and `flutter analyze` → green.
- [ ] **Step 5: Commit** `feat(mobile): the Path's Start here coach mark and placed lessons`.

---

### Task 6: Device check, docs and PR

- [ ] `just dev` from the worktree with `TILES_DIR` → the main checkout's `infra/tiles`; run the app
  on the emulator.
  - New player: clear the app data → Welcome → Choose a city → Tbilisi → picker → Start in … →
    Path with "Start here".
  - Existing player: seed finished rounds with known streets, delete `course` and `lesson_result`
    rows → What's new → placement → Start lesson n; and Start from Unit 1 instead.
  - Dark theme; screen-reader labels on the picker rows.
- [ ] Fix what the device shows, in its own commit.
- [ ] Docs: `docs/TODO.md` (R4d left-outs; drop the R4b "R4d:" line), `apps/mobile/CLAUDE.md`
  (start location, What's new, picker, placement), `packages/pindoro_core/CLAUDE.md` (placement),
  the spec's status → implemented. Commit `docs: R4d first launch in the spec, plan, guides and
  TODO`.
- [ ] `just lint`, `just gen-check`; push; PR; CI green → `gh pr merge --merge`; remove the
  worktree.
