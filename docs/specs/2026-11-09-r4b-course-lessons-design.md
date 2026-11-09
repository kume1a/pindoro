# R4b · v2.0 — the course, the Path and lessons

- Date: 2026-11-09
- Status: implemented
- Builds on: R4a (`docs/specs/2026-11-07-r4a-tabs-me-design.md`)
- Source: `docs/design/v1-screens.md` § R4 · v2.0; claude.ai screens canvas boards R4-01, R4-02
  rules, R4-10 to R4-12 (Path, stop taps, Pit stop sheet), R4-20 to R4-24 (lesson), R4-60 unlock
  storyboard, R4-63 motion table, components `PathScreen`, `LessonScreen`, `LessonDoneScreen`;
  design system LessonPath and PlateChoice

## Goal

The course arrives. Each city gets a road of units, one per raion, each with 6 lessons of 4 streets
and a Pit stop after lesson 3. The Path becomes the first tab and the screen the app opens on. A
lesson introduces 4 new streets, tests them with pin drops and "Which street is this?", then brings
the mistakes back once. Lesson complete shows the XP, accuracy and time, and the Path plays the
unlock of the next stop.

Road trips, the Final drive, Jump ahead and the unit reward are R4c. What's new, placement and the
start-district picker are R4d.

## Decisions

| Topic          | Decision                                                                                                               |
| -------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Units          | The raions (`DistrictKind.district`); a street belongs to the raion holding most of its length                         |
| Unit gate      | Lesson 6 done opens the next unit. The Final drive stop is drawn, locked: "Road trips are on their way"                |
| Road-trip step | Not in R4b: a lesson is 10 steps (4 cards, 6 tests) plus fixes, up to 570 XP                                           |
| Start district | Saved once per city: the raion of the last played Free play area, else the raion holding the city centre               |
| Titles         | Lesson: its longest street and the rest ("Vazha-Pshavela Avenue and 3 more"). Unit: the district name                  |
| Difficulty     | Lessons use the saved Free play difficulty (Medium when none); it only scales the distances, as in Free play           |
| Landing tab    | Tabs Path · Free play · Pit stop · Me. Launch and back land on the Path; Welcome stays until a round or lesson is done |
| Me city row    | Opens the Path for that city (R4a opened Free play; the course now lives on the Path)                                  |
| XP on leaving  | A lesson writes nothing until it completes, so leaving drops its XP (canvas R4-24)                                     |
| Lesson storage | Own tables (`course`, `lesson_result`, `lesson_answer`), joined into XP, known streets and the Pit stop                |
| Lesson rules   | `LessonRules` in pindoro_core (Dart only, like `ReviewRules`); distance scoring stays in `ScoringConfig`               |
| In R4b         | Practise again; the R4-60 unlock animation                                                                             |
| Later          | Unit guide and See the streets, Hear the name, resuming a killed lesson (docs/TODO.md)                                 |

## Rules (`pindoro_core`)

**Course (`course.dart`, pure).** `buildCourse(districts, streets, lengthsByDistrict,
startDistrictId)`:

- Units are the city's districts of kind `district` (the raions). A raion needs at least 4 eligible
  streets to be a unit.
