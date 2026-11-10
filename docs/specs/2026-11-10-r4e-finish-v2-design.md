# R4e · v2.0 — finish: Unit guide, Hear the name, lesson resume, Path loading, turn list setting

- Date: 2026-11-10
- Status: implemented
- Builds on: R4b (`docs/specs/2026-11-09-r4b-course-lessons-design.md`), R4c
  (`docs/specs/2026-11-09-r4c-road-trips-design.md`), R4d
  (`docs/specs/2026-11-09-r4d-first-launch-design.md`)
- Source: `docs/design/v1-screens.md` § R4 · v2.0; claude.ai screens canvas boards R4-02 (rules:
  resume), R4-10 (Path `loading`), R4-11 (See the streets), R4-13 (Unit guide), R4-20 (Hear the
  name), R4-34 (turn by turn); components `UnitGuideScreen`, `PathScreen` (`loading`, signpost
  book button), `LessonScreen` (`intro1`), `RouteScreen` (`list`)

## Goal

The designed v2.0 parts that R4b–R4d left out: the Unit guide and "See the streets", Hear the name
on new-street cards, a lesson killed by the OS resuming at its step, the Path's loading skeletons,
and Settings → Accessibility → "Choose turns from a list".

## Decisions

| Topic          | Decision                                                                                                                                                                                                |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Resume entry   | The next cold start opens the saved lesson at its step (`startLocation`); ✕ Leave goes to the Path as today. No sheet copy changes                                                                      |
| Resume store   | One row (`saved_lesson`): the lesson's args, a random seed, the pack version, start and last-save times, and its progress as JSON (step index + answers). Re-planned from the seed and replayed on open |
| What resumes   | Lessons, practice and the unit's Pit stop (everything `LessonController` plays). The Final drive is unchanged (it already keeps its passed trips)                                                       |
| Resume expiry  | 24 h after the last save (`LessonRules.resumeFor`). ✕ Leave, finishing, a different lesson starting, or a replay that no longer fits the pack drop the row                                              |
| Resume step    | The step after the last answered one (a reveal that was showing is skipped), or the saved card step                                                                                                     |
| Lesson time    | A resumed lesson's clock continues from where it stopped: `startedAt` moves forward by the time the app was dead                                                                                        |
| Unit guide map | `PindoroMap` in a 176 dp card: the unit's district as the area (outside dimmed), the unit's streets in yellow, no controls, pan and pinch                                                               |
| Unit guide tip | Generated only: the streets' main axis ("Most of Vake's streets run north to south."), no editorial text per district                                                                                   |
| Unit titles    | Still none: the guide's signpost shows the district, as the Path does                                                                                                                                   |
| Hear the name  | `flutter_tts`; speaks the name as shown (local or English setting), `ka-GE` when it has Georgian letters, else `en-US`. Hidden when the device has no voice for it. Not behind the Sound toggle         |
| Skeleton       | A new `Skeleton` block in pindoro_design (`.pd-skel`: sunken, a raised shimmer every 1.4 s, still under reduce motion)                                                                                  |
| Turn list      | `user_settings.turn_list`; road trips show the turn list when a screen reader is on or the setting is on                                                                                                |
| Schema         | Version 9: `saved_lesson` table and the `turn_list` column, one migration                                                                                                                               |
| Git            | Branch `r4e-finish-v2` in the main checkout, one commit per part, one PR                                                                                                                                |

## Rules (`pindoro_core`)

### Lesson resume (`game/lesson.dart`)

- `LessonRules.resumeFor = Duration(hours: 24)`.
- `typedef SavedAnswer = ({int step, String streetId, Tier tier, int xp, double? distanceM, DateTime at})`:
  an answer by the index of the step it answered.
- `LessonRun.saved`: its answers as `SavedAnswer`s (`step` = the index of the answered step in
  `steps`).
- `LessonRun.restore(kind, steps, answers, index)`: a new run over `steps` that walks `next()` up to
  each answer's step and records it (same tier, XP, distance and time), then walks on to `index`.
  Fixes are appended by `next()` as when playing. Returns null when an answer's step isn't a test
  step or its street id differs (the plan no longer fits).
