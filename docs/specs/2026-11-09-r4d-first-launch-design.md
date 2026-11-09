# R4d · v2.0 — first launch: What's new, placement and the start-district picker

- Date: 2026-11-09
- Status: implemented
- Builds on: R4b (`docs/specs/2026-11-09-r4b-course-lessons-design.md`) and R4c
  (`docs/specs/2026-11-09-r4c-road-trips-design.md`)
- Source: `docs/design/v1-screens.md` § R4 · v2.0 (First launch); claude.ai screens canvas boards
  R4-50 (existing players), R4-51 (new players), R4-10 (Path states `newCity`, `newPlayer`);
  components `WhatsNewScreen` (states `intro`, `placed`, `pick`), `PathScreen`, `StartScreen`
  (`firstRun`), `CityScreen`

## Goal

The last part of v2.0: how players arrive at the course. A player who already played Free play
sees What's new once, then a placement that checks off the lessons whose streets they already
know. A new player goes Welcome → City → "Where do you want to start?" → the Path, with a "Start
here" coach mark on lesson 1. A new city's course (an existing player switching cities) gets the
same coach mark.

## Decisions

| Topic            | Decision                                                                                                                                                                                              |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Placement        | Every lesson in any unit with 3 of its 4 streets known gets a check (never a star). A unit whose lessons all have one is done once the unit before it is done. Saved once; later Free play adds none |
| Placement store  | No schema change: `lesson_result.kind` gains `placed` (text enum), one row per placed lesson, 0 XP                                                                                                   |
| Who is "existing" | A player who finished a round but has no course yet (no `course` row): derived, no seen flag. Acting on What's new (or leaving it) creates the course, so it shows once                             |
| Picker           | New players only. A new city's course still starts at the raion of the last Free play area there (R4b rule), with the coach mark                                                                    |
| Picker order     | Nearest to the player first when location permission is already granted and they are inside the city's bounds; otherwise nearest to the city centre first. The picker never asks for permission   |
| Coach mark       | "Start here" on lesson 1 while the city's course has no results at all; any tap on the Path hides it for this launch                                                                                |
| Start location   | A course exists → Path; else played → What's new; else a saved first round → Free play; else Welcome                                                                                                |
| Git              | Worktree `../pindoro-r4d`, branch `r4d-first-launch`, one commit per part, PR, merge commit once CI is green                                                                                         |

## Rules (`pindoro_core`, `game/course.dart`)

- `CourseRules.placedKnown = 3`: known streets a lesson needs to be placed.
- `LessonKind.placed`: a lesson marked done by placement.
- `List<(String unitId, int lesson)> placeLessons(List<CourseUnit> units, Set<String> known)`: every
  lesson with at least `placedKnown` of its streets' ids in `known`, in course order.
- `courseProgress` reads `placed` outcomes:
  - a placed lesson is done, not Perfect, and counts in `lessonsDone`;
  - a unit whose every lesson is placed is done when it is the first unit or the unit before it is
    done (a forward pass after the Jump-ahead cascade, which only Final drives start). Its Pit stop
    and Final drive show done (checks), like a Jump-ahead unit;
  - a placed lesson counts only in an open unit: in a locked unit its stop stays locked (and
    uncounted) until the unit opens. The current stop is the first stop that isn't done, as before,
    so there is still one current stop.
