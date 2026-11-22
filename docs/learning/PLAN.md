# Pindoro v3 build plan

Work top to bottom. Each step is one Claude Code task: read the named spec sections and design boards
first, propose a plan, write tests first for logic, keep the app green. A milestone is done when its
acceptance list passes. Spec = `docs/learning/SPEC.md`. Boards = canvas page "v3 · Learn the whole city"
(index in `docs/design/v3-screens.md`, markup copies in `docs/design/v3-boards/`).

There is no self-experiment gate (decided 2026-11-14): the whole app is built M0 → M8 with the SPEC
§13 defaults, and M8 tunes them from real review logs. Research report 1 §5 keeps the experiment
design in case it is run later.

---

## M0 · Prepare the repo (half a day)

Status: steps 1–3 done (2026-11-14).

1. Add the handoff files: `docs/learning/SPEC.md`, `docs/learning/PLAN.md`, `docs/design/v3-screens.md`,
   `docs/design/v3-boards/`, `docs/research/` (the two reports), and append `CLAUDE.md-section.md` to the root
   `CLAUDE.md`.
2. Create `packages/pindoro_learning` (pure Dart, part of the pub workspace) with `lib/src/constants.dart`
   holding every value from SPEC §13, an empty public API, and its tests in `just test-dart` (which CI runs).
   The root `analysis_options.yaml` covers it, as it does the other packages.
3. Add `shared/fixtures/fsrs_vectors.json` generated with py-fsrs (SPEC §14) by a small script in `tools/`
   that runs once in Docker (`just fsrs-vectors`), never in CI.

