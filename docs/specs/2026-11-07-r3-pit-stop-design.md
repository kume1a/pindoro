# R3 · v1.2 — Pit stop and mastery

- Date: 2026-11-07
- Status: proposed
- Builds on: R2 (`docs/specs/2026-11-07-r2-daily-habit-design.md`)
- Source: `docs/design/v1-screens.md` § R3 · v1.2 Pit stop and mastery; claude.ai screens canvas boards
  R3-01 Home, R3-02 Pit stop, R3-03 Reveal Miss, R3-04 Results (`PitStopScreen`, and `HomeScreen`,
  `QuizScreen`, `ResultsScreen` at `release="r3"`)

## Goal

Streets the player gets wrong come back until they stick. Close and Miss answers put a street in
the Pit stop. It comes back after 1, 3, 7 and 21 days, and graduates after two Greats in a row.
Home shows a Pit stop card when streets are due. The Pit stop screen lists them and starts a Pit
stop round. Reveal and Results say when a street went to the Pit stop. Mastered districts get the
swatch and screen-reader label they're still missing on Home's district rows.

## Decisions

| Topic         | Decision                                                                                 |
| ------------- | ---------------------------------------------------------------------------------------- |
| Storage       | A `review_item` table, updated with every answer (the board's ReviewItem)                |
| History       | Starts empty at the update; answers from before it don't enter the Pit stop              |
| What counts   | Every answer to a street in the Pit stop is a review, in any kind of round               |
| Close         | Advances a step and breaks the run of Greats                                             |
| Round size    | Up to 10 streets, most overdue first; the rest wait for the next Pit stop                |
| Scope         | Per city; streets retired from the pack drop out of the list and the rounds              |
| Due           | On calendar days: due once today reaches `due_on`                                        |
| Round         | The districts holding the due streets, the saved difficulty, the existing "Try again" plate |
| Mastery       | Already drawn on the mini map; district rows gain the swatch and ", complete"           |

## Rules (`pindoro_core`, `review.dart`)

Pure Dart. `ReviewRules.intervals = [1, 3, 7, 21]` (days per step), `ReviewRules.pitStopSize = 10`.

`ReviewState? nextReview(ReviewState? current, Tier tier, DateTime day)`, where
`ReviewState = ({int step, int greatRun, DateTime dueOn})` and `day` is the answer's calendar day:

| Current     | Miss                  | Close                         | Great or Perfect                                 |
| ----------- | --------------------- | ----------------------------- | ------------------------------------------------ |
| none        | step 1, due day + 1   | step 1, due day + 1           | none (nothing to review)                         |
| step s      | step 1, run 0, due +1 | step min(s + 1, 4), run 0     | run + 1; at 2 graduates (none), else step min(s + 1, 4) |

The due day is `day + intervals[step − 1]`. Graduating returns null and the row is deleted.

## Data (`apps/mobile`)

Schema version 7:

- New table `review_item(city_id, street_id, step, great_run, due_on TEXT, last_tier, last_at,
  PRIMARY KEY (city_id, street_id))`. `due_on` is a `dayKey`. `last_tier` and `last_at` show on the
  Pit stop rows.
- `round` gains `pit_stop BOOLEAN DEFAULT false`.
- Migration test 6 → 7; the v7 dump is committed.

`ProgressDao`:

- `recordAnswer` also updates the street's review item in the same transaction: it reads the
  round's city and the current item, applies `nextReview`, then upserts or deletes the row.
- `reviewItems(cityId)`: every item, by `due_on`, then `last_at`.
- `startRound(..., pitStop: true)` marks a Pit stop round.
- `lastPitStopAnswers(cityId)`: the answers of the most recent finished Pit stop round, for the tally.

Consumers keep only streets in the open pack (`cityStreetsProvider`). Home counts due ones, the Pit
stop screen lists them, and the round controller plans them.

## Screens

**Home (R3-01).** A Pit stop card goes on top of the list when anything is due. It has the wrench
tile in `color.path.node.review.*`, "Pit stop", "7 streets due today" and **Review**, which opens
`/pit-stop`. District rows gain the `Swatch` for their progress before the name. A mastered row is
read as "Mtatsminda, 64 of 64 streets known, complete".

**Pit stop (R3-02), new route `/pit-stop`.**

- **Due:** a header with Pindo `encouraging` (80), "7 streets to tune up" and the rule line
  "Missed streets come back after 1, 3, 7 and 21 days. Two Greats in a row and a street graduates."
  Then a list of the first 4 due streets. Each row has the last tier's tile, the name, "Missed ·
  1 day ago" and a 4-bar `ReviewGauge`. A "+ 3 more streets" row follows when there are more.
  "Your last Pit stop" shows a `TierTally` of that round's answers. Pinned: **Start Pit stop · 7
  streets**, which is at most 10.
- **Empty:** Pindo `happy` (112), "All tuned up", "Streets you miss come back here when they're
  due. Nothing is due today." and "Next review: tomorrow · 3 streets" (or "in 5 days"). The last
  line is hidden when nothing is waiting at all.
- Row screen-reader label: "Marjanishvili Street. Missed, 1 day ago. Review step 1 of 4."

**Pit stop round.** `/round?pit-stop=1`, through `RoundController.startPitStop()`:

- It plans the first 10 due streets, most overdue first.
- The area is a `DistrictsArea` of the districts holding them.
- It uses the saved difficulty, and `round.pit_stop` is set.
- The quiz shows the reroute plate ("Try again: drop a pin on"), as retry rounds do.
- A Pit stop round resumes like any round.
- Results is titled "Pit stop complete" and offers Done / Play a new round, as a retry round does.

**Reveal (R3-03).** Close and Miss get a chip "Added to your Pit stop" (`wrench`,
`color.path.node.review.icon`) in every kind of round. The Miss sentence drops "You'll see it again
on your results."

**Results (R3-04).** A chip "3 to your Pit stop" (the round's Close and Miss count, same icon).
Close and Miss rows read "in your Pit stop" instead of "to retry". Retry stays: it replays now, and
the Pit stop brings them back later.

## Design system (`packages/pindoro_design`)

- `ReviewGauge(step, {steps = 4, semanticLabel})`: four 6 × 14 dp bars 2 dp apart, `color.line.base`
  off and `color.primary.text` on (`.pd-gauge`).
- `RevealSheet.chips` becomes `List<Widget>`, so a chip can carry an icon (`Pill` with icon).
- `Swatch` and `TierTally` are reused as they are.
- Goldens: the gauge joins the components gallery.

## Architecture

- New screen feature `features/pitstop` (the screen and its data provider), added to the
  screen-feature layer in `test/architecture_test.dart`.
- Review rules in `pindoro_core`; the table and its writes in `ProgressDao`.
- `Routes.pitStop = '/pit-stop'`, `Routes.pitStopRound = '/round?pit-stop=1'`.
- Strings in `app_en.arb` and `app_ka.arb` (Georgian draft), with ICU plurals for counts and ages.

## Testing

- `pindoro_core`: `nextReview` for every row of the table, step capped at 4, graduation after two
  Greats in a row, Close breaking the run, a Miss resetting.
- Mobile:
  - the 6 → 7 migration
  - `recordAnswer` keeping review items (entering on Close/Miss, advancing, graduating, per city)
  - `lastPitStopAnswers`
  - widget tests: the Home card and mastered row label, the Pit stop screen (due list, "+ n more",
    tally, empty state with the next review), starting a Pit stop round (10 most overdue, the plate),
    the reveal chip, the Results chip and row note
- Goldens for the gauge (`just goldens`).
- Run only the touched tests locally; CI runs everything.

## Docs

- `apps/mobile/CLAUDE.md`: `review_item`, Pit stop rounds, `/pit-stop`.
- `docs/TODO.md`: what R3 leaves out (below).

## Out of scope

The Pit stop tab, its badge and the Pit stop on the lesson path (R4); a tappable Results chip;
backfilling history.
