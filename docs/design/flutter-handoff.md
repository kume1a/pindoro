# Flutter handoff

How the tokens become a Material 3 theme. Two layers: the standard `ThemeData` (ColorScheme, TextTheme, component themes) carries everything Material already has a slot for; one `ThemeExtension`, `PindoroTheme`, carries the game-specific parts (feedback tiers, XP, streak, path, map overlays, the 3D button, motion).

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
- Numeric text: use `PindoroType.numeric*` (tabular figures) for scores, distances, XP, timers.
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
| Progress | `ProgressIndicatorThemeData` | `color.xp.fill` on `color.xp.track`, `linearMinHeight: 18` |
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
- **XP and level:** `xpFill, xpLip, xpTrack, levelBg, levelRim, levelText`.
- **Streak:** `streakFlame, streakCore, streakText, streakDayDone, streakDayEmpty, streakFreezeFill, streakFreezeInk`.
- **League:** `gold, silver, bronze, promote, demote`.
- **Lesson path:** `road, edge, lane`, node colours (locked, review), street plate (`bg, lip, rule, text, subtext`).
- **Map overlays:** `answerLine, answerCasing, playerPin, playerPinLip, playerHalo, playerRoute, measureLine, measureLabel, measureLabelText, areaFill, areaStroke`, district `locked/progress/mastered` fill + stroke, `routeArrow`; v1 adds `mapAreaCenter, mapAreaLabelBg, mapAreaLabelLip, mapAreaLabelText, mapReticle, mapAttributionBg, mapAttributionText` and, for district presets on the area picker, `mapRegionOutline, mapRegionLabelBg, mapRegionLabelText`.
- **v1 components:** `inputBg, inputBorder, inputBorderFocus, inputText, inputPlaceholder, inputIcon`, `coachBg, coachText, coachLip`, and `PindoroSize.plateNameMin` (20) for the street-plate fit. Per-screen notes and the release plan: the MVP screens section.
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
- Springs: drive an `AnimationController` with `SpringSimulation(PindoroMotion.springBouncy, 0, 1, velocity)` for the pin drop, badge pop and stop unlock; `springSnappy` for button release and toggles; `springGentle` for drag-follow and map recentre.
- Pin drop: lift (−24 dp, 0.9 scale) → fall → squash (`Transform.scale(scaleX: 1.08, scaleY: 0.86, alignment: Alignment.bottomCenter)`) → spring back; ground shadow scales 0.4 → 1.
- Celebrations: build confetti with a lightweight particle painter (lane dashes and stars) or a Rive file; Pindo's expressions as one Rive state machine (`happy`, `cheering`, `thinking`, `encouraging`, `sleepy`, `proud`).
- Reduce motion: `final calm = MediaQuery.of(context).disableAnimations;` swap every animation for a 150 ms fade or an instant change; skip confetti entirely.

## 9. Haptics per event

| Event | Call |
| --- | --- |
| Tap, step, segment change, slider step | `HapticFeedback.selectionClick()` |
| Pin drop, Close, stop unlock | `HapticFeedback.lightImpact()` |
| Confirm, Great, streak +1, badge unlock | `HapticFeedback.mediumImpact()` |
| Perfect, streak milestone | `heavyImpact()`, then `mediumImpact()` after 90 ms |
| Level up | `heavyImpact()`, `mediumImpact()` +120 ms, `lightImpact()` +240 ms |
| Miss | `selectionClick()` twice, 60 ms apart |
| District mastered | `HapticFeedback.heavyImpact()` |

Wrap calls in a `Haptics` service that checks the in-app Haptics toggle; do the same with a `Sfx` service for the Sound toggle (preload all sounds at launch, ambient audio session on iOS).

## 10. Map

Use `flutter_map` with CARTO `light_nolabels` / `dark_nolabels` raster tiles (follow CARTO's attribution and usage terms). Draw overlays as `PolylineLayer` (answer: 12 dp casing + 8 dp yellow; player route dashed), `MarkerLayer` (pins as widgets so they share `PindoroButton`-style lips and animate), `CircleLayer` (radius) and `PolygonLayer` (districts; hatch via a custom painter). Take every colour from `PindoroTheme.colors.map*`.

## 11. App icon and splash

- `flutter_launcher_icons`: iOS from `ios-light-1024.png` (+ dark and tinted variants in the asset catalogue), Android adaptive from `android-foreground.svg` / `android-background.svg` (export as PNG or vector drawable) and `android-monochrome.svg` for themed icons.
- `flutter_native_splash`: background `color.cobalt.500` (dark `color.asphalt.950`), centred pin; the drop intro runs on the first Flutter frame (see Splash).
