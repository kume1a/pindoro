# Badges — the starter eight

- Date: 2026-11-11
- Status: implemented
- Builds on: R5 and the v2.1 fixes (PRs #33–#40)
- Source: claude.ai design system, components `Badge` (README + preview: shield art, locked and
  unlocked states, the reward moment, the starter set), `Celebrations` (medium size) and
  `Illustration` (badge art rules); `docs/design/motion-sound-haptics.md` row "Badge unlock".
  `docs/TODO.md` § "Designed, not scheduled". No canvas board shows the Me shelf or the reward sheet
  in the app: their layout is decided here.

## Goal

Eight badges that reward playing in different ways, a shelf on Me that shows what is earned and
what is close, and a reward moment when a badge is earned while playing.

## Decisions

| Topic          | Decision                                                                                                                                                    |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Set            | First pin, Bullseye, On fire, Navigator, Road trip, Night owl, Explorer, Pit crew (the design's starter set)                                                |
| Explorer       | Know a street in 5 districts (raions) of one city. The design's "3 cities" can't be earned while the catalog has one city                                   |
| Past play      | Counts. Badges it already earned are awarded quietly at launch: on the shelf with the New pill, no reward moment                                            |
| Pit crew       | Counts streets cleared from the Pit stop from this update on: clearings were never recorded                                                                 |
| Once earned    | A badge is saved when earned and never locks again (a pack update can unmaster a district; Navigator stays)                                                 |
| Reward moment  | A sheet on the end screen (Results, Lesson complete, Unit complete), after the level-up moment if there is one; one sheet per new badge, in the set's order |
| Seen           | Closing a badge's reward sheet marks it seen. A quietly awarded badge is seen once the Me tab has shown it: the New pill stays until the next time Me opens |
| Tap on a badge | Nothing (no detail screen)                                                                                                                                  |
| Sound          | None: the "unlock chime" waits for the sound kit                                                                                                            |
| Schema         | App schema 11: tables `badge` and `review_cleared`. No API or pack change                                                                                   |
| Git            | Branch `badges` in the main checkout, one commit per part (core, design, app, docs), one PR, merge commit when green                                        |

## The badges

pindoro_core `lib/src/progress/badges.dart` holds the rules as pure functions.

```dart
enum BadgeId { firstPin, bullseye, onFire, navigator, roadTrip, nightOwl, explorer, pitCrew }

typedef BadgeStats = ({
  int pins,              // pin answers: rounds + lesson pin steps
  int perfects,          // of those, Perfect
  int bestStreak,        // streakOf(...).best
  int masteredDistricts, // raions with every street known, any city
  int knownDistricts,    // most raions with a known street, in one city
  int roadTrips,         // lesson trip answers (lesson step 11 + Final drive trips)
  bool lateAnswer,       // an answer or finished lesson between 00:00 and 03:59 local time
  int pitStopCleared,    // review_cleared rows
});

/// How far [id] is: earned once value >= target.
({int value, int target}) badgeProgress(BadgeId id, BadgeStats stats);
```

| Badge     | Glyph      | Field colour | Target | Value                | Condition copy              |
| --------- | ---------- | ------------ | ------ | -------------------- | --------------------------- |
| First pin | `pinDrop`  | `cobalt.500` | 1      | `pins`               | Drop your first pin         |
| Bullseye  | `star`     | `yellow.600` | 10     | `perfects`           | 10 Perfect answers          |
| On fire   | `flame`    | `orange.500` | 7      | `bestStreak`         | 7-day streak                |
| Navigator | `district` | `aqua.600`   | 1      | `masteredDistricts`  | Master a district           |
| Road trip | `car`      | `cobalt.700` | 5      | `roadTrips`          | Finish 5 road trips         |
| Night owl | `moon`     | `red.600`    | 1      | `lateAnswer ? 1 : 0` | Play after midnight         |
| Explorer  | `globe`    | `aqua.800`   | 5      | `knownDistricts`     | Know streets in 5 districts |
| Pit crew  | `wrench`   | `orange.700` | 50     | `pitStopCleared`     | Clear 50 Pit stop streets   |

The first six field colours are the design preview's; Explorer and Pit crew aren't drawn there, so
they take the darkest unused steps of the same hues (white glyph contrast). The design calls them
"route drills"; the app calls them road trips everywhere, so the copy does too. Values are capped
at the target for display.

## Data (app schema 11)

- `badge`: `id` (text, `BadgeId.name`, primary key), `earned_at`, `seen_at` (null until Me shows
  it). Rows are only ever inserted, then `seen_at` set once.
- `review_cleared`: `city_id`, `street_id`, `cleared_at`, one row each time a street leaves the
  Pit stop with two Greats in a row. Written in the same transaction that deletes its `review_item`,
  at both places that apply `nextReview` (`ProgressDao.recordAnswer` and the lesson's
  `reviewAnswers` path). A street cleared twice counts twice.
- Both tables belong to `ProgressDao`; migration 10 → 11 adds them (no backfill).

## Gathering the stats and awarding

A new layer, `features/badges` (after `league`, before the screen features in
`test/architecture_test.dart`):

- `readBadgeStats(dao, store)` builds `BadgeStats` fresh (an end screen awards right after its
  play is saved, before any provider reloads): `ProgressDao` counts (pins, perfects, road trips,
  late answer, cleared), the best streak from the goal days, and the per-raion known counts from
  each played city's installed pack (`DistrictKind.district` only). It never loads or downloads
  a pack: a fresh install on Welcome opens nothing. Opening an installed pack for a read moves
  into `readInstalledPack`, which Me's other-cities loop uses too.
- `awardBadgesProvider` reads the stats, inserts a `badge` row for every badge now earned that has
  none, and returns the new ids in the set's order.
- `badgesProvider` (watched by Me): every badge with its progress, `earnedAt` and whether it is
  new (`seen_at` null).

When it runs:

- **Launch, quietly, until the first badge:** while the `badge` table is empty (the first launch
  after the update, or a new player who hasn't finished anything), the app root awards quietly and
  shows nothing. This is how past play gets its rows. Once any badge exists it never runs again, so
  it can't take a badge whose moment an end screen is about to show.
- **End screens, with a moment:** Results, Lesson complete and Unit complete award as they open
  (their data is saved by then) and show a reward sheet for each new id once the arrival and the
  level-up moment (if any) are over. A badge earned on a screen that was killed, or in a Final drive
  left before Unit complete, is awarded at the next end screen.
- Awarding inserts with "or ignore" and returns only the rows it inserted, so two awards running at
  once never give the same badge twice.

## Design system (`pindoro_design`)

- `BadgeShield(glyph, field, {locked, size = 76})`: the design's shield (viewBox 88 × 100): a
  `color.yellow.400` rim, the coloured field inset 8, the glyph white at 1.5 × in the field.
  Locked: `color.path.node.locked.lip` rim, `.fill` field, `lock` glyph in `.icon`.
- `BadgeTile({shield, name, condition, progress, isNew, semanticLabel})`: a raised card with the
  lip (card press and focus rules), the shield, name in `title.sm` (secondary when locked),
  condition in `body.sm` secondary; locked and countable (target > 1): a 6 dp `Minibar`
  (`color.xp.fill` on `color.xp.track`); `isNew`: the "New" pill top-right (`color.accent.base` /
  `.on`, `label.sm`).
- The field colours become app tokens `color.badge.<id>` in `tokens/app.json`, aliasing the
  primitives above (components reference semantic tokens); `just gen`.
- Goldens `badge_{light,dark}.png`: the eight earned, three locked (one with progress, one
  uncountable, one New).

## Screens

**Me.** Between the stat tiles and Cities: `SectionTitle` "Badges · 3 of 8", then all eight
`BadgeTile`s in a 3-column grid (same row-height rule as the tiles), in the set's order. When the Me
tab opens, it takes the earned badges with no `seen_at` as this visit's New ones, sets their
`seen_at` and shows their pills until the tab opens again (Me stays mounted in the tab shell, so
"opens" is the tab becoming current, not a rebuild).

**Reward sheet** (`showBadgeReward(context, id)`): a modal bottom sheet on `color.reward.soft`,
centred: the 110 dp shield in `PopIn` with the medium `Celebration` burst behind it, "Badge
unlocked" in `headline.lg` `color.reward.text`, one sentence "{name} · {condition}.", and a hero
**Nice!** button in the reward variant that closes it.
`HapticFeedback.mediumImpact()` as the
shield lands. Reduce motion: no burst, and the shield is there at once (`PopIn`'s calm mode, as
every pop in the app). Closing the sheet any way (Nice!, back, a drag) marks it seen. The sheet is a
live
region read as "Badge unlocked. Bullseye, 10 Perfect answers."

## Strings (`app_en.arb`, draft `app_ka.arb`)

`badgeName` and `badgeCondition` (select on the badge id), `meBadges` ("Badges · {earned} of
{total}"), `badgeNew` ("New"), `badgeUnlocked` ("Badge unlocked"), `badgeRewardBody` ("{name} ·
{condition}."), `badgeNice` ("Nice!"), `a11yBadge` ("{name}, earned." / "{name}, locked,
{value} of {target}." / "{name}, locked." when the target is 1). Never uppercase.

## Testing

- pindoro_core: each badge's value and target, the cap, earned exactly at the target.
- `ProgressDao`: a graduation writes `review_cleared` (round and lesson paths); the stat counts
  (pins, perfects, a late answer at 01:30 local and none at 05:00, road trips); migration 10 → 11.
- `BadgeAwards`: awards what's earned, never twice; a district unmastered later keeps Navigator.
- Design goldens (Linux, `just goldens`).
- App: Me shows the shelf with progress and the New pill, and the pill is gone the next time the
  tab opens; a badge whose sheet was closed shows no pill; Results shows the First pin sheet for a
  first round; launch awards past play quietly only while there are no badges.

## Left out (to `docs/TODO.md`)

- The unlock chime (sound kit).
- A badge detail screen, sharing a badge, the earned date anywhere in the UI.
- Explorer as 3 cities (when a second city exists), and badges beyond the starter eight.
- Navigator's sheet names the district ("you mastered Vake"): it says the condition instead.
- Chests (the design's other reward moment): no chest exists.
