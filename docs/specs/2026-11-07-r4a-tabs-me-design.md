# R4a · v2.0 — tab shell and the Me screen

- Date: 2026-11-07
- Status: implemented
- Builds on: R3 (`docs/specs/2026-11-07-r3-pit-stop-design.md`)
- Source: `docs/design/v1-screens.md` § R4 · v2.0 (Tabs R4-14); claude.ai screens canvas boards
  R4-14 Tabs, `MeScreen`, `PitStopScreen` (tab and empty), `HomeScreen` at `release="r4"`, R4-63
  motion table; design system StatTile README and `bundle.css` (`.pd-nav`, `.pd-stattile`)

## Goal

R4 · v2.0 "Lessons and road trips" ships in four parts (R4a–R4d). R4a is the first: the app gets a
bottom navigation with three tabs (Free play, Pit stop, Me; the Path tab arrives in R4b) and the new
Me screen with the level card, four stat tiles, the cities with progress and the settings gear.

## Decisions

| Topic                | Decision                                                                                              |
| -------------------- | ----------------------------------------------------------------------------------------------------- |
| Home's Pit stop card | Dropped (canvas r4): the tab badge carries the due count. Card, `HomeData.pitStopDue` and strings go   |
| Lessons, Road trips  | All four tiles now; Lessons and Road trips read 0 until R4b / R4c wire them (TODO.md)                  |
| Tab badge            | Cobalt count pill (`color.primary.base` / `.on`), `label.sm` tabular, 18 dp, 2 dp `surface.raised` ring |
| Back at a tab root   | Pit stop or Me → Free play; Free play → leaves the app                                                 |
| Pushed screens       | Every non-tab route stays top-level (root navigator) and covers the bar, as now                       |
| Re-tap active tab    | Scrolls that tab to the top (canvas R4-14)                                                             |
| Switching tabs       | Cross-fade `duration.fast` (200 ms), no slide; reduce motion: instant; `selectionClick` (R4-63)        |
| Me city row          | Chooses that city and opens Free play                                                                  |
| Me tiles             | Best streak opens Streak; the others aren't tappable until their lists exist (TODO.md)                |
| Results Done         | Unchanged: Free play with the Home intro, also after a Pit stop round                                  |

## Design system (`packages/pindoro_design`)

**`PindoroNavBar`** (new `lib/src/widgets/navigation.dart`), from `.pd-nav`:

- `PindoroNavBar({required List<PindoroNavItem> items, required int current, required
  ValueChanged<int> onSelect})`, with
  `typedef PindoroNavItem = ({PindoroGlyph glyph, String label, int? badge, String? semanticLabel})`.
- `color.surface.raised`, 2 dp `color.line.base` top rule. Items share the width (`Expanded`, so
  200 % labels fit), 10 dp from the top: a 56 × 34 icon pill (`radius.md`, `color.tab.active.bg`
  when current) with the 24 dp glyph, a 3 dp gap, the `label.md` label; `color.tab.active.icon` /
  `color.tab.inactive.icon`. Under the labels: the bottom inset, at least 8 dp. The canvas lets the
  labels dip into the iPhone's 34 dp inset (84 dp in all); on Android the gesture handle and the
  3-button bar sit there, so the labels stay above the inset (found on the device check).
- Badge (when `badge > 0`): a cobalt pill on the icon pill's top-right corner, min 18 × 18, 5 dp
  side padding, `radius.full`, `color.primary.base`, digits in `label.sm` with tabular figures in
  `color.primary.on`, a 2 dp `color.surface.raised` ring.
- Each item is a `Tappable`: a button, `selected` when current, labelled `semanticLabel ?? label`.

**`StatTile`** (in `surfaces.dart`), from the StatTile README: a `LipBox` with a `color.line.base`
border and lip, `radius.lg`, padding `space.3`. Label row: an optional 20 dp glyph (colour
parameter, default `color.primary.text`), 6 dp, `label.md` in `color.text.secondary`. Value:
`numeric.md`. One semantics label, "Label, value" by default; an optional `onTap` through `Tappable`.

