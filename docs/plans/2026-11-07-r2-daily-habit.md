# R2 Daily habit Implementation Plan

> **For agentic workers:** Implement this plan one task at a time. Steps use checkbox (`- [ ]`)
> syntax for tracking. The user approved this batch's git flow: worktree `../pindoro-r2`, branch
> `r2-daily-habit`, one commit per task, PR, merge commit once CI is green.

**Goal:** Daily XP goal, streak with freezes, Streak screen, Results streak chip, Settings goal and
an evening reminder (spec: `docs/specs/2026-11-07-r2-daily-habit-design.md`).

**Architecture:** Only goal-met days are stored (`goal_day`). `pindoro_core` `streakOf` derives the
streak, best, freezes and frozen days from them. `features/progress` exposes `streakProvider` and
the reminder logic. The screens read the provider. Four new `pindoro_design` widgets draw it.

**Tech Stack:** Flutter, Riverpod 3 (no codegen), Drift (schema 6), go_router, gen-l10n,
`flutter_local_notifications` 22 + `timezone`.

## Global Constraints

- Design values only from `pindoro_design` tokens; never hand-edit generated code; `just gen`.
- Never uppercase UI strings; numbers through `formatNumber`; tabular figures.
- Every UI string in `app_en.arb` and `app_ka.arb` (Georgian is a draft).
- Layers: `l10n` → `core` → `features/progress` → `features/pack` → `features/map` → screen
  features → `app`; screen features never import each other (`test/architecture_test.dart`).
- Goals 250 / 500 / 1 000 XP, default 500. Freeze every 7 goal days, max 2. At risk from 18:00.
  Reminder at 19:00. Big celebration on 7, 30, 100, 365 days.
- Run only the touched tests locally; CI runs everything.

---

### Task 1: Streak rules (`pindoro_core`)

**Files:**

- Create: `packages/pindoro_core/lib/src/progress/streak.dart`
- Modify: `packages/pindoro_core/lib/pindoro_core.dart` (export)
- Test: `packages/pindoro_core/test/streak_test.dart`

**Produces:**

- `DateTime calendarDay(DateTime local)` (UTC midnight of the local date),
  `String dayKey(DateTime day)`, `DateTime parseDayKey(String key)`
- `abstract final class StreakRules { goals, defaultGoal, freezeEvery, maxFreezes, riskHour,
  reminderHour, milestones }`
- `enum StreakPillState { active, atRisk, frozen, off }`
- `class StreakSummary { today, days, best, freezes, metToday, frozenDays;
  StreakPillState pillState(DateTime now); bool get yesterdayFrozen }`
- `StreakSummary streakOf(Set<DateTime> metDays, DateTime today)`

- [ ] Write `streak_test.dart`:
  - no days → 0, 0, 0
  - three days in a row ending today → days 3, metToday
  - ending yesterday, today unplayed → still 3, not metToday
  - a gap with no freeze resets; best keeps the old run
  - 7 days earn a freeze; a gap after them is frozen, and the run continues without growing
  - 14 days → 2 freezes; 21 → still 2
  - two missed days with one freeze → reset
  - `pillState`: met → active; 17:59 → off, 18:00 → atRisk (days > 0); yesterday frozen → frozen;
    18:00 with 0 days → off
  - forecast: `streakOf(days, tomorrow)` after a missed today uses a freeze
  - `dayKey`/`parseDayKey` round-trip
- [ ] Run `dart test test/streak_test.dart` in `packages/pindoro_core` → fails (no symbols)
- [ ] Implement (the walk is in the spec § Rules) → passes
- [ ] Commit `feat(core): streak rules from goal-met days`

### Task 2: Data — schema 6, goal days, streak provider

**Files:**

- Modify: `apps/mobile/lib/core/database/database.dart` (`GoalDays` table, `dailyGoal`, `reminder`,
  `schemaVersion` 6, `from5To6`)
- Modify: `apps/mobile/lib/core/database/settings_dao.dart` (`setDailyGoal`, `setReminder`, defaults)
- Modify: `apps/mobile/lib/features/progress/data/progress_dao.dart` (`markGoalIfMet`,
  `recordAnswer` in a transaction, `goalDays`, `xpOn`, `goalRoundOn`; `progressChangesProvider`
  also watches `goal_day`)
- Create: `apps/mobile/lib/features/progress/data/streak.dart` (`StreakView`, `streakProvider`)
- Create: `apps/mobile/drift_schemas/drift_schema_v6.json` (by `just gen`)
- Test: `apps/mobile/test/features/progress/progress_dao_test.dart`,
  `apps/mobile/test/core/database/settings_dao_test.dart`; migration test runs as is