Accept: `just test` (or the repo's test command) is green; the new package is in CI; no app behaviour changed.

## M1 · The core loop

Status: steps 1–8 done (2026-11-16).

Spec §2.2, §3 (P only), §4, §5.1, §6.4, §7, §8 (Known only), §12, §16. Boards V3-01, V3-20, V3-21, V3-24, V3-10.

1. **FSRS-6** in `pindoro_learning`: `Fsrs.next(state, rating, now)`, `Fsrs.retrievability(state, now)`,
   intervals with fuzz from a seeded `Random`, max interval. Tests must match the golden vectors to 1e-4.
2. **Grader**: `Grader.gradePin({pin, target, nearby, rtMs, history})` → `{tier, rating, distanceM, snapStreetId,
   isMixUp}`; confusable set from family table (stub until M2: same base name + logged confusions), parent and
   siblings when present. Fixture tests for every row of SPEC §5.1.
3. **Local tables**: Drift migration adding `card_state`, `review_log`, `confusion`, `learn_settings`. Repository
   classes in the app; pure mapping functions in the package.
4. **Session planner**: `Planner.plan({cards, newCandidates, minutesPerDay, now, seed})` → ordered list of
   steps (intro, retrieval1, review, retrieval2, relearn). Tests: normal mode, backlog mode, interleave order,
   relearn gap 5–10.
5. **New-street source (temporary)**: new streets come from the existing course order (`buildCourse`
   from the start district) until M2 step 2's curriculum queue replaces it. The current Path and Free
   play stay untouched until M3.
6. **Session UI** (SessionScreen states: `intro`, `pin`, `great`, `close`, `mixup`, `done`):
   - intro sheet with facts, TTS, known-street labels on the map;
   - reveal sheets with the next-review chip instead of XP; Mix-up reveal (truth yellow, hit street cobalt dashed);
   - top bar with minutes left; auto-save after each answer.
7. **Today (minimal)**: `ready` and `done` states with today's counts and Start; reachable from the current home
   in builds made with `--dart-define=V3=true` (the flag goes in M3).
8. **Export**: Settings → "Export review log (CSV)".

Accept: a 20-minute session runs end to end offline; after Again a street comes back 5–10 items later;
tomorrow's due count matches FSRS; the CSV opens with every column of SPEC §2.2.

## M2 · Curriculum, placement, progress

Status: done (2026-11-16).

Spec §2.1 (ring, bank, tier, chunk, family), §6, §8. Boards V3-10, V3-11, V3-20 (`introFamily`, `pretest`), V3-60.

1. **Pipeline**: add `ring`, `bank`, `tier`, `chunk_id`, `etymology`, the `family` table, `district.parent_id`
   and `chunk_neighbour` to the pack (SPEC §16); `centre` and `river` go in `city.yaml`. Bump the pack schema
   version and keep reading old packs. The family step prints the data check (share of "Nth Lane / Dead
   End of X" within 500 m and 1.5 km of X, and the orphans); commit it to `docs/research/family-check.md`.
2. **Curriculum queue** in `pindoro_learning`: placement set, tier B order, chunk order from home/work anchors,
   within-chunk order, 60/40 split, sibling cap, parent-before-child. Property tests over the Tbilisi fixture pack.
3. **Placement flow** (SessionScreen `placement`, `placementDone`; TodayScreen `firstRun`).
4. **Family intro and guess-first** (`introFamily`, `pretest`).
5. **Progress tab** (`overview`, `district`): City memory, recall rate, 14-day forecast, whole-city date,
   district and chunk rows.
6. **Learning settings** (minutes a day, home, work, plate script, reminder).
7. **Migration for existing players**: every street "known" today becomes a P card created as Good with
   `prior_known = 1` and due in 1–7 days (spread), so nothing is lost and nothing is trusted forever.

Accept: a new install goes Welcome → placement → Today; the curriculum never offers a child before its parent
is at S ≥ 3 d; City memory falls when the clock is advanced without reviews.

## M3 · Replace the old game layer

Status: done (2026-11-16).

Spec §8. Boards V3-00, V3-10, V3-24.

1. Tabs become Today · Explore · Progress · Me (StatefulShellRoute, 4 branches). Explore = the MVP Home and flow,
   minus XP; its answers feed `card_state` (SPEC §5.1; first-sight successes create cards like placement, failures
   on unseen streets are logged only).
2. Remove XP per answer, the daily XP goal, levels, level-up screen, leagues (app and server endpoints), the Path,
   unit sheets, Jump ahead and the Pit stop tab. Delete their code and tests; keep the tier visuals and sounds.
3. Streak rule: day counts when due is cleared or the minutes are spent; keep freezes and the reminder.
4. Badges: neighbourhood / district Mastered, 100-day maintenance, zero leeches; City memory milestones.
5. Backlog state on Today; "Learn 5 more".

Accept: no XP strings or league calls remain (grep); streak behaves per spec in clock-advance tests.

## M4 · More street cards and drills

Status: done (2026-11-16).

Spec §3 (N, E, drills), §5.2, §4 (leeches). Boards V3-22, V3-23.

1. N cards (`nameHidden`, `nameShown`) with the 1-in-10 verification.
2. E cards (`extent`): two pins, Confirm after both.
3. Family sweep (`family`), crossings drill (`crossings`), bearing (`orientation`).
4. Leech handling and the side-by-side contrast for top confusions.

Accept: unlock rules match SPEC §3 in tests; drills never write their own `card_state` rows.

## M5 · Directed graph and route items

Status: done (2026-11-16). Road trips were removed in M3, so step 2 is the routing itself and the
M6 route drawing following legal exits.

Spec §2.1 (edges, restrictions, junction items, landmarks), §3 (J, G, B, C, L), §5.2, §6.5–6.6, §9.
Boards V3-30, V3-32.

1. **Pipeline**: directed edges, turn restrictions, edge-expanded graph; junction-item selection by OD
   coverage; OSM landmarks with salience; attach landmarks to junction items. Coverage report output.
2. **Road trips** move to the directed, restricted graph (existing route drawing keeps working).
3. Cards J (`junction`, `junctionRight`, `junctionWrong`), G (`gateway`), B (`bridge`), C (typed), L1–L3
   (`landmarkQuiz`); personal landmarks (`landmarkAdd`) with long-press and "here".
4. Route items in the planner: cap 10 new a day; pause rule.

Accept: a one-way violation is impossible in drawn routes; each J card's exits are only the junction's legal exits.

## M6 · Recitals and GPS-free drives

Status: done (2026-11-16) without step 3: speech is parked (SPEC §16.15 item 73, `docs/TODO.md`).

Spec §5.3, §11. Boards V3-40, V3-50.

1. `RecitalGrader` (tokenise, resolve, Viterbi with connectors, stretch, decisions) with fixture tests.
2. Recital UI: Type and Draw modes first (`ask`, `typing`, `result`, `resultIllegal`); implicit evidence to J cards.
3. Speech (`listening`): Vosk Georgian model download, constrained grammar, transcript chips, self-grade fallback.
   Prototype on iOS before committing.
4. Drive mode (`setup`, `recording`, `review`): background location, map matching, U-turn and hesitation flags,
   "Drive this run today" card on Today.

Accept: the illegal-route fixture is graded "Not drivable"; a recorded test drive replays as a matched path.

## M7 · Street photos (dropped)

Spec §10. Boards V3-30 (`sceneAction`), V3-31.

1. Pipeline: Mapillary pull for junction approaches (25–40 m before, heading-matched), crop, WebP, licence and
   author; separate optional "photo pack" download.
2. Own captures: Panoramax on the home server (Docker); import frames for junctions without coverage.
3. S1, S2, S3 cards; attribution line on every photo; "Look around in Google Maps" deep link only.

Accept: every displayed photo shows its source and licence; no Google API key exists in the app.

Status: dropped (2026-11-16). Mapillary covers too little of Tbilisi to be worth a card type, and
Google Street View can't be used inside the app (SPEC §10, §16.16). The build is kept on the unmerged
`feat/v3-m7` branch.

## M8 · Tuning

1. Offline FSRS fit from exported logs; load weights from a JSON override.
2. Calibration chart (predicted R bins vs observed) in a debug screen.
3. Revisit SPEC §13 and the open questions in SPEC §15.

Status: done (2026-11-16). The fit, the calibration and the tier C relief run on the player's own
log, so the weights and §13's numbers change only once there are real reviews (SPEC §15, §16.17).

## M9 · Navigation that fades

Spec §16.23. Research `docs/research/03-navigation-that-fades.md`. Boards V32-* (canvas page
"v3.2 · Navigate and learn").

1. Drive log: the append-only drive table, its track (fixes with accuracy) kept 90 days, GPS gaps
   in the review, Past drives from Me.
2. Navigation core in pindoro_learning (tests first), the per-decision log table and §16.23's
   numbers in §13 and `constants.dart`: main-road edge cost (an optional cost on
   `RoadGraph.shortestRoute`, Dart only, default unchanged), a route's decisions, silent-eligible,
   the suggested level and its steps, the navigator (per fix: position, next decision, prompts,
   recovery, guard) and the evidence guards.
3. Driving screens: setup (destination search, quick destinations, level), preview, Guided,
   Coached and Quiet, recovery, Off with Rescue, no input above 5 km/h, voice with ducking,
   screen kept on.
4. Debrief and review: recall before reveal, the drill, the pointing probe, Past drives.
5. Learning hooks: success credit, your routes first, reverse J items, the weekly goal, Today and
   Progress cards.

Accept: a recorded drive replays to the same decisions and evidence; nothing takes input above
5 km/h; a Guided drive never writes a review.

Status: step 1 done (2026-11-21, schema 23). Past drives is one list, not grouped by week, and
opens from Me only until Progress has its routes (step 5).
