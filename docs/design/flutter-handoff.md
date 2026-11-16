# Flutter handoff

How the tokens become a Material 3 theme. Two layers: the standard `ThemeData` (ColorScheme, TextTheme, component themes) carries everything Material already has a slot for; one `ThemeExtension`, `PindoroTheme`, carries the game-specific parts (feedback tiers, memory and charts, streak, map overlays, the 3D button, motion).

## 1. Tokens → Dart

`handoff/pindoro_tokens.dart` is generated from `tokens.json` and contains:

- `PindoroPalette`: primitives (`PindoroPalette.cobalt500`).
- `PindoroColors.light` / `.dark`: every semantic, game and component colour (dot names become camelCase: `color.feedback.great.fill` → `feedbackGreatFill`), with a `lerp` for theme animation.
- `PindoroSpace`, `PindoroRadius`, `PindoroStroke`, `PindoroElevation` (lip heights), `PindoroSize`.
- `PindoroMotion`: `Duration`s, `Cubic` curves and `SpringDescription`s.
- `PindoroType`: one `TextStyle` per role; numeric roles include `FontFeature.tabularFigures()`.

Regenerate it whenever tokens change; never edit it by hand.

## 2. Fonts

```yaml
# pubspec.yaml
flutter:
  fonts:
    - family: FiraGO
      fonts:
        - { asset: assets/fonts/FiraGO-Regular.ttf, weight: 400 }
        - { asset: assets/fonts/FiraGO-Medium.ttf, weight: 500 }
        - { asset: assets/fonts/FiraGO-SemiBold.ttf, weight: 600 }
        - { asset: assets/fonts/FiraGO-Bold.ttf, weight: 700 }
        - { asset: assets/fonts/FiraGO-ExtraBold.ttf, weight: 800 }
        - { asset: assets/fonts/FiraGO-Heavy.ttf, weight: 900 }
```

