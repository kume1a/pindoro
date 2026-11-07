# R2 · v1.1 — Daily habit

- Date: 2026-11-07
- Status: implemented
- Builds on: the MVP (`docs/design/v1-screens.md` § MVP screens)
- Source: `docs/design/v1-screens.md` § R2 · v1.1 Daily habit; claude.ai screens canvas boards
  R2-01 Home, R2-02 Streak, R2-03 Results, R2-04 Settings (`StreakScreen`, and `HomeScreen`,
  `ResultsScreen`, `SettingsScreen` at `release="r2"`); design-system component `Streak`
  (`project/components/Streak/README.md`) and its bundle classes (`.pd-pill--off|risk|frozen`,
  `.pd-cal`, `.pd-freeze`, `.pd-ring-track|fill`)

## Goal

Give players a reason to come back every day. Players get a daily XP goal, a streak of days with
the goal met, streak freezes for missed days, and an optional reminder in the evening. Home shows
the streak and today's progress, a new Streak screen shows the month, Results celebrates the round
that meets the goal, and Settings changes the goal and the reminder.

## Decisions

| Topic         | Decision                                                                                      |
| ------------- | --------------------------------------------------------------------------------------------- |
| Storage       | Only goal-met days are stored (`goal_day`); everything else comes from them in `pindoro_core` |
| Daily goal    | 250, 500 or 1 000 XP; default 500. All XP counts: rounds and retries                          |
| Day           | The device's local calendar date                                                              |
| Streak count  | Goal-met days in the unbroken run. A frozen day keeps the run alive and adds nothing          |
| Freezes       | One earned on every 7th goal day of the run, at most 2 held, one used per missed day          |
| Goal changes  | Apply from now on. Lowering it below today's XP marks today met; past days never change       |
| History       | Starts fresh: days before the update aren't backfilled                                        |
| Reminder      | Off by default; turning it on asks for notification permission. Fixed at 19:00                |
| Reminder rule | Fires only when that day's goal isn't met; text names the streak at stake                     |
| Calendar      | Current month only (the board has no month arrows)                                            |
| Sound         | None: the streak sound waits for the designed sound kit (`docs/TODO.md`)                      |

## Rules (`pindoro_core`, `streak.dart`)

Pure Dart. Days are calendar dates (`DateTime.utc(y, m, d)`, so DST never shifts a day).

`StreakSummary streakOf(Set<DateTime> metDays, DateTime today)` walks day by day from the first met
day to `today`:

- A met day: `run += 1`; when `run % 7 == 0`, `freezes = min(2, freezes + 1)`.
- A past day that isn't met: with a freeze, `freezes -= 1` and the day is frozen; without one,
  `run = 0`.
- `today` not met isn't missed yet: it changes nothing.
- `best` is the largest `run` seen.

The summary holds `days` (the current run), `best`, `freezes`, `metToday`, the set of frozen days,
and `yesterdayFrozen`. `streakOf(metDays, tomorrow)` predicts tomorrow's streak if the player
doesn't play today (the reminder uses it).

Pill state, from the summary and the local hour:

| State  | When                             | Look (`.pd-pill--*`)                       |
| ------ | -------------------------------- | ------------------------------------------ |
| active | today's goal met                 | flame in `color.streak.flame` / `.core`    |
| atRisk | not met, `days > 0`, after 18:00 | `color.warning.soft`, warning text and lip |
| frozen | not met, yesterday was frozen    | `color.streak.freeze.fill`, `freeze` icon  |
| off    | anything else, including 0       | flame in locked grey, secondary text       |

atRisk wins over frozen: it's more urgent.

## Data (`apps/mobile`)

Schema version 6:

- New table `goal_day(date TEXT PRIMARY KEY, round_id TEXT NULL REFERENCES round(id))`. `date` is
  the local date as `YYYY-MM-DD`. `round_id` is the round whose answer reached the goal (null when
  lowering the goal did it).
- `user_settings` gains `daily_goal INTEGER DEFAULT 500` and `reminder BOOLEAN DEFAULT false`.
- Migration test for 5 → 6; the new schema dump is committed in `drift_schemas/`.

`ProgressDao`:

- `markGoalIfMet(DateTime now, {String? roundId})`: sums today's XP from `answer` and, when it's at
  least the goal, inserts today's `goal_day` row if none exists. `recordAnswer` calls it in the same
  transaction. Settings calls it after lowering the goal.
- `goalDays()` and `xpOn(DateTime day)` for the summary and the ring.

`streakProvider` (in `features/progress`, so every screen can use it) builds a `StreakView`:
the summary, today's XP, the goal, the pill state and `goalRoundId` (the round that met today's
goal, from `goal_day.round_id`; Results compares it with its own round). It
recomputes when progress or settings change and when the app resumes (the date may have changed).

`SettingsDao`: `setDailyGoal(int)` and `setReminder({required bool on})`.

## Screens

**Home (R2-01).** `StreakPill` fills the reserved slot between the city switcher and the XP pill;
tapping it opens `/streak`. The level card gets a `DailyGoalRing` (56 dp, 9 dp stroke,
`color.xp.track` / `color.xp.fill`, flame in the middle) at the end of its first row: today's XP
over the goal, full when met. Nothing else moves. Screen readers: "13-day streak. Goal met today."
and "Daily goal: 320 of 500 XP".

**Streak (R2-02), new route `/streak`.** Back button and "Streak" title; the count in heavy
tabular figures with "day streak" and "Your best: 21 days"; a card with the month name, the legend
"Goal met · frozen · today" and a `StreakCalendar`; a `StreakFreezeCard`; a daily goal card (ring,
"Daily goal: 500 XP", "Met today with 695 XP" or "320 of 500 XP today", **Change** opens the daily
goal sheet); pinned **Play a round**, which starts a round as Home's Play does.

