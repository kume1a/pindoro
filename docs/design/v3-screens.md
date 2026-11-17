# v3 screens: Flutter notes

Canvas: https://claude.ai/artifact/Q2dLJn2NTaWESxWgYy9EGb, page **v3 · Learn the whole city**.
Each board mounts a reusable screen part with a `state`. Copies of all files are in `v3-boards/`
(they load the canvas CSS, so read them as markup, not as runnable pages). Light theme only on the
canvas; dark comes from `PindoroTheme.dark` as before. All visuals use existing tokens and components
from the Pindoro design system unless listed under "New".

Street photos were dropped (SPEC §16.16) and taken off the canvas: no V3-31 board, no scene states.

## Boards

| Board | Shows | Screen part · states |
| --- | --- | --- |
| V3-00 Overview | Removed / changed / new; the daily loop; unlock ladder; local tables | — |
| V3-01 Rules | Pin → rating table, scheduler, card types, session plan, labels, recital tiers, landmark salience, new motion / sound / haptics | — |
| V3-10 Today | Today tab | TodayScreen · `ready`, `firstRun`, `backlog`, `done` |
| V3-11 Placement | Placement pins and result | SessionScreen · `placement`, `placementDone` |
| V3-20 New street | Intro, family intro, guess first | SessionScreen · `intro`, `introFamily`, `pretest` |
| V3-21 Reviews and reveals | Pin review, Great, Close, Mix-up | SessionScreen · `pin`, `great`, `close`, `mixup` |
| V3-22 Recall name and ends | Name it, extent | SessionScreen · `nameHidden`, `nameShown`, `extent` |
| V3-23 Families, crossings, bearing | Drills | SessionScreen · `family`, `crossings`, `orientation` |
| V3-24 Session done | Summary, Today after | SessionScreen · `done`; TodayScreen · `done` |
| V3-30 Junction decisions | J cards | RouteItemScreen · `junction`, `junctionRight`, `junctionWrong` |
| V3-32 Gateways, bridges, landmarks | G, B, personal landmarks, L cards | RouteItemScreen · `gateway`, `bridge`, `landmarkAdd`, `landmarkQuiz` |
| V3-40 Recital | Speak / type / draw, grading | RecitalScreen · `ask`, `listening`, `typing`, `result`, `resultIllegal` |
| V3-50 GPS-free drive | Setup, recording, review | DriveScreen · `setup`, `recording`, `review` |
| V3-60 Progress and settings | Progress, district, learning settings | ProgressScreen · `overview`, `district`; LearnSettingsScreen · `learning` |

## Screen notes

### Today (TodayScreen)
- Top bar: city switcher · streak pill. No XP pill.
- `ready`: hero card "Today's drive" (about N min, saves as you go) with three StatTiles (Reviews, New, Turns)
  and Start (primary). City memory card: big number, "of 3 282 streets", delta vs yesterday, stacked bar
  (Mastered cobalt 600 · Solid cobalt 300 · Known yellow 400 · Seen asphalt 300 · rest track). "Drive this run
  today" card (car icon, secondary Drive). List: current chunk and gateways solid.
- `firstRun`: Pindo cheering, "Let's see what you already know", three rows (main roads, district sample,
  home and work), Start placement / Start from zero.
- `backlog`: hero becomes "186 reviews waiting", New = 0, Catch up; info card explains most-overdue-first.
- `done`: "Done for today", streak kept, tomorrow's due; Learn 5 more / Free play (secondary).
- Controller: `TodayController` ← `Planner.plan`, `MemoryStats.cityMemory`, streak service.

### Session (SessionScreen)
- Top bar: Leave (×) · 12-segment bar (time budget, `miss` segments for Again) · pill with timer icon "14 min".
- Plate rules unchanged (two lines, shrink to 20 dp floor). Sub-line: other script · district when the name
  is shared by more than one street.
- `placement`: pin question with "I don't know this one" (tertiary) under Confirm.
- `placementDone`: Pindo proud, count, 4 StatTiles, Start learning.
- `intro`: answer street painted yellow; only streets the player already knows get labels (`pd-region-label`);
  intro sheet: Where it is, facts line (length · type · crossings · distance from centre), etymology line when
  present, TTS button + Got it.