- `LessonRun.resumeAt`: where a restored run continues: past its last answer when that answer is
  on the current step.

### Street axis (`game/course.dart`)

- `enum StreetAxis { northSouth, northeastSouthwest, eastWest, northwestSoutheast }`.
- `StreetAxis? mainAxis(List<NamedStreet> streets)`: each segment's bearing folded to 0–180°,
  weighted by its length, in four 45° bins centred on 0°, 45°, 90° and 135°; the largest bin when it
  holds at least 40 % of the length (`CourseRules.axisShare`), else null.

## Data (`apps/mobile`, schema 9)

- `UserSettings.turnList`: bool, default false. `SettingsDao.setTurnList({required bool on})`.
- `SavedLessons` table (`saved_lesson`, one row, `id` = 1): `cityId`, `unitId`, `kind`
  (`LessonKind`), `lesson` (nullable), `difficulty`, `packVersion`, `seed`, `startedAt`,
  `savedAt`, `progress` (JSON `{"index": n, "answers": [{"step", "street", "tier", "xp",
  "distance", "at"}]}`).
- `ProgressDao`:
  - `saveLesson(SavedLessonsCompanion)`: upsert the row.
  - `savedLesson(DateTime now)`: the row when saved under `resumeFor` ago; an older row is deleted
    and null returned.
  - `dropSavedLesson()`.
  - `finishLesson` deletes the row in its transaction.
- `startLocation`: with a course, a saved lesson → `Routes.lessonOf(...)` (or
  `Routes.unitPitStop`), else `/path`. The other branches are unchanged.
- `LessonController`:
  - `start(args)`: a saved row for the same unit, kind and lesson and the open pack's version is
    restored (re-plan with `Random(seed)` in the same order as a fresh start: trip, then steps;
    `LessonRun.restore`; `startedAt` = now − (savedAt − startedAt)). Any other row is dropped. A
    fresh start draws its seed from `lessonRandomProvider` and plans with `Random(seed)`.
  - After every answer and every Next it saves the row (not after the last Next: that finishes).
  - `leave()`: drops the row. The lesson screen's Leave calls it before going to the Path.
  - A restored run that is already finished is saved as a result at once.
- `speechProvider` (`core/speech.dart`): `Speech` with `canSpeak(String languageTag)` and
  `speak(String text, String languageTag)` over `flutter_tts`; tests override it.
  `speechLanguage(String name)`: `ka-GE` with Georgian letters, else `en-US`.

## Screens

**Path loading (canvas R4-10 `loading`).** Nothing for 300 ms. Then a skeleton signpost (full
width, 64 dp, `radius.lg`) and four 56 dp round skeleton stops at the board's positions. From 2 s
a card (`LipBox`) over them adds thinking Pindo (64), "Laying out your course", "Finding {city}'s
districts and their streets. This takes a few seconds the first time." and the lane loader; it is a
live region. Error, no-districts and the loaded Path are unchanged.