- Ship FiraGO as TTF/OTF in the app (the `.woff2` files in this system's `fonts/` are for the web previews; the same OFL family is available as desktop/mobile formats from the FiraGO project). Include `FiraGO-OFL.txt` in the app's licences (`LicenseRegistry`).
- Set `fontFamily: 'FiraGO'` and `fontFamilyFallback: ['Noto Sans']` on the `TextTheme`.
- Add `Locale('en')` (the template and default) and every translated locale to `supportedLocales` with `flutter_localizations`.
- **Never call `toUpperCase()`** on UI strings (some scripts' capital forms aren't in FiraGO). Lint for it.
- Numeric text: use `PindoroType.numeric*` (tabular figures) for counts, distances, City memory, timers.
- Test text scaling with `MediaQuery(data: …copyWith(textScaler: TextScaler.linear(2.0)))`; don't clamp below 2.0.

## 3. ColorScheme

| ColorScheme slot | Token |
| --- | --- |
| `primary` / `onPrimary` | `color.primary.base` / `color.primary.on` |
| `primaryContainer` / `onPrimaryContainer` | `color.primary.soft` / `color.primary.text` |
| `secondary` / `onSecondary` | `color.reward.base` / `color.reward.on` |
| `secondaryContainer` / `onSecondaryContainer` | `color.reward.soft` / `color.reward.text` |
| `tertiary` / `onTertiary` | `color.success.base` / `color.success.on` |
| `tertiaryContainer` / `onTertiaryContainer` | `color.success.soft` / `color.success.text` |
| `error` / `onError` | `color.error.base` / `color.error.on` |
| `errorContainer` / `onErrorContainer` | `color.error.soft` / `color.error.text` |
| `surface` / `onSurface` | `color.surface.base` / `color.text.primary` |
| `onSurfaceVariant` | `color.text.secondary` |
| `surfaceContainerLowest` / `Low` | `color.surface.raised` |
| `surfaceContainer` | `color.surface.overlay` |
| `surfaceContainerHigh` / `Highest` | `color.surface.sunken` |
| `outline` / `outlineVariant` | `color.line.strong` / `color.line.base` |
| `inverseSurface` / `onInverseSurface` | `color.surface.inverse` / `color.text.inverse` |
| `inversePrimary` | `color.cobalt.300` |
| `scrim` | `color.scrim` |
| `surfaceTint` | `Colors.transparent` (no M3 tonal tint; depth is the lip) |

```dart
ColorScheme pindoroScheme(PindoroColors c, Brightness b) => ColorScheme(
  brightness: b,
  primary: c.primaryBase, onPrimary: c.primaryOn,
  primaryContainer: c.primarySoft, onPrimaryContainer: c.primaryText,
  secondary: c.rewardBase, onSecondary: c.rewardOn,
  secondaryContainer: c.rewardSoft, onSecondaryContainer: c.rewardText,
  tertiary: c.successBase, onTertiary: c.successOn,
  tertiaryContainer: c.successSoft, onTertiaryContainer: c.successText,
  error: c.errorBase, onError: c.errorOn,
  errorContainer: c.errorSoft, onErrorContainer: c.errorText,
  surface: c.surfaceBase, onSurface: c.textPrimary, onSurfaceVariant: c.textSecondary,
  surfaceContainerLowest: c.surfaceRaised, surfaceContainerLow: c.surfaceRaised,
  surfaceContainer: c.surfaceOverlay,
  surfaceContainerHigh: c.surfaceSunken, surfaceContainerHighest: c.surfaceSunken,
  outline: c.lineStrong, outlineVariant: c.lineBase,
  inverseSurface: c.surfaceInverse, onInverseSurface: c.textInverse,
  inversePrimary: PindoroPalette.cobalt300,
  scrim: c.scrim, shadow: PindoroPalette.asphalt975, surfaceTint: const Color(0x00000000),
);
```

## 4. TextTheme

| TextTheme | Token role |
| --- | --- |
| `displayLarge` / `displayMedium` | `display.lg` / `display.md` |
| `displaySmall`, `headlineLarge` | `headline.lg` |
| `headlineMedium` / `headlineSmall` | `headline.md` / `headline.sm` |
| `titleLarge` / `titleMedium` / `titleSmall` | `title.lg` / `title.md` / `title.sm` |
| `bodyLarge` / `bodyMedium` / `bodySmall` | `body.lg` / `body.md` / `body.sm` |
| `labelLarge` / `labelMedium` / `labelSmall` | `label.lg` / `label.md` / `label.sm` |
| (extension) | `label.button`, `numeric.xl/lg/md/sm` |

```dart
TextTheme pindoroText(Color ink) => const TextTheme(
  displayLarge: PindoroType.displayLg, displayMedium: PindoroType.displayMd,
  displaySmall: PindoroType.headlineLg, headlineLarge: PindoroType.headlineLg,
  headlineMedium: PindoroType.headlineMd, headlineSmall: PindoroType.headlineSm,
  titleLarge: PindoroType.titleLg, titleMedium: PindoroType.titleMd, titleSmall: PindoroType.titleSm,
  bodyLarge: PindoroType.bodyLg, bodyMedium: PindoroType.bodyMd, bodySmall: PindoroType.bodySm,
  labelLarge: PindoroType.labelLg, labelMedium: PindoroType.labelMd, labelSmall: PindoroType.labelSm,
).apply(bodyColor: ink, displayColor: ink);
```

## 5. Component themes

| Component | Theme | Key values |
| --- | --- | --- |
| Secondary / tertiary buttons | `OutlinedButtonThemeData`, `TextButtonThemeData` | height 48–56, `radius.lg`, 2 dp `color.button.secondary.border`, `label.button` |
| Primary / reward / destructive / tier buttons | custom `PindoroButton` (below) | M3 buttons can't do the lip-and-drop; use the widget |
| Icon buttons | `IconButtonThemeData` | 48 dp, `radius.md`, secondary colours |
| Chips | `ChipThemeData` | 40 dp, `StadiumBorder`, 2 dp border, `color.chip.*` |
| Segmented control | `SegmentedButtonThemeData` | sunken track, raised selected segment, `color.primary.text` |
| Switch | `SwitchThemeData` | track `color.toggle.on/off`, thumb `color.toggle.thumb` |
| Slider | `SliderThemeData` | track height 10, thumb radius 16, `color.slider.*`, value indicator `color.surface.inverse` |
| Progress | `ProgressIndicatorThemeData` | `color.progress.done` on `color.progress.track`, `linearMinHeight: 18` |
| Cards | `CardThemeData` | `elevation: 0`, `radius.xl`, side 2 dp `color.line.base`; lip drawn by a wrapper |
| List rows | `ListTileThemeData` | min height 64, `title.md`, `body.sm` subtitle |
| Bottom sheet | `BottomSheetThemeData` | `color.surface.overlay`, top `radius.2xl`, drag handle 36 × 5 `color.line.strong`, `elevation: 0` |
| Dialog | `DialogThemeData` | `color.surface.overlay`, `radius.xl`, `elevation: 0` |
| Toast | `SnackBarThemeData` | floating, `color.toast.bg/text`, `radius.lg` |
| Bottom nav | `NavigationBarThemeData` | `color.surface.raised`, indicator `color.tab.active.bg`, icons `color.tab.*`, height 84 |
| Focus | `ThemeData.focusColor` + per-widget `FocusableActionDetector` | solid 3 dp `color.focus.ring` drawn 2 dp outside |
| Search field (v1) | `InputDecorationTheme` | filled `color.input.bg`, 2 dp `color.input.border` (focused `color.input.border-focus`), `radius.lg`, 56 dp, `body.lg`, hint `color.input.placeholder`; lip drawn by the card wrapper |
| Coach mark (v1) | `TooltipThemeData` is not enough: a positioned widget | `color.coach.bg/text/lip`, `radius.lg`, `title.sm` + `body.sm`, 9 dp arrow |

## 6. ThemeExtension: what goes in `PindoroTheme`

Everything Material has no slot for:

- **Feedback tiers:** `TierColors perfect, great, close, miss` (each `fill, lip, on, bg, ink`) + icon per tier.
- **Progress, locked and roads:** `progressTrack` (empty tracks and bars), `lockedFill, lockedLip, lockedIcon` (locked badges, the not-yet-today streak flame), `roadBase, roadLane` (illustrations and the cover).
- **Streak:** `streakFlame, streakCore, streakText, streakDayDone, streakDayEmpty, streakFreezeFill, streakFreezeInk`.
- **Street plate:** `bg, lip, rule, text, subtext`.
- **Map overlays:** `answerLine, answerCasing, playerPin, playerPinLip, playerHalo, playerRoute, measureLine, measureLabel, measureLabelText, areaFill, areaStroke`, district `progress/mastered` fill + stroke (the `locked` pair has no v3 use), `routeArrow`; v1 adds `mapAreaCenter, mapAreaLabelBg, mapAreaLabelLip, mapAreaLabelText, mapReticle, mapAttributionBg, mapAttributionText` and, for district presets on the area picker, `mapRegionOutline, mapRegionLabelBg, mapRegionLabelText`.
- **v1 components:** `inputBg, inputBorder, inputBorderFocus, inputText, inputPlaceholder, inputIcon`, `coachBg, coachText, coachLip`, and `PindoroSize.plateNameMin` (20) for the street-plate fit. Per-screen notes and the release plan: the MVP screens section.
- **v3 memory and charts:** `memoryMastered, memorySolid, memoryKnown, memorySeen` (the rest of the bar is `progressTrack`), `chartLine, chartArea, chartBar, chartBarToday`.
- **3D button:** lip heights (`PindoroElevation.e2` default, `e3` hero), radius, press `Duration` + `Curve`, release `SpringDescription`.
- **Motion:** celebration durations (`celebrateSmall/Medium/Big`), `pinDrop`, `countUp`, springs.

```dart
@immutable
class PindoroTheme extends ThemeExtension<PindoroTheme> {
  const PindoroTheme({required this.colors, this.reduceMotion = false});
  final PindoroColors colors;          // all game + component colours (generated)
  final bool reduceMotion;             // from MediaQuery.disableAnimations

  TierColors tier(Tier t) => switch (t) {
    Tier.perfect => TierColors(colors.feedbackPerfectFill, colors.feedbackPerfectLip, colors.feedbackPerfectOn, colors.feedbackPerfectBg, colors.feedbackPerfectInk),
    Tier.great   => TierColors(colors.feedbackGreatFill, colors.feedbackGreatLip, colors.feedbackGreatOn, colors.feedbackGreatBg, colors.feedbackGreatInk),
    Tier.close   => TierColors(colors.feedbackCloseFill, colors.feedbackCloseLip, colors.feedbackCloseOn, colors.feedbackCloseBg, colors.feedbackCloseInk),
    Tier.miss    => TierColors(colors.feedbackMissFill, colors.feedbackMissLip, colors.feedbackMissOn, colors.feedbackMissBg, colors.feedbackMissInk),
  };
  Duration d(Duration full) => reduceMotion ? const Duration(milliseconds: 150) : full;

  @override
  PindoroTheme copyWith({PindoroColors? colors, bool? reduceMotion}) =>
      PindoroTheme(colors: colors ?? this.colors, reduceMotion: reduceMotion ?? this.reduceMotion);
  @override
  PindoroTheme lerp(PindoroTheme? other, double t) =>
      other == null ? this : PindoroTheme(colors: PindoroColors.lerp(colors, other.colors, t), reduceMotion: t < .5 ? reduceMotion : other.reduceMotion);
}

enum Tier { perfect, great, close, miss }
class TierColors { const TierColors(this.fill, this.lip, this.on, this.bg, this.ink); final Color fill, lip, on, bg, ink; }

ThemeData pindoroTheme(Brightness b) {
  final c = b == Brightness.light ? PindoroColors.light : PindoroColors.dark;
  return ThemeData(
    useMaterial3: true,
    colorScheme: pindoroScheme(c, b),
    textTheme: pindoroText(c.textPrimary),
    scaffoldBackgroundColor: c.surfaceBase,
    splashFactory: NoSplash.splashFactory,   // feedback is the press/lip, not ink ripples
    extensions: [PindoroTheme(colors: c)],
  );
}
// usage: final p = Theme.of(context).extension<PindoroTheme>()!;
```

## 7. The 3D button

```dart
class PindoroButton extends StatefulWidget {
  const PindoroButton({super.key, required this.label, required this.onPressed,
    this.face, this.lip, this.ink, this.loading = false, this.lipHeight = PindoroElevation.e2});
  final String label; final VoidCallback? onPressed; final Color? face, lip, ink;
  final bool loading; final double lipHeight;
  @override State<PindoroButton> createState() => _PindoroButtonState();
}
class _PindoroButtonState extends State<PindoroButton> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<PindoroTheme>()!.colors;
    final enabled = widget.onPressed != null && !widget.loading;
    final face = enabled ? (widget.face ?? c.buttonPrimaryBg) : c.buttonDisabledBg;
    final lip  = enabled ? (widget.lip ?? c.buttonPrimaryLip) : c.buttonDisabledLip;
    final ink  = enabled ? (widget.ink ?? c.buttonPrimaryText) : c.buttonDisabledText;
    final drop = _down ? widget.lipHeight : 0.0;
    return Semantics(button: true, enabled: enabled, label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) { setState(() => _down = true); HapticFeedback.selectionClick(); } : null,
        onTapUp:   enabled ? (_) { setState(() => _down = false); widget.onPressed!(); } : null,
        onTapCancel: () => setState(() => _down = false),
        child: SizedBox(height: PindoroSize.buttonLg + widget.lipHeight,
          child: Stack(children: [
            Positioned.fill(top: widget.lipHeight, child: DecoratedBox(decoration: BoxDecoration(color: lip, borderRadius: BorderRadius.circular(PindoroRadius.lg)))),
            AnimatedPositioned(
              duration: _down ? PindoroMotion.durationInstant : PindoroMotion.durationQuick,
              curve: _down ? PindoroMotion.easePress : PindoroMotion.easeOvershoot,
              left: 0, right: 0, top: drop, height: PindoroSize.buttonLg,
              child: DecoratedBox(
                decoration: BoxDecoration(color: face, borderRadius: BorderRadius.circular(PindoroRadius.lg)),
                child: Center(child: widget.loading
                  ? LaneLoader(color: ink)                         // three dashes driving left to right
                  : Text(widget.label, style: PindoroType.labelButton.copyWith(color: ink))),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
```

Tier buttons pass `face/lip/ink` from `tier(t)`; secondary buttons use a 2 dp border and `color.button.secondary.*`.

## 8. Motion in Flutter

- Durations and curves: `PindoroMotion.durationBase` + `PindoroMotion.easeDecelerate` for entering, `durationFast` + `easeAccelerate` for leaving, `easeOvershoot` for pops.
- Springs: drive an `AnimationController` with `SpringSimulation(PindoroMotion.springBouncy, 0, 1, velocity)` for the pin drop, badge pop and next-review chip; `springSnappy` for button release and toggles; `springGentle` for drag-follow and map recentre.
- Pin drop: lift (−24 dp, 0.9 scale) → fall → squash (`Transform.scale(scaleX: 1.08, scaleY: 0.86, alignment: Alignment.bottomCenter)`) → spring back; ground shadow scales 0.4 → 1.
- Celebrations: build confetti with a lightweight particle painter (lane dashes and stars) or a Rive file; Pindo's expressions as one Rive state machine (`happy`, `cheering`, `thinking`, `encouraging`, `sleepy`, `proud`).
- Reduce motion: `final calm = MediaQuery.of(context).disableAnimations;` swap every animation for a 150 ms fade or an instant change; skip confetti entirely.

## 9. Haptics per event

| Event | Call |
| --- | --- |
| Tap, step, segment change, slider step | `HapticFeedback.selectionClick()` |
| Pin drop, Close | `HapticFeedback.lightImpact()` |
| Confirm, Great, streak +1, badge unlock | `HapticFeedback.mediumImpact()` |
| Perfect, streak milestone | `heavyImpact()`, then `mediumImpact()` after 90 ms |
| Miss | `selectionClick()` twice, 60 ms apart |
| District Mastered | `HapticFeedback.heavyImpact()` |
| Speech token resolved (v3) | `selectionClick()`, no sound |
| Drive start / end (v3) | `mediumImpact()` |
| Session done (v3) | `heavyImpact()`, then `mediumImpact()` after 90 ms |
| Mix-up (v3) | as Miss: `selectionClick()` twice, 60 ms apart |

Wrap calls in a `Haptics` service that checks the in-app Haptics toggle; do the same with a `Sfx` service for the Sound toggle (preload all sounds at launch, ambient audio session on iOS).

## 10. Map

Use `flutter_map` with CARTO `light_nolabels` / `dark_nolabels` raster tiles (follow CARTO's attribution and usage terms). Draw overlays as `PolylineLayer` (answer: 12 dp casing + 8 dp yellow; player route dashed), `MarkerLayer` (pins as widgets so they share `PindoroButton`-style lips and animate), `CircleLayer` (radius) and `PolygonLayer` (districts). Take every colour from `PindoroTheme.colors.map*`.

## 11. App icon and splash

- `flutter_launcher_icons`: iOS from `ios-light-1024.png` (+ dark and tinted variants in the asset catalogue), Android adaptive from `android-foreground.svg` / `android-background.svg` (export as PNG or vector drawable) and `android-monochrome.svg` for themed icons.
- `flutter_native_splash`: background `color.cobalt.500` (dark `color.asphalt.950`), centred pin; the drop intro runs on the first Flutter frame (see Splash).

## 12. v3 components

Widgets added for v3 (Learn the whole city). Colours come from `PindoroTheme.colors` (generated names, e.g. `color.map.region.outline` → `mapRegionOutline`); sizes, radii and motion from `PindoroSize`, `PindoroRadius`, `PindoroMotion`. Opacity tokens are not generated into `pindoro_tokens.dart`; use the value given here.

### NextReviewChip

- **Inputs:** `int? days` (null = back in this session), `bool animate` (false when reduce motion is on or the sheet is rebuilt).
- **Look:** icon `calendar` when `days != null`, else `retry`; label "Next review in {days, plural, one {# day} other {# days}}" or "Back in this session"; 40 dp tall, `PindoroRadius.md`, `surfaceRaised` with a 2 dp `lineBase` lip (`PindoroElevation.e1`), 24 dp icon (`PindoroSize.iconMd`) in `textPrimary`, label 900 17/22 with `FontFeature.tabularFigures()`.
- **Motion:** scale 0.4 → 1 + fade on `PindoroMotion.springBouncy`, started after the tier badge lands, inside `PindoroMotion.celebrateSmall`. No sound, no haptic.
- **Tokens:** `surfaceRaised`, `lineBase`, `textPrimary`, `radius.md`, `elevation.1`, `size.icon.md`, `motion.spring.bouncy`, `motion.celebrate.small`.

### RevealSheet (v3 changes)

- **Inputs:** `RevealResult result` (`tier`, `distanceMeters`, `int? nextReviewDays`, `MixUp? mixUp`, `List<String> chips`), `String? hint`, `VoidCallback onNext`. `MixUp` holds `placedStreetName`, `contrastLine` and `pairLabel` ("4th ↔ 5th"). `Grader.grade(pin, street, rtMs)` returns `{tier, rating, snapStreetId}`; a confusable `snapStreetId` makes the result a Mix-up.
- **Changes:** `NextReviewChip` sits at the end of the header row (`Wrap`, so it drops under the title when narrow). Mix-up uses `tier(Tier.miss)` colours, the `reroute` icon, the title "Mix-up" and **Got it**; chip row "Pair saved: {pairLabel}".
- **Map on Mix-up:** hit street as a player route (`PolylineLayer`: 9 dp `mapPlayerHalo` under 5 dp `mapPlayerRoute`, dash 8 / 7) with a cobalt name chip; true street as answer paint (12 dp `mapAnswerCasing` + 8 dp `mapAnswerLine`). Animate the hit street's paint first, then the true street, `PindoroMotion.durationBase` each; Miss sound and Miss haptic as the badge lands.
- **Tokens:** `feedback.miss.*`, `map.player.halo`, `map.player.route`, `map.answer.line`, `map.answer.casing`, `map.area.label.bg` / `.text` / `.lip` (cobalt chip), `motion.duration.base`.

### IntroSheet

- **Inputs:** `StreetIntro intro` (`name`, `otherScriptName`, `String? district` when the name is shared, `where`, `facts`, `String? etymology`, `Family? family`), `int index`, `int count` ("New street · 3 of 10"), `bool canSpeak`, `VoidCallback onHear`, `VoidCallback onGotIt`. `Family` holds `parentName`, `laneCount`, `deadEndCount`.
- **Build:** `StreetPlate` (ask row with `signpost`, up to two sub-lines) over the map, then a non-dismissible sheet: title "Where it is" (`PindoroType.titleMd`), sentence (`bodyMd`, `textSecondary`), facts (`labelMd`, `textSecondary`, tabular figures), optional etymology (`bodySm`), optional family `StatChip` with the `road` icon (wraps to two lines when narrow), then a `Row` of a 56 dp secondary icon button (`sound-on`) and an expanded primary `PindoroButton` "Got it". Hide the speak button when `canSpeak` is false.
- **Text-to-speech:** `flutter_tts` with the street's language tag; `canSpeak` comes from the installed voices for that tag.
- **Motion:** camera flies to the street (`durationSlow`, `easeStandard`), paint draws (`durationBase`), sheet rises (`durationBase`, `easeDecelerate`).
- **Tokens:** `surfaceOverlay`, `textPrimary`, `textSecondary`, `streetCard*`, `button.secondary.*`, `button.primary.*`, `radius.2xl`, `space.1` – `space.5`, `size.button.lg`, `size.plate.name-min`.

### MapLabels (known streets)

- **Inputs:** `Set<StreetId> knownStreets` (Known or better), `StreetId? answerStreet` (never labelled), `StreetId? hitStreet` (Mix-up only: the one cobalt chip), the visible street geometries with short names.
- **Build:** a `PolylineLayer` of 6 dp traces in `mapRegionOutline` at opacity 0.55 (`opacity.street-trace`), drawn under the answer paint, plus a `MarkerLayer` of name chips: 24 dp, `PindoroRadius.full`, `mapRegionLabelBg` / `mapRegionLabelText`, `labelMd`, a 2 dp `lineBase` lip and `shadow.float`. The hit street's chip uses `mapAreaLabelBg` / `mapAreaLabelText` / `mapAreaLabelLip`. Shown on the intro and on reveals only; chips never cover the answer street or the pin.
- **Tokens:** `map.region.outline`, `opacity.street-trace`, `map.region.label.bg` / `.text`, `map.area.label.bg` / `.text` / `.lip`, `line.base`, `shadow.float`, `radius.full`.

### SessionTopBar

- **Inputs:** `int plannedItems`, `int answeredItems`, `Set<int> forgottenBlocks` (0–11), `Duration timeLeft`, `VoidCallback onLeave`.
- **Build:** `Row`: 48 dp icon button (`close`, "Leave session"), `SessionBar` (12 equal blocks, 14 dp tall, `space.1` gaps; block i covers one twelfth of `plannedItems`; current `progressCurrent`; finished `progressDone` with a 3 dp `progressDoneLip`, or `feedbackMissFill` with `feedbackMissLip` when the block is in `forgottenBlocks`; upcoming `progressTodo` with a 2 dp `progressTodoBorder`), then the time-left pill (`timer` icon in `primaryText`, "{minutes} min", tabular figures, floating shadow). Semantics: "Today’s session, 5 of 12" and "About 14 minutes left".
- **Tokens:** `progress.*`, `feedback.miss.fill`, `feedback.miss.lip`, `primary.text`, `surface.raised`, `line.base`, `shadow.float`, `radius.xs`, `radius.full`, `space.1`, `motion.duration.fast`.

### MemoryBar

- **Inputs:** `int mastered, solid, known, seen, total`, `MemoryBarSize size` (`card` 14 dp, `compact` 6 dp), `bool showLegend` (card only), `String semanticsPrefix` ("City memory", or the district or neighbourhood name), `bool animate`.
- **Build:** a `ClipRRect` (`PindoroRadius.xs`) around a `Row` on `progressTrack`; each non-empty state is an `Expanded(flex: count)` box in its colour with 2 dp (`PindoroStroke.base`) gaps; the remainder `Expanded(flex: total − sum)` stays empty so the track shows. One `Semantics(label: "City memory: 412 mastered, 630 solid, 220 known, 90 seen of 3 282", image: true)` around the bar. Legend: an `ExcludeSemantics` `Wrap` (spacing 12, run spacing 8) of 12 dp round swatches + `labelMd` name + bold tabular count. Grow: an `AnimationController` over `PindoroMotion.durationSlow` with `easeStandard` scaling each segment's width from 0 (`Align(widthFactor: t)`), only on a card's first show; skip when `disableAnimations`.
- **Tokens:** `color.memory.mastered`, `.solid`, `.known`, `.seen`, `color.progress.track`, `radius.xs`, `stroke.base`, `space.1` – `space.3`, `label.md`, `motion.duration.slow`, `motion.ease.standard`.

### MemoryChart

- **Inputs:** `List<int> weekly` (up to 11 values, oldest first), `String startLabel` ("Sep 8"), `String endLabel` ("Today"), `String semanticsLabel`, `bool animate`.
- **Build:** a `CustomPainter`, card content width × 132 dp, following the painter spec in the Memory chart component: plot 2 dp … `width − 5` × 0 … 110 dp; `top = ceil(max × 1.05 / step) × step` with `step = 10^(floor(log10(max)) − 1)` (minimum 10); `y = 110 × (1 − v / top)`; baseline 2 dp `lineBase`, area `chartArea`, line 3 dp `chartLine` (round caps and joins), 5 dp dot, labels in `labelMd` / `textSecondary` at baseline 128. Draw-in: animate the line with `PathMetric.extractPath(0, length × t)` over 2 × `durationSlow`, then fade the area (`durationBase`) and pop the dot (`springBouncy`). `Semantics(image: true, label: semanticsLabel)`.
- **Tokens:** `color.chart.line`, `color.chart.area`, `color.line.base`, `color.text.secondary`, `label.md`, `motion.duration.slow`, `motion.duration.base`, `motion.spring.bouncy`.

### ForecastBars

- **Inputs:** `List<int> dueByDay` (14 values, today first), `String endDateLabel` ("Nov 29"), `bool animate`.
- **Build:** header `Row` (`titleSm` "Reviews, next 14 days" + `labelMd` / `textSecondary` "about {round(sum / 14)} a day"), 8 dp gap, a `CustomPainter` 56 dp tall (painter spec in the Forecast bars component): bar width `(width − 52) / 14`, 4 dp gaps, height `56 × count / busiest`, `RRect` with `PindoroRadius.xs` (clamped to half the width); bar 0 in `chartBarToday`, the rest in `chartBar`; then 8 dp and a label `Row` ("Today" left, the end date right, `labelMd`, `textSecondary`). Grow: each bar scales up from the bottom over `durationBase` with `easeDecelerate`, bar i delayed `i × stagger`. The card is one `Semantics` group: "Reviews, next 14 days, about 27 a day. Today 34."
- **Tokens:** `color.chart.bar`, `color.chart.bar-today`, `color.text.secondary`, `radius.xs`, `space.1`, `space.2`, `title.sm`, `label.md`, `motion.duration.base`, `motion.ease.decelerate`, `motion.stagger`.

### CityMemoryCard (pattern)

- **Inputs:** `double cityMemory` (Σ recall, shown rounded), `int total` (core streets), `int? changeSinceYesterday`, `MemoryCounts counts`, `CityMemoryLayout layout` (`today`, `progress`, `sessionDone`), `List<int>? weekly` (progress), `int? sessionStartValue` (session done).
- **Build:** no new widget: a `Card` from the card theme (section 5) with its lip wrapper, padding 16 and 12 between rows. Today: label (`labelMd`, `textSecondary`), the number in `headlineLg` with tabular figures and "of {total} streets" (`bodySm`) on one baseline, the change on the right (`labelMd`, `successText`; a `Wrap` so it drops under the number when long), `MemoryBar(size: card, showLegend: true)`, optional explanation (`bodySm`). Progress: label "City memory · streets you’d place today", "of {total} · {percent} %", `MemoryChart`, `MemoryBar(showLegend: true)`. Session done: padding 12 × 16, "City memory" (`titleSm`) and "{start} → {now}" (`numericSm`) counting up over `PindoroMotion.countUp`, then `MemoryBar(size: card)`.
- **Tokens:** `surface.raised`, `line.base`, `text.primary`, `text.secondary`, `success.text`, `headline.lg`, `title.sm`, `numeric.sm`, `body.sm`, `label.md`, `radius.xl`, `space.2` – `space.4`, `motion.count-up`.

### BearingDial

- **Inputs:** `double playerBearing` (degrees clockwise from north), `double? trueBearing` (null before Check), `ValueChanged<double> onChanged`, `bool enabled` (false after Check), `String caption`.
- **Build:** a `CustomPainter` at 280 dp (scaled by `size.shortestSide / 280`) inside a `GestureDetector` for pan and `Semantics(slider: true)` with ±30° increase and decrease; the layer-by-layer painter spec is in the Bearing dial component. Caption below in `labelMd`, `textSecondary`. After Check the feedback bar (`.pd-feedback`, tier colours) carries the angle and the sound and haptic.
- **Tokens:** `color.surface.raised`, `color.line.base`, `color.text.secondary`, `color.text.primary`, `color.map.answer.line`, `color.map.answer.casing`, `color.map.player.route`, `color.map.measure.line`, `color.map.player.pin`, `title.sm`, `label.md`, `motion.duration.base`.

### ExitButton

- **Inputs:** `ExitDirection direction` (`left`, `straight`, `right`; `uTurn` comes with the drive icons), `bool selected`, `VoidCallback onTap`, `String semanticsLabel` ("Turn right").
- **Build:** a 56 dp circular `PindoroButton` variant (`radius.full`) with the secondary face, 2 dp border and 4 dp lip; selected swaps to `primaryBase` / `primaryLip` / `primaryOn`. 24 dp icon (`turn-left`, `straight`, `turn-right`) in `textSecondary` (unselected). `Positioned` on its arm about 112 dp from the junction centre. `Semantics(button: true, toggled: selected)`; tap haptic `selectionClick()`.
- **Tokens:** `color.button.secondary.*`, `color.primary.base`, `.lip`, `.on`, `color.text.secondary`, `size.button.lg`, `radius.full`, `elevation.2`, `motion.duration.instant`, `motion.ease.press`, `motion.spring.snappy`.

### LandmarkBadge

- **Inputs:** `String name`, `LandmarkKind kind` (icon; `fuel` → `fuel-station`), `bool personal`, `String semanticsLabel` ("Your landmark: Connect fuel station, south-east corner").
- **Build:** a 40 dp `DecoratedBox` (`surfaceRaised`, `PindoroRadius.md`, 2 dp `lineStrong` lip) with the 24 dp icon in `textPrimary`; the name chip (as MapLabels, white) centred 40 dp below. One `Semantics(image: true)` around both; exclude the chip's text from semantics.
- **Tokens:** `color.surface.raised`, `color.line.strong`, `color.text.primary`, `color.map.region.label.bg`, `.text`, `radius.md`, `radius.full`, `elevation.1`, `label.md`, `shadow.float`.

### JunctionMap

- **Inputs:** `JunctionGeometry geometry` (arms with polylines and road classes, buildings, parks, landmark footprint, approach edge, from the pack), `JunctionState state` (`choosing`, `right`, `wrong`), `ExitDirection? chosen`, `List<Offset>? correctExit`.
- **Build:** a heading-up `CustomPainter` (layer-by-layer spec in the Junction map component) under a `Stack` with `ExitButton`s (only while choosing), the `LandmarkBadge` and the car marker (32 dp `mapRouteArrow` disc, 20 dp `car` icon in `mapRouteLine`, 2 dp `mapPlayerHalo` ring). After Confirm: wrong choice then correct exit, `PindoroMotion.durationBase` each; the reveal sheet carries the tier sound and haptic.
- **Tokens:** `color.map.basemap.land`, `.building`, `.park`, `.casing`, `.road`, `color.map.route.line`, `.casing`, `.arrow`, `color.map.player.route`, `.halo`, `motion.duration.base`.

### TranscriptChips

- **Inputs:** `List<RecitalToken> tokens` (each `street`, `turn` or `landmark`, with `label`, `fullName`, `LandmarkKind?`, `bool isNew`), `String transcript`, `ValueChanged<RecitalToken> onFix`.
- **Build:** a card (padding 12 × 16, 12 between rows) with the label (`labelMd`, `textSecondary`), a `Wrap` (spacing 8, run spacing 8) of tokens, then the transcript (`bodySm`, `textSecondary`). Streets and landmarks: 32 dp selected chips (`chipSelectedBg`, `.Border`, `.Text`, `StadiumBorder`, 2 dp lip; landmark adds a 20 dp kind icon) inside a 48 dp tap target. Turn words: `labelMd` in `textSecondary` on `surfaceSunken`, padding 4 × 8, `StadiumBorder`. New tokens slide 16 dp up and fade in (`PindoroMotion.durationBase`, `easeDecelerate`, `stagger` between tokens resolved together) and call `HapticFeedback.selectionClick()`. Announce each new token with `SemanticsService.announce` (polite).
- **Tokens:** `color.chip.selected.*`, `color.surface.sunken`, `color.text.secondary`, `label.md`, `body.sm`, `radius.full`, `space.1` – `space.4`, `size.icon.sm`, `motion.duration.base`, `motion.ease.decelerate`, `motion.stagger`.

### SceneCard

- **Inputs:** `ImageProvider photo` (Mapillary or the player's own; `cached_network_image` with the offline pack), `String altText`, `String caption`, `String attribution` ("© Mapillary · CC BY-SA · {photographer}"), `Uri lookAround` (Google Maps at the photo's place).
- **Build:** a `ClipRRect` (`PindoroRadius.xl`) card on `surfaceRaised` with a 4 dp `lineBase` lip; the photo `Image` at full width × 260 dp with `BoxFit.cover` and `Semantics(image: true, label: altText)`; while loading, a shimmer box of the same size on `surfaceSunken`; then caption and attribution in `labelSm`, `textSecondary`, padding 8 × 12. Below the answer controls: a full-width tertiary button with the `external` icon, "Look around in Google Maps", opening `lookAround` with `url_launcher` (`LaunchMode.externalApplication`).
- **Tokens:** `color.surface.raised`, `color.surface.sunken`, `color.line.base`, `color.text.secondary`, `color.button.tertiary.text`, `radius.xl`, `elevation.2`, `label.sm`, `space.2`, `space.3`.

### Progress rows (ListRow variants)

- **Inputs:** `RowStatus status` (`district`, `done`, `now`, `next`), `String title`, `String subtitle` ("23 of 61 seen · learning now"), `MemoryCounts? counts` (shows the compact bar), `VoidCallback onTap`.
- **Build:** the list row (64 dp min, 40 dp `PindoroRadius.md` tile, `titleMd`, `bodySm` subtitle, chevron) with the tile by status: `district` / `now` the default tile (`primarySoft` + `primaryText`, icons `district` / `play`); `done` `primaryBase` + `primaryOn` with `check-circle`; `next` `surfaceSunken` + `textSecondary` with `lock`. With `counts`, a `MemoryBar(size: compact)` 4 dp under the subtitle, the full width of the text column. Merge semantics: "Bagebi, learning now. 0 mastered, 4 solid, 7 known, 12 seen of 61."
- **Tokens:** `color.primary.base`, `.on`, `.soft`, `.text`, `color.surface.sunken`, `color.text.secondary`, `color.memory.*`, `color.progress.track`, `radius.md`, `space.1`, `title.md`, `body.sm`.

### Home and work rows and picker

- **Rows:** list rows with the default tile and `home` or `briefcase`, title "Home" / "Work", subtitle "{neighbourhood} · learning starts here" / "· comes next", chevron. Today's first run uses one row: `home`, "Home and work", "Set them to start learning near you".
- **Picker:** the area selector (`AreaSelector`) in districts mode with `level: neighbourhood`, `singleSelect: true` and the mode switch hidden. Inputs: `Anchor anchor` (`home`, `work`), `List<Region> neighbourhoods`, `RegionId? selected`, `ValueChanged<RegionId> onSelect`, `VoidCallback onConfirm`. Sheet title "Home: {name}", single-choice chips (`Semantics(inMutuallyExclusiveGroup: true)`), "More" with search, **Set as home** / **Set as work** (disabled until a pick). Saves the anchor; the curriculum starts new streets in the home neighbourhood.
- **Tokens:** `color.map.area.fill`, `.stroke`, `color.map.area.label.*`, `color.map.region.outline`, `color.map.region.label.*`, `color.chip.*`, `color.primary.soft`, `.text`.

### Placement (pattern)

- **Question:** the normal session pin question with `PlacementController`; the plate's ask is "Placement · {n} of 88"; under **Confirm**, a full-width tertiary button "I don’t know this one" (`onSkip`: leave the street unseen, no penalty, load the next).
- **Result:** Pindo `proud` 120 dp, `headlineMd` "You know {n} streets already", `bodyMd` / `textSecondary` line, a 2-column `GridView` of 4 stat tiles (`road` Main roads, `district` Districts, `check-circle` In review, `home` Start in), **Start learning** pinned at the bottom. Tiles stagger in (`stagger`, `durationBase`).
- **Tokens:** `button.tertiary.text`, `button.primary.*`, `headline.md`, `body.md`, `text.secondary`, `surface.raised`, `line.base`, `radius.lg`, `motion.stagger`, `motion.duration.base`.

### Bottom nav

- **Build:** `StatefulShellRoute.indexedStack` with four branches and a Material 3 `NavigationBar` (theme in section 5). Destinations in this order: `road` Today, `map` Explore, `chart` Progress, `user` Me. Full-screen routes (session, placement, an Explore round, recital, drive) sit outside the shell, so the bar hides there.
- **Tokens:** `color.surface.raised`, `color.line.base`, `color.tab.active.bg`, `color.tab.active.icon`, `color.tab.inactive.icon`, `label.md`, `radius.md`, `size.tap.min`.

### Today card (pattern)

- **State:** from `TodayController` (`SchedulerService.dueCount(now)`, `planSession(budgetMin)`, `MemoryStats.cityMemory()`): **ready**, **catching up** when `dueCount × 12 s` exceeds the day's minutes (new streets 0, most overdue first), or **done** once today's session is finished.
- **Build:** a `Card` (card theme) with padding 16 and 12 between rows: a `Row` of Pindo (56 dp) and a `Column` with the title (`titleLg`) and subtitle (`bodySm`, `textSecondary`); a 3-column grid of `StatTile`s with 8 dp gaps; a full-width primary `PindoroButton` with the `play` icon ("Start" / "Catch up"). Ready and catching up draw the primary ring: a 3 dp (`PindoroStroke.thick`) inner border in `primaryBase` and the `elevation.2` lip in `primaryLip`. Done: no ring, no tiles; two secondary `PindoroButton`s, "Learn 5 more" and "Free play", as `Expanded` children of a `Row` (8 dp), switching to a `Column` when either label would overflow.
- **Info card** (catching up, under the City memory card): a `Card` with padding 12 × 16 and a top-aligned `Row`: the 40 dp list-row tile (`primarySoft`, `info` in `primaryText`) and `bodySm` in `textPrimary`.
- **Actions:** Start and Catch up push the session route; Learn 5 more starts a session of 5 new streets beyond the daily number; Free play switches to the Explore branch.
- **Tokens:** `color.surface.raised`, `color.line.base`, `color.primary.base`, `.lip`, `.soft`, `.text`, `color.text.primary`, `.secondary`, `stroke.thick`, `elevation.2`, `radius.xl`, `title.lg`, `body.sm`, `space.2` – `space.4`.

### Badge (v3)

- **Inputs:** `BadgeId id`, `BadgeState state` (`earned`, `locked`, `retired`), `bool isNew`, `int? progress`, `int? goal` ("1 292 of 1 500").
- **Build:** the shield (`CustomPainter`: rim `yellow400`, field per badge as tabled in Badge), the glyph as a white `PindoroIcon`. Locked: field `lockedFill`, rim `lockedLip`, `lock` glyph in `lockedIcon`, and a 6 dp bar on `progressTrack` filled `progressDone` when `goal` is set. Retired: the earned look plus a "Retired" pill on `surfaceSunken` with `textSecondary`. Filter out retired badges the player never earned before building the list.
- **Tokens:** `color.yellow.400`, the field primitives, `color.locked.*`, `color.progress.track`, `color.progress.done`, `color.surface.sunken`, `color.text.secondary`, `color.accent.*` (New pill), `label.sm`.