Calendar days: met = `color.streak.day.done`; frozen = `color.streak.freeze.fill`; past and not met
= `color.streak.day.empty`; today = a 3 dp `color.primary.base` ring on top of its state; future
days and days before the first goal day = plain text. Seven columns from the locale's first
weekday. Screen readers get one label listing the goal days and the frozen days.

Freeze card: "Streak freeze equipped · 1 of 2" (or "· 2 of 2") with "Miss a day and your streak
stays put. You earn one for every 7 days in a row." With none held: "No streak freeze yet" with
"You earn one for every 7 days in a row." (not on the board; same card).

**Results (R2-03).** Once today's goal is met, a flame chip "13-day streak" joins the chips. When
this round reached the goal, the number counts up from `days − 1` (overshoot ease, 420 ms),
haptics play a medium impact, and the celebration is big on 7, 30, 100 and 365 days. Screen
readers hear "Daily goal met, 13-day streak". Reduce motion: the number swaps with a 150 ms
cross-fade.

**Settings (R2-04).** A "Daily goal" section after Language:

- Goal row (flame, "500 XP a day", "About two rounds · keeps your streak going", chevron) opens
  the daily goal sheet.
- Reminder row (bell, "Reminder", "19:00, only if today's goal isn't met", toggle). Turning it on
  asks for permission. If permission is denied, the switch stays off and a toast explains how to
  turn notifications on in system settings.

**Daily goal sheet** (from Settings and Streak). A bottom sheet with three rows: 250 XP "About
one round", 500 XP "About two rounds", 1 000 XP "About 4 rounds", with the current goal
checked. Choosing a row saves it and closes the sheet.

## Reminder

`flutter_local_notifications`. Exactly one reminder is scheduled at a time:

- Turning it off in Settings cancels it; without permission it can't be turned on.
- Otherwise schedule the next 19:00 local whose day isn't met: today's 19:00 when it is still ahead
  and today isn't met, else tomorrow's 19:00.
- Text: "Your 13-day streak ends at midnight. One round keeps it going." with that day's streak
  (from `streakOf` for that day). With no streak at stake: "Today's goal is waiting. One round gets
  your streak going."
- It is scheduled at an absolute instant (the local 19:00 converted to UTC), so no timezone
  package is needed. Android uses inexact scheduling: there's no exact-alarm permission.
- It's rescheduled at app start and resume, after every answer, and when the goal or the switch
  changes, by listening to `streakProvider` and settings at the app root.
- The next-reminder choice is a pure function (`nextReminder(metDays, now)` → time and streak days),
  unit-tested. The plugin call itself sits behind it, untested.

Platform setup: Android core-library desugaring, `POST_NOTIFICATIONS`, the plugin's boot receiver
(reschedules after a reboot) and a small monochrome notification icon from the branding; iOS asks
for alert permission only when the switch is turned on.

## Design system (`packages/pindoro_design`)

New widgets, tokens only, with goldens:

- `StreakPill(label, state)`: `Pill` gains `face`, `lip`, `foreground` and `iconAccent` (the
  flame's core, through `PindoroIcon.accent`) for the three streak looks, so the pill keeps one
  implementation.
- `DailyGoalRing(progress, size)`: a `CustomPainter` ring with the flame inside; the fill animates
  with `motion.duration.slow`.
- `StreakCalendar(month, days, today, firstWeekday)`: the `.pd-cal` grid, 36 dp discs, 6 dp gaps.
- `StreakFreezeCard(title, body)`: the `.pd-freeze` card.

## Architecture

- New screen feature `features/streak` (the Streak screen). It joins the screen-feature layer in
  `test/architecture_test.dart`.
- The daily goal sheet lives in `features/progress/ui`: Settings and Streak both open it, and screen
  features never import each other.
- `streakProvider`, `nextReminder` and the reminder scheduler live in `features/progress`.
- Router: `/streak` in `Routes` and `router.dart`.
- Strings in `app_en.arb` and `app_ka.arb` (Georgian as a draft for native review); counts use
  ICU plurals ("1-day streak", "13-day streak"), numbers via `formatNumber`. Never uppercase.

## Testing

- `pindoro_core`: `streakOf` (one day, runs, a gap with and without a freeze, two gaps in a row,
  earning at 7 and 14, the cap of 2, a reset, `best`, today met or not, tomorrow's forecast) and
  the pill state at 17:59, 18:00, frozen and off.
- Mobile: the 5 → 6 migration; `markGoalIfMet` (below goal, crossing it, once a day, lowering the
  goal); `nextReminder` (before and after 19:00, met today, no streak); widget tests for the Home
  pill and ring, the Streak screen (calendar states, freeze copy, Change), the Results chip
  (crossed this round or not) and the Settings rows.
- Goldens for the four new design widgets (`just goldens`, Linux).
- Run only the touched tests locally; CI runs everything.

## Docs

- `apps/mobile/CLAUDE.md`: `goal_day`, the streak provider, reminders, `/streak`.
- `docs/TODO.md`: the streak sound waits for the sound kit; the reminder time is fixed at 19:00; the
  calendar shows the current month only; the pill doesn't turn atRisk at 18:00 while the app stays
  open (it updates on the next resume or change).

## Out of scope

The Pit stop and mastered districts (R3), lessons, tabs and the Me screen (R4), leagues and
accounts (R5), a reminder time picker, months other than the current one, and the streak sound.