- `introFamily`: parent and known siblings outlined and labelled; family chip ("26 May Street · 9 lanes, 6 dead ends").
- `pretest`: "Guess first" plate with hint icon; reassurance line above Confirm guess.
- `pin`: blank map, zoom controls, attribution, Confirm.
- `great` / `close`: RevealSheet; XP chip replaced by NextReviewChip (calendar icon, "Next review in 12 days") or
  "Back in this session" (retry icon) for Again.
- `mixup`: Miss tier colours with title "Mix-up"; truth street yellow, the street the pin hit as cobalt dashed with
  a name chip; chips "Back in this session", "Pair saved: 4th ↔ 5th".
- `nameHidden` → `nameShown`: question card with Pindo thinking; Show name (eye icon); then plate with the name,
  TTS, Forgot (secondary) / Knew it (great).
- `extent`: first pin with "End 1" chip, coach mark "Now drop a pin on the other end", Confirm disabled until both.
- `family`: parent labelled, lanes dashed with sockets; draggable lane chips in a wrapping tray; Check shows count.
- `crossings`: map panned down 60 dp; your drive cobalt with the car marker; junction rings numbered; current
  ring has a tip; text field + single fuzzy match row; Next crossing.
- `orientation`: BearingDial (new CustomPainter): your arrow cobalt dashed, truth yellow, ink arc; feedback bar.
- `done`: Pindo proud, 4 StatTiles (Reviews, New streets, Recalled %, Streak), City memory before → after,
  "Watch out for" (mix-ups, repeated Closes), Done / Learn 5 more.

### Route items (RouteItemScreen)
- `junction`: unlabelled local junction map (custom painter: land, buildings, roads with casing, park), approach
  arrow cobalt, car marker, landmark badge (fuel-station icon) + name label; three exit buttons placed on the arms
  (turn-left / straight / turn-right; selected = primary colours); optional "Then you're on" field; Confirm.
- `junctionRight`: correct exit painted with the route style (yellow), tier sheet Great with "Next in 9 days".
- `junctionWrong`: chosen exit cobalt dashed, correct exit yellow, Miss sheet naming the sibling junction.
- `gateway`: neighbourhood polygon (`pd-map-area`) with area label; pin; Confirm.
- `bridge`: numbered bridge tips on the map (selected = primary), A pin at the start, field for the bridge name.
- `landmarkAdd`: long-press ring; bottom sheet: name field, kind chips (Fuel, Metro, Church, Shop, Other),
  snapped junction row, approach row (editable), Save landmark.
- `landmarkQuiz`: plate with the landmark name and "added by you"; pin.

### Recital (RecitalScreen)
- Always without a map until the result. Endpoint card (A / B with context lines).
- Segmented control Speak · Type · Draw (Draw opens the existing road-trip screen).
- `ask`: 104 dp round mic button, instruction copy. `listening`: mic with soft halo, live transcript chips
  (streets as selected chips, turn words as small pills, landmarks as chips with icon), raw transcript line,
  "Done, check my route".
- `typing`: list of steps, Left / Straight / Right buttons, field "Next street or landmark", Check my route.
- `result`: map panned up 40 dp; best route yellow, yours cobalt dashed, divergence ring (ink), "+212 m" chip;
  Close sheet "26 % longer", decisions list with tier icons, Practise that turn / See all turns.
- `resultIllegal`: offending segment in Miss fill with "One-way: no entry" chip; sheet "Not drivable",
  chips "Turn added to practice" and "Wrong? Report this turn".

### GPS-free drive (DriveScreen)
- `setup`: today's run card, destination segmented control (Today's run · Surprise me · My own), three rules rows
  (locate-off, timer, info), Start drive (car icon), Plan it out loud first.
- `recording`: live dot, big tabular timer, distance, destination card; End drive (stop icon); escape link
  "Lost? Show the way (ends the test)". No map, no interaction needed while moving.
- `review`: best route yellow, recorded track solid cobalt with halo, U-turn marker; Great sheet, 3 StatTiles
  (Driven, Longer, U-turns), Done, credited turns line.