**Produces:**

- `ProgressDao.markGoalIfMet(DateTime now, {String? roundId})`, `Future<Set<DateTime>> goalDays()`,
  `Future<int> xpOn(DateTime day)`, `Future<String?> goalRoundOn(DateTime day)`
- `SettingsDao.setDailyGoal(int goal)`, `setReminder({required bool on})`
- `typedef StreakView = ({StreakSummary summary, Set<DateTime> metDays, int goal, int todayXp,
  String? goalRoundId})` with `double get goalProgress`
- `final streakProvider = FutureProvider<StreakView>`

- [ ] Tests: below the goal nothing is marked; crossing marks today with the round id; a second
  crossing keeps the first row; lowering the goal then `markGoalIfMet` marks with a null round;
  `xpOn` counts only that local day; settings setters persist
- [ ] Implement; `just gen` writes the v6 dump; run the migration, progress and settings tests

### Task 3: Design widgets

**Files:**

- Create: `packages/pindoro_design/lib/src/widgets/streak.dart` (`StreakPill`, `DailyGoalRing`,
  `StreakCalendar`, `StreakDay`, `StreakFreezeCard`)
- Modify: `round_hud.dart` (`Pill` gains `tone: PillTone` and `iconAccent`), `graphics.dart`
  (`PindoroIcon.accent` recolours the flame core), `pindoro_design.dart` (export)
- Test: `packages/pindoro_design/test/components_test.dart` (calendar label test + `streak_*`
  goldens)

**Produces:**

- `enum PillTone { normal, off, risk, frozen }`
- `StreakPill({required String label, required StreakPillState state, required String
  semanticLabel, VoidCallback? onPressed})`
- `DailyGoalRing({required double progress, double size = 56, String? semanticLabel})`
- `enum StreakDay { met, frozen, missed, plain }`;
  `StreakCalendar({required DateTime month, required StreakDay Function(int day) dayState,
  required int today, required int firstWeekday, required List<String> weekdays,
  required String semanticLabel})` (`today` 0 when the month isn't the current one)
- `StreakFreezeCard({required String title, required String body})`

- [ ] Widget test: the calendar is one image with its label; the pill is a button
- [ ] Goldens via `just goldens` (Docker), commit the PNGs

### Task 4: Home, Streak screen, daily goal sheet

**Files:**

- Create: `apps/mobile/lib/features/streak/ui/streak_screen.dart`
- Create: `apps/mobile/lib/features/progress/ui/daily_goal_sheet.dart` (`showDailyGoalSheet`)
- Create: `apps/mobile/lib/features/progress/ui/streak_labels.dart` (pill semantics, goal ring
  semantics, shared by Home and Streak)
- Modify: `home_screen.dart` (pill in the reserved slot), `level_card.dart` (ring), `routes.dart`
  (`streak`), `router.dart`, `architecture_test.dart` (`features/streak`), both `.arb` files
- Test: `apps/mobile/test/features/streak/streak_screen_test.dart`, Home pill/ring in
  `test/app/home_results_test.dart`

- [ ] Tests: Home shows the pill and ring; tapping the pill opens Streak; Streak shows the count,
  best, freeze copy for 0 and 1 freezes, and Change opens the sheet that saves 1 000

### Task 5: Results chip and Settings goal row

**Files:**

- Modify: `results_screen.dart` (flame chip, count-up when this round met the goal, big
  celebration on milestones, `feedback.streak()`), `core/settings.dart` (`GameFeedback.streak`),
  `settings_screen.dart` (Daily goal section with the goal row), `.arb` files
- Test: `test/app/home_results_test.dart` (chip after a goal-meeting round), a Settings test

### Task 6: Reminder

**Files:**

- Modify: `apps/mobile/pubspec.yaml` (`flutter_local_notifications`, `timezone`)
- Create: `apps/mobile/lib/features/progress/data/reminders.dart` (`nextReminder`, `Reminders`,
  `remindersProvider`, `reminderPlanProvider`, `syncReminder`)
- Modify: `app.dart` (listen and sync), `settings_screen.dart` (Reminder row: permission, toast),
  Android `build.gradle.kts` (desugaring), `AndroidManifest.xml` (permissions, receivers),
  notification icon drawable, `.arb` files
- Test: `apps/mobile/test/features/progress/reminders_test.dart` (`nextReminder`: before 19:00
  unmet → today; met → tomorrow with today's run; after 19:00 unmet → tomorrow with the forecast);
  Settings reminder toggle with a fake `Reminders`

### Task 7: Docs

- `apps/mobile/CLAUDE.md`, `docs/TODO.md`, spec status → implemented
- `just lint`; touched tests; push; PR; merge when green
