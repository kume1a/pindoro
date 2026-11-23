# pindoro_design

Flutter design system: generated tokens, `buildPindoroTheme`, `PindoroTheme` extension and the
Signpost widgets: `PindoroButton`, `StreetPlate`, surfaces (`LipBox`, `ListGroup`, `ListRow`,
`RowTile`, `StatTile`, a one-line `ListRow(dense: true)`, `TileGrid`, `TitledCard`, `SheetHandle`), the bottom navigation (`PindoroNavBar`, no counts on tabs), controls
(`SegmentedControl`, `PindoroToggle`, `PindoroIconButton`, `PindoroDialog`, `LaneLoader`, the
loading `Skeleton`), graphics (`PindoroIcon`, `Pindo`, `Wordmark`, `PinMark` incl. the route's
`PinMark.endpoint`, `CarMark`, Guided's `ArrowMark`, `glyphPng` and `onewayArrowPng` for map images), the round components (`QuestionBar`,
`Pill`, `MapControl`, `RevealSheet` and its `TierSheetFrame`, `ResultRow`, `TierTally`,
`CoachBubble`), the v3 session (`StatChip`, `NextReviewChip`, `IntroSheet`, the drills'
`BearingDial`; the session bar is `QuestionBar` with `height: 14`), v3 route items (`ExitButton`,
`LandmarkBadge`, `MapLabelChip`, `CarMarker`, `MapTip`), v3
progress (`MemoryBar`, `MemoryLegend`, `MemoryChart`, `ForecastBars`, `WeekBars`, `MemoryRow`), the streak (`StreakPill`, `StreakCalendar`, `StreakWeek`,
`StreakFreezeCard`), badges (`BadgeShield`, `BadgeTile`; fields `color.badge.*`),
setup components (`SearchField`, whose keyboard goes at a tap outside it, `PindoroChip`, `DifficultyCard`, the painted `DistrictMap` and `AreaMiniMap`), `MiniTally`,
the drive (v3.2: `DriveGlyph`, `TurnPlate` with `LaneArrows`, `DriveBottomBar` with
`DriveBarButton`, Guided's `DriveMapButton` column (`DriveCompass`, `DriveRecentre`), `RouteOptions`,
`LevelPickerCard`, `StreetChip`, `SpeedNow`, `SpeedLimitSign`, `CameraBadge`, `DistrictLine`, `HeadingDial`, `StatusDot`, `SpeakingBars`, `RecoveryBand`, `RecordingDot`,
`LevelPicker`, `LevelSuggestion`, `StoppedBar`; their `color.drive.*` are day in the light theme and night
in the dark one, and drive type ignores the text scale), the v3.2 parked parts in the app theme (`ReviewMark`, `TurnNumber`, `StartRing`,
`DestinationFlag`, `StepDots`, `TierChip`, `GoalLine`, `PlanChecklist`, `RouteLevelStair`, `SuggestionCard`,
`DialResultChip` and `BearingDial`'s pointing `calibrating`/`degrees`), the answer trays (`AnswerTray` docked over
the map in place of floating chips; the family sweep's `SweepTray` and `SweepSocket`)
and motion (`PindoroPageTransitions`, `CountUp`, `PopIn`, `RiseIn`, `Celebration`, `Wiggle`,
`Shake`, `FadeIndexedStack`; all calm down under reduce motion). Widgets take their text as
parameters; strings live in the app.

## Tokens

- `tokens/tokens.json` is the claude.ai design system's file, copied verbatim (never edit it here;
  change it on claude.ai and copy it again). `tokens/app.json` holds app-only tokens in the same
  format (none since the 2026-11-20 sync); duplicates of a design-system token fail the
  generator. Intent lives in `docs/design/*.md`.
- `tool/generate_tokens.dart` writes `lib/src/generated/pindoro_tokens.dart`: `PindoroPalette`
  (primitives), `PindoroColors.light` / `.dark` (semantic + component colours, aliases resolved),
  `PindoroSpace.s4`, `PindoroRadius.lg`, `PindoroElevation.e2`, `PindoroSize`, `PindoroStroke`,
  `PindoroMotion`, `PindoroOpacity`, `PindoroShadow`, `PindoroCamera` and `PindoroType` roles.
  **Never hand-edit generated code** — commit the token JSON and run `just gen`; the generated
  Dart is not committed (`just setup` and CI generate it).
- No literal colours, radii, spacing or durations in widgets. Theme-dependent colours come from
  `PindoroTheme.of(context).colors`, never from `PindoroPalette` directly.

## Assets

- `assets/icons` (76), `assets/logos`, `assets/mascot` come from the claude.ai design system's
  asset groups. Icons are drawn in asphalt ink (#1B2133) with white details; `PindoroIcon` maps ink
  to its colour and white to `cut` (the surface behind). The mascot files had their `.pd-m-*` CSS
  colours inlined (flutter_svg ignores external CSS); re-inline when syncing new mascot files.
- `assets/map_icons` are Maki icons (CC0, github.com/mapbox/maki `icons/`), not from claude.ai:
  the basemap's landmark glyphs, drawn by `PoiMark` (`mapIconPicture`) as a `color.map.poi.*` disc.

## Rules

- Never uppercase UI strings. FiraGO 400–900 (OFL, `fonts/OFL.txt`) everywhere; every type role
  carries tabular figures.
- Tier → colour + icon: perfect yellow star, great aqua check-circle, close orange target,
  miss red reroute. Map roles: yellow = truth, cobalt = you, ink = measurement.
- `StreetPlate`: starts at `title.lg`, shrinks 2 dp steps until it fits two lines, floor
  `size.plate.name-floor` (16), then wraps — never truncates; its sub-line keeps to
  two lines (a turn card: where to and the question). `RevealSheet` and `IntroSheet` are kept
  short (32 dp badge, `title.lg` label, 12 dp padding) so the map keeps its room (2026-11-17, see
  `docs/TODO.md`).
- The turn card draws on the real map (the app's `PindoroMap`, heading-up), not a painted junction
  map: `ExitButton`, `CarMarker` and `LandmarkBadge` sit on it (2026-11-17, see `docs/TODO.md`).
- `PindoroButton` and `SearchField` are 48 dp (`size.button.md`), not the design's 56: the app
  felt too big (2026-11-16, see `docs/TODO.md`). The drive's stopped bar is the exception:
  `PindoroButton(large: true)` is 56 dp, `iconOnly` a square icon button.

## Tests

`flutter test` from this package. Goldens live in `test/goldens/` and are **Linux-only** (glyph
rasterisation differs per OS): they are skipped elsewhere and compared on Linux CI with a 1.5 %
tolerance for Flutter stable drift (`test/flutter_test_config.dart`, which also loads the real
fonts). After an intended visual change run `just goldens` (regenerates them in a Linux Flutter
container) and commit the PNGs.