### Progress (ProgressScreen) and settings (LearnSettingsScreen)
- `overview`: City memory card (number, 10-week line chart cobalt 600 on cobalt 100 area, stacked bar, legend with
  counts), StatTiles (Recall 30 days, Whole city by), 14-day forecast bars (cobalt 300), district rows.
- `district`: number, stacked bar, StatTiles (Gateways solid, Landmarks), neighbourhood rows (done = cobalt check,
  now = play, next = lock), definition line for Mastered.
- `learning`: Time a day (15 / 20 / 30), explanation line, home / work rows, toggles (Turns and routes,
  Speak your answers), plate script segmented control, Reminder toggle.

## New design-system items (add to the system before building the screens that use them)

- Icons (same grid and stroke rules): `chart` (Progress tab), `mic`, `keyboard`, `photo`, `fuel-station`, `straight`,
  `turn-left`, `turn-right`, `external`, `locate-off`, `stop`, `eye`, `u-turn`, `home`, `briefcase`.
- Components: NextReviewChip (StatChip variant), MemoryBar (stacked bar + legend), IntroSheet (extends lesson intro),
  BearingDial, ExitButton (map-placed round icon button with selected state), LandmarkBadge, TranscriptChips, JunctionMap painter.
- Copy rules unchanged: sentence case, no uppercase transforms, buttons are verbs, tabular figures for numbers.

## Motion, sound and haptics (new events)

| Event | Motion | Sound · haptic |
| --- | --- | --- |
| Mix-up reveal | Both streets paint, cobalt then yellow (280 ms each) | Miss sound · Miss haptic |
| Next-review chip | Pops in after the tier title (celebrate small) | none |
| Speech token resolved | Chip slides in from the transcript | light tick |
| Drive start / end | Timer fades in / out | medium impact |
| Session done | Celebrate big; City memory counts up | results sound · success haptic |

## v3.1 · Tabs, filled

Canvas page **v3.1 · Tabs, filled** (boards V31-10 to V31-99, copies in `v3-boards/` with
`pindoro-v31.css`). The tabs were stacks of one to three cards; each now has one job and a layout for
every stage. Decisions (V31-99): one count everywhere (City memory, "in memory"); one header on
Today, Explore and Progress (city switcher and streak pill; Settings from Me only); City memory is a
row on Today and the full card on Progress; the chart's window grows with play (SPEC §16.4 item 20).

| Board | Shows | Flutter |
| --- | --- | --- |
| V31-10, V31-11 Today | Plan tiles of the kinds today holds (Drills new; New 0 · paused in a backlog), City memory row, Coming up: run, the neighbourhood being learnt (mini map), gateways, next 7 days, yesterday's mix-ups; done adds the last 7 days | `TodayScreen`; `nowLearningProvider`, `gatewaysProvider`, `mixUpsYesterdayProvider` |
| V31-20, V31-21 Explore | The city map first (district fills, play area dashed cobalt), a sheet: City memory, legend, quick starts, last round, areas played, all areas, next badge; Play pinned. **The app differs** (2026-11-17): the basemap sits under a veil, the legend is a key over the map, a tap on a district picks it, the sheet pins a play card (area, its City memory, difficulty, Play; or the round in progress) instead of the Play footer, and the quick starts are sideways cards | `HomeScreen` + `ExploreMap` (MapLibre), `PlayCard`, `explore_sheet.dart`; `areaMemoryProvider`, `homeProvider` (last round, recent areas) |
| V31-30 Progress | City memory card with the windowed chart and caption; recall and whole-city tiles with captions; What's coming (forecast, neighbourhoods in order); Where it grows (district map, legend, districts, the one being learnt first) | `ProgressScreen`; `progressProvider.coming` |
| V31-40 Me | "Streets in memory": City memory summed over the cities | `MeScreen` |
| V31-90 | New parts | `TileGrid`, StatTile `caption`, SectionTitle `meta`, `TitledCard`, `MemoryRow`, `WeekBars`, `StreakWeek`, `MiniTally`, `DistrictMap` (with `DistrictProgress.started`), `AreaMiniMap`, `SheetHandle`; token `color.map.district.started.fill` (app-only) |

Where the app differs from these boards is listed in `docs/TODO.md` (v3.1 tabs, filled).