**Signpost book button (canvas PathScreen).** Open units' signposts get a 48 dp book button at the
end ("Unit guide", `PindoroIconButton`-sized, ink in the plate's text colour) that opens the guide.
Locked signposts keep their tap (the locked sheet). `Signpost` gains `onGuide` and `guideLabel`.

**Unit guide (`/unit-guide?unit=…&lesson=n`, canvas R4-13, `UnitGuideScreen`).**

- Page bar: Back ("Back to the path") and "Unit guide".
- The unit's signpost (no book button).
- Map card (176 dp, `radius.xl`, clipped): the unit's district shape as the area, every street of
  the unit in yellow (or the selected lesson's streets, framed), no map controls. Below the map, in
  the same card: happy Pindo (44) and the tip: "Most of {district}'s streets run {axis}. Learn the
  long ones first; the side streets hang off them." or, without a main axis, "{district}'s streets
  run every way. Learn the long ones first; the side streets hang off them."
- "Lessons", then one row per stop in path order:

| Stop                 | Tile                      | Title                  | Subtitle                                                       | Tap                   |
| -------------------- | ------------------------- | ---------------------- | -------------------------------------------------------------- | --------------------- |
| Lesson, done         | check                     | "{n} · {lesson title}" | "Done · {accuracy} % · 4 streets" (placed: "Done · 4 streets") | select it on the map  |
| Lesson, Perfect      | Perfect tier tile, star   | same                   | "Perfect · 4 streets"                                          | select it on the map  |
| Lesson, current      | cobalt, play; chevron     | same                   | "Next · {the 4 street names}"                                  | start the lesson      |
| Lesson, locked       | locked, lock              | same                   | "Locked"                                                       | none                  |
| Pit stop, locked     | locked, wrench            | "Pit stop"             | "Opens after lesson {n}"                                       | none                  |
| Pit stop, current    | review, wrench; chevron   | "Pit stop"             | "{count} streets to tune up"                                   | start the Pit stop    |
| Pit stop, done       | check                     | "Pit stop"             | "Done"                                                         | none                  |
| Final drive, locked  | locked, trophy            | "Final drive"          | "Opens after lesson {n}"                                       | none                  |
| Final drive, current | cobalt, trophy; chevron   | "Final drive"          | "{passed} of 3 road trips"                                     | start the Final drive |
| Final drive, done    | Perfect tier tile, trophy | "Final drive"          | "Passed"                                                       | none                  |

- The selected lesson row ends in a primary `map` icon and its label adds "On the map"; tapping it
  again shows the whole unit.
- `?lesson=n` selects lesson n and scrolls its row into view.
- A unit that isn't open has no guide: the route goes back to the Path.

**See the streets (canvas R4-11).** A done or Perfect lesson's sheet gets a tertiary "See the
streets" under **Practise again**: it opens `/unit-guide?unit=…&lesson=n`.

**Hear the name (canvas R4-20 `intro1`).** The new-street card's sheet ends in a row: a 56 dp
secondary sound button ("Hear the name", `soundOn`) and **Got it** / **Start the test**. The button
shows only when `canSpeak` is true for the name's language; a tap speaks the name shown on the
plate and plays the tap haptic.

**Settings → Accessibility.** A new section after Display and feedback: a switch row "Choose turns
from a list" / "Road trips ask for each turn instead of a drawing." (`route` glyph). It applies at
once.

**Road trips.** List mode when `MediaQuery.accessibleNavigation` or `turnList`.

## Strings

New en keys (Georgian drafts alongside): Path loading (title, body), the book button label, the
Unit guide (title, back label, tip with axis and without, the four axes, "Lessons", every subtitle
in the table, "Pit stop", "Final drive", "Passed", selected), See the streets, Hear the name,
Accessibility (section, row title, subtitle).

## Testing

- `pindoro_core` `lesson_test`: `restore` round-trips a run mid-test, mid-fixes and finished;
  `resumeAt` skips an answered current step; a changed street id or a non-test step returns null;
  planning twice with the same seed gives the same steps.
- `pindoro_core` `course_test`: `mainAxis` for a grid, a diagonal set and a mixed set (null).
- `migration_test` covers 8 → 9 by itself; `progress_dao_test`: `savedLesson` expiry,
  `finishLesson` drops the row, `startLocation` opens a saved lesson.
- `lesson_controller_test`: an answer saves the row; a new controller restores the step and the
  answers; Leave drops it; a different lesson drops it.
- Widget tests: the Unit guide (rows, select, start), See the streets opens it at the lesson, the
  book button, Hear the name hidden without a voice and speaking with one, the Settings switch turns
  on the turn list, the Path loading stages (300 ms, 2 s).
- Goldens: `Signpost` with the book button and `Skeleton` (`just goldens`).
- Emulator: kill the app mid-lesson and reopen; the Unit guide map; Hear the name on a device voice;
  dark theme.

## Out of scope (docs/TODO.md)

- Caching a lesson's streets, graph and tiles (zoom 14–17) when it starts.
- Hand-written district tips and unit titles.
- Hear the name where the device has no voice for the street's language (common for Georgian on
  iOS): the button is hidden.
- A killed Final drive still drops the trip in progress.
- A pack update between the kill and the next launch starts the lesson over.