- Eligible streets: named streets (`groupByName` over the whole pack, every difficulty) of at least
  `QuestionSelector.minTotalLengthM` (150 m). Each belongs to the raion holding most of its length
  (the sum of its parts' `street_district.length_m`; ties go to the lower district id).
- Each raion orders its streets by the road class of their longest part (motorway, trunk, primary,
  secondary, tertiary, then the rest), then longest first, and takes up to 24: lessons of 4 in that
  order, up to 6 lessons.
- Unit order: the start raion first, then the others by distance from its centre.
- Stops in a unit: lessons 1–3, the Pit stop, lessons 4–6, the Final drive. A unit with 3 or fewer
  lessons has its Pit stop after its last lesson.
- Lesson title: its longest street's name, "and 3 more" (localised, the count from the lesson).
- `PackRepository.lengthsByDistrict()` (new): district id → part id → metres, read from
  `street_district.length_m`. No pack format change.

**Progress (`courseProgress(course, results)`).**

- Lesson state: locked, current, done, or Perfect (its first lesson result had no mistakes).
- The Pit stop is done once it has a result, or as soon as lessons 1–3 are done without first-try
  mistakes.
- A stop opens when the stop before it is done; the current stop is the first open stop that isn't
  done. The Final drive stays locked in R4b. The next unit opens when the unit's last lesson is done
  (R4c moves the gate to the Final drive).
- Practice results never change a stop's state.

**Lesson (`lesson.dart`, `LessonRules`).**

- Steps: 4 new-street cards (the lesson's streets in order), then 6 tests in a shuffled order: a pin
  drop on each of the 4 streets and "Which street is this?" on 2 of them, never the same street twice
  in a row. Then each mistake once more, in the order it happened.
- Name options: the answer and two other streets of the unit with a different name, shuffled.
- Mistakes: a Close or Miss pin drop, a wrong name.
- XP: pin drops as in Free play at the chosen difficulty; a right name 50, a wrong one 0; fixes earn
  half (rounded down); finishing +20; no mistakes (a Perfect lesson) +50. Max 570.
- Accuracy: tests right first time (Great or Perfect pin drop, right name) out of 6.
- Known streets: a Great or Perfect pin drop (fixes too), or a right name first time.
- Pit stop tab: at the end of a lesson, a street already in the Pit stop takes every answer as a
  review (`nextReview`; a right name as Great, a wrong one as Miss). A street not in it enters only
  when its fix was wrong again.
- Practise again: the 6 tests of a done lesson in a new shuffle, no cards, no fixes, half XP, no
  bonuses; every answer follows the R3 rule (Close and Miss enter the Pit stop tab).
- The unit's Pit stop: the unit's first-try mistakes from lessons 1–3, one pin drop each, no fixes,
  full XP, no bonuses, the R3 rule for every answer.
- Card facts, generated: the where sentence "A main road north-west of the city centre." (a
  `compassPoint` from the city centre to the street's midpoint; "in the city centre" within 1 km)
  and the facts line "2.1 km · main road · crosses 9 streets" (road type: main road for motorway,
  trunk and primary, street for secondary and tertiary, side street for the rest; crossings: other
  named streets whose lines cross or touch it).

## Data (`apps/mobile`, schema 8)

- `course(city_id PK, start_district_id)`: written the first time the Path opens a city. The start
  raion: the one holding the centre of the most recent Free play round's area in that city, else the
  one holding the city centre, else the one whose centre is nearest it. R4d's picker writes the same
  row.
- `lesson_result(id, city_id, unit_id, kind 'lesson' | 'practice' | 'pitStop', lesson nullable,
  difficulty, xp, perfect, right_first, tests, duration_ms, finished_at)`; `xp` includes the
  bonuses.
- `lesson_answer(result_id, position, street_id, kind 'pin' | 'name', tier, xp, fix, distance_m
  nullable)`; a name answer's tier is Great when right, Miss when wrong.
- `ProgressDao.finishLesson(...)` writes the result, its answers and the Pit stop updates in one
  transaction, then marks today's goal if it got there, and returns the result id. Migration test
  7 → 8; the v8 dump is committed.
- `ProgressDao`: `totalXp` and `xpOn` add lesson XP; `bestTierByPart` also reads lesson answers
  (name answers as Great when right first time, as Miss when wrong; right name fixes don't count);
  `hasFinishedRound` becomes `hasPlayed` (a finished round or any lesson result); `firstRoundAt`
  becomes `firstPlayedAt`; `progressChangesProvider` also ticks on the lesson tables. New:
  `courseStart` / `saveCourseStart`, `lessonResults(cityId)`, `unitMistakes(cityId, unitId)`,
  `lastDistances(cityId, streetIds)`.
- `features/course` (new slice): `courseProvider` for the open city (pack, lesson results and the
  start raion, built with pindoro_core), shared by the Path, the lesson and Me.

## Screens

**Tabs.** Path · Free play · Pit stop · Me (`road`, `map`, `wrench`, `user`); the Path is
`/path`, Free play stays `/`. The app opens on the Path once Welcome is done; back on another tab
goes to the Path first. Tapping the open Path tab scrolls to the current stop. Results' Done,
leaving a round and the area picker's back still go to Free play.

**Path (R4-01, R4-10 to R4-12).**

- The Free play top bar: city switcher, streak pill, XP pill (one shared widget).
- A sticky compact signpost per unit (`SliverMainAxisGroup` + pinned header): the unit number, "2
  of 6 lessons", the district name; locked units in the locked colours with "Locked". The guide
  button arrives with the Unit guide.
- A 24 dp road through stops 104 dp apart, swinging centre, left, centre, right; asphalt with kerbs
  and lane dashes up to the current stop, soft grey after; at 55 % past the current unit.
- Stops: done (cobalt, check), Perfect (yellow, star), current (72 dp, `play`, the ring at 0, a
  "Start" tip, ±4 dp float over 1.6 s), Pit stop (locked colours with a wrench; due: white, 72 dp,
  ring, "Tune up"; done: 56 dp review colours), Final drive (locked colours, `trophy`), locked
  (grey, lock). Labels as the LessonPath README ("Lesson 3, Vazha-Pshavela Avenue and 3 more.
  Current. Double-tap to start.").
- Opens scrolled so the current stop sits in the upper half.
- Tap a stop: it presses (80 ms), then a sheet. Lesson: "Lesson 3 of 6 · Unit 2 · Vake", the title,
  "Meet 4 new streets in Vake, then a short test.", chips (difficulty, 4 new streets, up to 570 XP),
  **Start lesson**. Done or Perfect: the first result ("71 % accuracy · 507 XP · 3 min 12 s";
  Perfect: "No mistakes · 627 XP"), "Practise replays the test without the intro cards and earns
  half XP.", **Practise again**. Pit stop: "Tune up 4 streets", "The streets you missed in lessons
  1–3 come back once here. Finish it to open lesson 4.", chips (4 streets, up to 400 XP), **Start
  Pit stop**. A done Pit stop has no sheet.
- A locked stop opens no sheet: its glyph wiggles ±6° over 300 ms and a coach bubble says what
  opens it ("Lesson 4 is locked / Finish the Pit stop first."; the Final drive: "Road trips are on
  their way / The Final drive opens in a later update."; a locked signpost: "Unit 3 is locked /
  Finish Vake's lessons first."), gone after 3 s or the next tap.
- Loading: nothing for 300 ms, then thinking Pindo and the lane loader. Error: "Couldn't load the
  course" with **Try again** and **Open Free play**. No pack yet: the Free play pack states.
- A city without districts shows Pindo and "Lessons need this city's districts. Play it in Free
  play for now." with **Open Free play** (rings from the centre: TODO).

**Unlock (R4-60).** After Continue on Lesson complete, the Path plays the unlock once, from the
finished stop, over 900 ms: 0–200 ms the stop swaps to `check` or `star` with a pop
(`spring.bouncy`) and a 12-dash burst; 200–620 ms the road to the next stop is paved (asphalt over
the soft road, yellow lane dashes that turn white when it settles, `duration.slow`, linear);
620–900 ms the next stop grows 56 → 72 dp with an overshoot to 1.12 (`ease.overshoot`) and its ring
and tip fade in (`duration.base`); the path scrolls to keep it in the upper half. `lightImpact` at
620 ms (no sound kit yet). When the next stop is in the next unit, the road isn't paved across the
units; the signpost is simply open (R4-61 flip: R4c). Reduce motion: the final state at once.

**Lesson (R4-20 to R4-23), `/lesson?unit=<id>&lesson=<n>` (`&practice=1`) and
`/lesson?unit=<id>&pit-stop=1`.** Top-level routes, over the tab bar.

- Top bar: ✕, a step bar with one segment per step (a segment slides in per mistake), the XP this
  lesson.
- New street: the plate "New street · 1 of 4" with the name; the map flies to the street (420 ms,
  `ease.standard`) and paints it yellow; a sheet with "Where it is", the where sentence, the facts
  line and **Got it** (the last card: **Start the test**). The map stays free to pan; Got it moves
  on.
- Which street is this: a one-line card "Which street is this?", the street painted yellow, three
  `PlateChoice` options, **Check**. Right: the mark pops, a Great feedback bar "Correct! / Pekini
  Avenue +50 XP" with **Continue**. Wrong: the picked plate shakes, the right one is marked, a Miss
  feedback bar "Not quite / The marked plate is right. It comes back at the end." with **Got it**.
- Pin drop: the Free play question and reveal (map, plate, Confirm, reveal sheet); Close and Miss
  add the chip "Comes back at the end". A failed fix shows "Added to your Pit stop".
- Fixes: "Let's fix 2 mistakes", "Get these right to finish the lesson. Fixes earn half XP, and you
  can't fail: anything still wrong goes to your Pit stop.", a row per mistake ("Close · 240 m · drop
  a pin again", "Named wrong · name it again"), **Fix them**; each fix uses the "Try again" plate.
- The unit's Pit stop and Practise again run in the same screen with their own step lists.
- ✕ or back: "Leave this lesson? / You'll lose this lesson's progress. Your streak and the XP you
  earned today are safe." **Keep learning** (primary, the default) and **Leave** (back to the Path).
- The Free play pin-drop view (map, plate, Confirm, reveal) is extracted from `QuizScreen` and
  shared, so lessons don't copy it.

**Lesson complete (R4-24), `/lesson-done?result=<id>`**, with a fade. Pindo (`proud`; Perfect:
`cheering`), "Lesson complete!" or "Perfect lesson!" ("Pit stop complete!", "Practice complete!"),
"Lesson 3 · Vazha-Pshavela Avenue and 3 more", `RewardTotal`, the bonus line ("Includes +20 for
finishing and 65 XP from 2 fixes" / "… and +50 Perfect bonus"; none for practice and the Pit stop),
three `StatTile`s (Accuracy, New streets, Time; the Pit stop and practice: Streets instead of New
streets), the level bar, the level-up screen when a level was reached, the streak chip when this
lesson met today's goal, **Continue** back to the Path (and its unlock). A Perfect lesson plays the
big celebration.

**Me.** The Lessons tile counts the lessons done (kind `lesson`, every city). A city row reads "Unit
2 · Vake · 180 / 1 240 streets" once that city has a course, and opens its Path.

## Design system (`packages/pindoro_design`)

New widgets: `PathStop` (every look, 56 and 72 dp, the ring, the tip, the float, pressed, the
wiggle), `Signpost` (compact, open and locked), `LessonRoad` (the road painter: driven, ahead, the
55 % part, and a paved fraction for the unlock), `PlateChoice` (default, selected, right, wrong, dim,
the shake) and `FeedbackBar` (Great and Miss). Tests in `components_test.dart`; goldens
`path_{light,dark}.png` (a signpost and a road with every stop look) and `lesson_{light,dark}.png`
(the plate-choice states and both feedback bars).

## Testing

- pindoro_core: the course (units, ordering, a street in the raion with most of its length, short
  raions, titles), progress states and unlocks (Pit stop auto-done, practice ignored, the next unit
  after lesson 6), the lesson plan (step order, no street twice in a row, options), XP, accuracy,
  the Pit stop rule, crossings and the where sentence.
- apps/mobile: migration 7 → 8; `finishLesson` and its joins (total XP, today's XP, known streets,
  review items, goal day); the course start; Path states, sheets and locked bubbles; a lesson played
  through with a mistake and its fix; practice; the unit's Pit stop; lesson complete; the unlock
  (final state, reduce motion); the tabs with the Path first and back to it; Me's Lessons tile and
  city row.
- Design widget tests and goldens (`just goldens`).
- Emulator: the whole loop on the Vake fixture and on the Tbilisi pack, dark theme, 200 % text.

## Out of scope (docs/TODO.md)

R4c: the lesson's road trip, the Final drive, Jump ahead, the locked signpost sheet, the unit
reward and +100 bonus, the R4-61 unit storyboard. R4d: What's new, placement, the start-district
picker, the new-city and new-player coach marks. Later: the Unit guide, the signpost's guide button
and See the streets; Hear the name (TTS); resuming a killed lesson; loading skeletons; units by
rings for cities without districts; editorial where sentences and titles per district.
