import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';

import 'generated/pindoro_tokens.dart';

typedef _T = PindoroTokens;

const String fontFamily = 'FiraGO';
const String fontPackage = 'pindoro_design';
const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

class TierStyle {
  const TierStyle({required this.fill, required this.on, required this.icon});

  final Color fill;
  final Color on;
  final IconData icon;
}

class PindoroTheme extends ThemeExtension<PindoroTheme> {
  const PindoroTheme({
    required this.background,
    required this.card,
    required this.lip,
    required this.text,
    required this.muted,
  });

  static const light = PindoroTheme(
    background: _T.colorSurfaceLightBackground,
    card: _T.colorSurfaceLightCard,
    lip: _T.colorSurfaceLightLip,
    text: _T.colorSurfaceLightText,
    muted: _T.colorSurfaceLightMuted,
  );

  static const dark = PindoroTheme(
    background: _T.colorSurfaceDarkBackground,
    card: _T.colorSurfaceDarkCard,
    lip: _T.colorSurfaceDarkLip,
    text: _T.colorSurfaceDarkText,
    muted: _T.colorSurfaceDarkMuted,
  );

  final Color background;
  final Color card;
  final Color lip;
  final Color text;
  final Color muted;

  // Map roles never change with brightness: yellow = truth, cobalt = you,
  // ink = measurement.
  Color get mapTruth => _T.colorMapTruth;
  Color get mapYou => _T.colorMapYou;
  Color get mapMeasure => _T.colorMapMeasure;

  double get radius => _T.radiusLg;

  TierStyle tier(Tier tier) => switch (tier) {
    Tier.perfect => const TierStyle(
      fill: _T.colorFeedbackPerfectFill,
      on: _T.colorFeedbackPerfectOn,
      icon: Icons.star_rounded,
    ),
    Tier.great => const TierStyle(
      fill: _T.colorFeedbackGreatFill,
      on: _T.colorFeedbackGreatOn,
      icon: Icons.check_circle_rounded,
    ),
    Tier.close => const TierStyle(
      fill: _T.colorFeedbackCloseFill,
      on: _T.colorFeedbackCloseOn,
      icon: Icons.track_changes_rounded,
    ),
    Tier.miss => const TierStyle(
      fill: _T.colorFeedbackMissFill,
      on: _T.colorFeedbackMissOn,
      icon: Icons.alt_route_rounded,
    ),
  };

  static PindoroTheme of(BuildContext context) =>
      Theme.of(context).extension<PindoroTheme>()!;

  // ponytail: only two fixed instances exist, so copy/lerp just snap.
  @override
  PindoroTheme copyWith() => this;

  @override
  PindoroTheme lerp(PindoroTheme? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

ThemeData buildPindoroTheme(Brightness brightness) {
  final pindoro = brightness == Brightness.dark
      ? PindoroTheme.dark
      : PindoroTheme.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: _T.colorBrandCobalt,
    onPrimary: _T.colorButtonPrimaryText,
    secondary: _T.colorBrandYellow,
    onSecondary: _T.colorBrandInk,
    error: _T.colorBrandRed,
    onError: _T.colorFeedbackMissOn,
    surface: pindoro.background,
    onSurface: pindoro.text,
    onSurfaceVariant: pindoro.muted,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: pindoro.background,
    // M3 would draw the track in `secondary` (yellow): an empty bar looks full.
    progressIndicatorTheme: ProgressIndicatorThemeData(
      linearTrackColor: pindoro.lip,
    ),
    fontFamily: fontFamily,
    package: fontPackage,
    extensions: [pindoro],
  );
  return base.copyWith(textTheme: _withTabularFigures(_sized(base.textTheme)));
}

TextTheme _sized(TextTheme t) => t.copyWith(
  displaySmall: t.displaySmall?.copyWith(
    fontSize: _T.typeDisplay,
    fontWeight: FontWeight.w700,
  ),
  titleLarge: t.titleLarge?.copyWith(
    fontSize: _T.typeTitle,
    fontWeight: FontWeight.w600,
  ),
  bodyLarge: t.bodyLarge?.copyWith(fontSize: _T.typeBody),
  bodyMedium: t.bodyMedium?.copyWith(fontSize: _T.typeBody),
  labelLarge: t.labelLarge?.copyWith(
    fontSize: _T.typeLabel,
    fontWeight: FontWeight.w600,
  ),
  bodySmall: t.bodySmall?.copyWith(fontSize: _T.typeCaption),
);

TextTheme _withTabularFigures(TextTheme t) {
  TextStyle? f(TextStyle? s) => s?.copyWith(fontFeatures: tabularFigures);
  return t.copyWith(
    displayLarge: f(t.displayLarge),
    displayMedium: f(t.displayMedium),
    displaySmall: f(t.displaySmall),
    headlineLarge: f(t.headlineLarge),
    headlineMedium: f(t.headlineMedium),
    headlineSmall: f(t.headlineSmall),
    titleLarge: f(t.titleLarge),
    titleMedium: f(t.titleMedium),
    titleSmall: f(t.titleSmall),
    bodyLarge: f(t.bodyLarge),
    bodyMedium: f(t.bodyMedium),
    bodySmall: f(t.bodySmall),
    labelLarge: f(t.labelLarge),
    labelMedium: f(t.labelMedium),
    labelSmall: f(t.labelSmall),
  );
}