**`ListRow.below`**: an optional widget under the subtitle (Me's city minibar).

Tests (`components_test.dart`): the nav bar reports the tapped index, marks the current item
selected and reads the badge label; a stat tile is one label. Golden `navigation_{light,dark}.png`:
two bars (Free play current; Pit stop current with badge 7) and Me's 2 × 2 tiles.

## App (`apps/mobile`)

**Shell** (`lib/app/router.dart`, new `lib/app/tab_shell.dart`):

- A `StatefulShellRoute` with branches `/` Free play (`HomeScreen`, keeps the `extra` summary),
  `/pit-stop` (`PitStopScreen`) and `/me` (`MeScreen`); new `Routes.me`. The old top-level
  `/pit-stop` route goes. The shell page keeps `_fadePage`. Other routes stay top-level, so they
  cover the bar.
- `navigatorContainerBuilder`: a fading indexed stack (inactive branches at opacity 0, ignoring
  pointers, tickers off; `durationFast`, instant under reduce motion).
- `TabShell`: `Scaffold(body: container, bottomNavigationBar: PindoroNavBar(...))`. Items: Free
  play `map`; Pit stop `wrench` with the badge = the `pitStopProvider` due count ("Pit stop, 7
  streets due"); Me `user`. A tap plays `feedbackProvider.tap()`, then `goBranch(i)`; on the current
  tab it animates that tab's scroll controller to 0 (`durationBase`, `easeDecelerate`; reduce
  motion: jump). `PopScope`: can pop only on Free play, otherwise back runs `goBranch(0)`.
- One `ScrollController` per tab, made in `buildRouter` and given to each branch page through
  `PrimaryScrollController` (the pages' `ListView`s already use the primary controller).
- `bottomActionGap` (`core/page_scaffold.dart`): inside the shell
  (`StatefulNavigationShell.maybeOf(context) != null`) footers end 12 dp above the bar (canvas r4
  Home `footPad`); elsewhere the safe area + 26 dp, as now.

**Free play** (`features/home`): no settings gear and no Pit stop card. `pit_stop_card.dart`,
`HomeData.pitStopDue` with its query, and `homePitStopDue` / `homePitStopReview` (en, ka) go.

**Pit stop tab**: `PitStopScreen` unchanged; as a branch root it has no back button
(`PageScaffold` already hides it when it can't pop). `go(Routes.pitStop)` lands on the tab.

**Level card**: `LevelCard` moves to `features/progress/ui/level_card.dart` (Me can't import home)
and takes `subtitle`, `caption`, an optional `trailing` and an optional `bar` (default: a plain
`XpBar` with the level label). Home passes its intro bar, the goal ring, "195 XP to level 4" and
"3 555 XP in total"; Me passes "4 062 XP in total · playing since November" and "1 438 XP to level
5". Both keep "312 / 1 750 XP" on the right.

**Me** (new slice `features/me`, added to the architecture test's feature layer):

- `data/me_data.dart`, `meProvider` (autoDispose; follows `progressChangesProvider`, the chosen
  city and `streakProvider`): total XP, the first round's start (`ProgressDao.firstRoundAt()`, null
  before any round), the best streak, and the cities: the chosen city first, then the other played
  cities (`recentCityIds`). Each city's known / total streets come from its pack: the open one, or
  its installed pack opened read-only and closed again. A played city without an installed pack is
  skipped.
- Known counts: Home's `countsAt` becomes `ProgressDao.knownIn(PackRepository pack, streets,
  {before})` (pindoro_core types only, so the progress layer can hold it); Home and Me both use it.
- `ui/me_screen.dart`: `PageScaffold(title: "Me", showBack: false, trailing: the settings gear →
  push /settings)`; the level card; 2 × 2 `StatTile`s with 8 dp gaps and equal heights: Streets
  known (`pin`, the sum over cities), Lessons (`road`, 0), Road trips (`car`, 0), Best streak
  (`flame` in `color.streak.flame`, "21 days", opens `/streak`); a "Cities" section; a `ListGroup`
  of rows: `pin` tile, city name, "180 / 1 240 streets", `Minibar`, chevron; read as "Tbilisi, 180
  of 1 240 streets known"; a tap runs `chooseCity` and `go(Routes.home)`.
- "playing since": `DateFormat.MMMM` (the standalone month in Georgian), `yMMMM` when not this year.
- New strings (en + ka drafts): tab labels, the Pit stop tab label (plural), Me's title, Cities,
  the four tile labels, "{n} days" (plural), the level subtitle with the start month, the city
  row's count and label.

## Testing

- `packages/pindoro_design`: `components_test.dart` (nav bar, stat tile, the new golden).
  `just goldens` regenerates the goldens on Linux.
- `apps/mobile`: `test/app/routing_test.dart` (Settings through Me; tabs keep their state; back
  from Me lands on Free play; re-tap; badge), `test/app/home_results_test.dart` (the R3 "Review
  opens the Pit stop" test becomes "the Pit stop tab badges the due count"; Me shows the level,
  tiles and cities; a city row opens Free play), `test/features/progress/progress_dao_test.dart`
  (`firstRoundAt`, `knownIn`), `test/architecture_test.dart`.
- Emulator: tabs and the cross-fade, the badge with seeded `review_item` rows, a Pit stop round from
  the tab, Me's numbers, Settings from the gear and back, system back from each tab, re-tap scroll,
  the dark theme, 200 % text on the bar.

## Out of scope (docs/TODO.md)

Lessons and Road trips counts (R4b, R4c); the lists behind the Me tiles; Me's city subtitle "Unit n
· district" (R4b); the Path tab and re-tap to the current stop (R4b); played cities without an
installed pack.
