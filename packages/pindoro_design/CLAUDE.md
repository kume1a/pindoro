# pindoro_design

Flutter design system: generated tokens, `buildPindoroTheme`, `PindoroTheme` extension and the
Signpost widgets: `PindoroButton`, `StreetPlate`, `FeedbackBadge`, surfaces (`LipBox`,
`ListGroup`, `ListRow`, `StatTile`), the bottom navigation (`PindoroNavBar`), controls (`SegmentedControl`, `PindoroToggle`, `PindoroIconButton`,
`LaneLoader`), graphics (`PindoroIcon`, `Pindo`, `Wordmark`, `PinMark` incl. the road trip's `PinMark.endpoint`,
`CarMark`, `glyphPng` for map images) and the round
components (`QuestionBar`, `Pill`, `MapControl`, `RevealSheet`, `ResultRow`, `RewardTotal`,
`TierTally`, `CoachBubble`), the lesson path (`PathStop`, `Signpost` with its Unit guide book button, `LessonRoad`, the loading `Skeleton`) and lesson
components (`PlateChoice`, `FeedbackBar`), the league (`LeagueHeader`, `LeagueRow`,
`ZoneDivider`), badges (`BadgeShield`, `BadgeTile`; fields `color.badge.*` in `app.json`), setup components (`SearchField`, `CitySwitcher`, `PindoroChip`,
`DifficultyCard`, `DistrictMiniMap`) and motion (`PindoroPageTransitions`, `CountUp`, `PopIn`,
`RiseIn`, `Celebration`, `Wiggle`, `FadeIndexedStack`; all calm down under reduce motion). Widgets take their text
as parameters; strings live in the app.

## Tokens

- `tokens/tokens.json` is the claude.ai design system's file, copied verbatim (never edit it here;
  change it on claude.ai and copy it again). `tokens/app.json` holds app-only tokens in the same
  format; duplicates of a design-system token fail the generator. Intent lives in
  `docs/design/*.md`.
- `tool/generate_tokens.dart` writes `lib/src/generated/pindoro_tokens.dart`: `PindoroPalette`
  (primitives), `PindoroColors.light` / `.dark` (semantic + component colours, aliases resolved),
  `PindoroSpace.s4`, `PindoroRadius.lg`, `PindoroElevation.e2`, `PindoroSize`, `PindoroStroke`,
  `PindoroMotion`, `PindoroOpacity`, `PindoroShadow`, `PindoroCamera` and `PindoroType` roles.
  **Never hand-edit generated code** — commit the token JSON and run `just gen`; the generated
  Dart is not committed (`just setup` and CI generate it).
- No literal colours, radii, spacing or durations in widgets. Theme-dependent colours come from
  `PindoroTheme.of(context).colors`, never from `PindoroPalette` directly.

## Assets

- `assets/icons` (62), `assets/logos`, `assets/mascot` come from the claude.ai design system's
  asset groups. Icons are drawn in asphalt ink (#1B2133) with white details; `PindoroIcon` maps ink
  to its colour and white to `cut` (the surface behind). The mascot files had their `.pd-m-*` CSS
  colours inlined (flutter_svg ignores external CSS); re-inline when syncing new mascot files.

## Rules

- Never uppercase UI strings. FiraGO 400–900 (OFL, `fonts/OFL.txt`) everywhere; every type role
  carries tabular figures.
- Tier → colour + icon: perfect yellow star, great aqua check-circle, close orange target,
  miss red reroute. Map roles: yellow = truth, cobalt = you, ink = measurement.
- `StreetPlate`: starts at `headline.md`, shrinks 2 dp steps until it fits two lines, floor
  `size.plate.name-min` (20), then wraps — never truncates.

## Tests

`flutter test` from this package. Goldens live in `test/goldens/` and are **Linux-only** (glyph
rasterisation differs per OS): they are skipped elsewhere and compared on Linux CI with a 1.5 %
tolerance for Flutter stable drift (`test/flutter_test_config.dart`, which also loads the real
fonts). After an intended visual change run `just goldens` (regenerates them in a Linux Flutter
container) and commit the PNGs.