- A placed lesson's row never comes back as a first result: the done sheet shows no score (below).
- Finishing a unit can now also complete the fully placed unit after it, so "the next unit" (Unit
  complete's signpost and Continue, the R4-61 unlock) is the first unit after it that isn't done.
- Exhaustive switches on `LessonKind` gain a `placed` arm (`courseProgress`, Lesson complete's
  title); nothing routes a placed result to Lesson complete.

## Data (`apps/mobile`, no schema change)

- `ProgressDao.hasCourse()`: any `course` row.
- `ProgressDao.place(cityId, placed)`: one `lesson_result` per placed lesson in one transaction
  (`kind` placed, `xp` 0, `perfect` false, `tests` 0, `rightFirst` 0, `durationMs` 0, difficulty
  medium), no answers. XP, today's XP, the Lessons tile (`kind = 'lesson'`), known streets and the
  Pit stop are unchanged by it.
- `startLocation(db)`: `hasCourse` → `/path`; `hasPlayed` → `/whats-new`; a saved first round →
  `/` (Free play); else `/welcome`.
- `LocationService.ifAllowed()`: the last known position when location services are on and
  permission is already granted; null otherwise. Never prompts and never waits for a fix (the City
  screen's "Use my location" leaves a fresh one).
- `placementProvider` (course data): the open city's plan (`coursePlanProvider`, which saves the
  default start), its known streets (`bestTierByPart` + `knownStreetIds`), the placed lessons and
  the progress they give (`courseProgress` with them as outcomes).
- `CourseData.placed`: the open city's placed lessons as `(unitId, lesson)`, so the Path can tell a
  placed lesson from a Jump-ahead one.

## Screens

**Start location.** As in Decisions. Welcome now stays until a course is started or a round is
finished (it was: until a round or lesson is finished).

**What's new (`/whats-new`, canvas R4-50, `WhatsNewScreen` `intro`).** No top bar. A short road
with three stops (done, Perfect, current with its ring), chip "New in 2.0", headline "{City} is now
a course", body "Learn the city district by district. Everything you've already learned counts.",
three rows (road glyph "Lessons on a path" / "New streets first, then a short test and a road
trip."; car "Road trips" / "Draw the shortest drive between two points."; map "Free play is still
here" / "Quick rounds in any area, just like before."), button **Show me my path**.

- Show me my path: the button waits for `placementProvider`. Nothing placed (or no course, or an
  error) → go to the Path. Placed lessons that leave the current stop at unit 1, lesson 1 (they
  are all in later, locked units) → save the placement and go to the Path. Otherwise the placement
  state.
- Back skips: go to the Path (the course starts unplaced; What's new doesn't come back).

**Placement (same route, `WhatsNewScreen` `placed`).** Pindo proud; headline "You start in Unit
{n}"; body "You already know {k} streets in {city}, so your course skips what you know."; up to
three rows:

- the unit before the current one, if any: check tile, "Unit {n} · {district}", "Complete · you
  know {known} of its {total} streets";
- the current unit, selected (cobalt play tile): "Unit {n} · {district}", "{d} of {total} lessons
  done · lesson {m} is next";
- the unit after it, if any: lock tile, "Unit {n} · {district}", "Opens after {district}".

Buttons: tertiary **Start from Unit 1 instead** (nothing saved; go to the Path) and primary **Start
lesson {m}** (save the placement; go to the Path and open lesson {m}). If placement leaves no
current stop (every unit placed), the headline is "You know every unit", the only row is the last
unit (complete) and the primary button is **Show me my path** (saves, goes to the Path). Back
returns to the intro state.

**City (`/city?course=1`).** Welcome's **Choose a city** opens the City screen for the course: a
picked city goes to the picker instead of Area. Every other way into City (Free play's city chip,
Welcome's resume variant, the pack error) still goes to Area.

**Start district (`/start-district`, canvas R4-51, `WhatsNewScreen` `pick`).** The chosen city's
pack (`PackPending` while it downloads). The page bar has Back and the city name; headline
"Where do you want to start?"; body "Your course goes district by district. Start where you live or
where you need it most; the rest follow, nearest first."; a radio list of the raions that have a
unit, the first selected. The order starts from the player's position (see Decisions) or the city
centre: the raion holding that point first (as `startDistrict` does), then by distance from it.

- title: the district name;
- subtitle: "{n} streets" (all the district's named streets, as Home counts them, not only the 24
  its unit teaches) and one of "nearest to you" (the first row when located), "city centre" (the
  raion holding the city centre) or the compass direction of its centre from the city centre
  ("north", "north-east", … 8 points).

The picker builds its list itself (`buildCourse` for which raions have a unit, plus its own order)
and writes nothing until **Start in {district}**: that saves the course start, invalidates
`coursePlanProvider` and goes to the Path. Going back leaves no course behind. Under the list
"{n} districts · from OpenStreetMap". A city without raions skips the picker (the Path explains it).

**Path coach mark (canvas R4-10 `newCity`, `newPlayer`).** While the open city has no lesson
results (not even placed ones), the current stop (unit 1, lesson 1) shows a coach bubble instead of
its "Start" tip: "Start here" / "Your first lesson: 4 streets in {district}, then a short test."
Any tap on the Path hides it until the next launch. It also announces itself to screen readers
(live region, as `CoachBubble` does).

**Placed lesson sheet.** A placed lesson is done: tapping it opens the done sheet with the kicker
"Lesson {n} of {total} · Done", body "You already knew these streets when the course started." and
**Practise again**.

## Strings

New en keys (Georgian drafts alongside): What's new intro (chip, headline, body, 3 × title and
line, button), placement (headline, body, the three row lines, both buttons), the picker (back
label, headline, body, the subtitle parts and 8 directions, footer, button), the coach mark (title,
body), the placed lesson body. No uppercase; numbers through `formatNumber`.

## Testing

- `pindoro_core` `course_test`: `placeLessons` at 2, 3 and 4 known; `courseProgress` with placed
  lessons (done not Perfect, counted, non-contiguous checks, a fully placed first unit done and the
  next open, a placed lesson in a locked unit stays locked, a fully placed later unit done only once
  the one before it is done, its Final drive a check).
- `progress_dao_test`: the `startLocation` table above; `place` leaves XP, Lessons and known
  streets unchanged.
- Widget tests: What's new → placement → Start lesson opens the lesson; Start from Unit 1 instead
  saves nothing; nothing known goes straight to the Path; the picker's order and Start in saves the
  start and opens the Path; the coach mark shows on a new course and hides on a tap.
- `routing_test`: Welcome → Choose a city → picker → Path.
- Emulator: a new player from a clean install; an existing player (finished rounds, no course row)
  through What's new and placement; a new city's coach mark; dark theme.

## Out of scope (docs/TODO.md)

- Changing the start district later, and the picker for a new city.
- Placement for cities other than the open one: their courses start unplaced.
- Hand-written district descriptions ("old town hills"); the subtitle uses direction only.
- The coach mark comes back on the next launch until the city has a lesson result (a lesson or a
  Final drive trip); there is no seen flag.
- A city without raions never gets a course row, so an existing player there sees What's new on
  every launch and a new player returns to Welcome. No catalog city lacks raions today.
- The R4b and R4c left-outs stay as listed.
