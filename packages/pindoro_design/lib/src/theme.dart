import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';

import 'generated/pindoro_tokens.dart';
import 'widgets/graphics.dart';

/// One answer tier's colours (fill/lip/on for badges and buttons, bg/ink for
/// the reveal sheet) and icon, so a tier never relies on colour alone.
class TierStyle {
  const TierStyle({
    required this.fill,
    required this.lip,
    required this.on,
    required this.bg,
    required this.ink,
    required this.icon,
  });

  final Color fill;
  final Color lip;
  final Color on;
  final Color bg;
  final Color ink;
  final PindoroGlyph icon;
}

/// The game parts Material has no slot for: every Pindoro colour, plus the
/// soft shadow for elements floating over the map.
class PindoroTheme extends ThemeExtension<PindoroTheme> {
  const PindoroTheme({required this.colors, required this.floatShadow});

  static const light = PindoroTheme(
    colors: PindoroColors.light,
    floatShadow: PindoroShadow.floatLight,
  );

  static const dark = PindoroTheme(
    colors: PindoroColors.dark,
    floatShadow: PindoroShadow.floatDark,
  );

  final PindoroColors colors;
  final BoxShadow floatShadow;

  TierStyle tier(Tier tier) {
    final c = colors;
    return switch (tier) {
      Tier.perfect => TierStyle(
        fill: c.feedbackPerfectFill,
        lip: c.feedbackPerfectLip,
        on: c.feedbackPerfectOn,
        bg: c.feedbackPerfectBg,
        ink: c.feedbackPerfectInk,
        icon: PindoroGlyph.star,
      ),
      Tier.great => TierStyle(
        fill: c.feedbackGreatFill,
        lip: c.feedbackGreatLip,
        on: c.feedbackGreatOn,
        bg: c.feedbackGreatBg,
        ink: c.feedbackGreatInk,
        icon: PindoroGlyph.checkCircle,
      ),
      Tier.close => TierStyle(
        fill: c.feedbackCloseFill,
        lip: c.feedbackCloseLip,
        on: c.feedbackCloseOn,
        bg: c.feedbackCloseBg,
        ink: c.feedbackCloseInk,
        icon: PindoroGlyph.target,
      ),
      Tier.miss => TierStyle(
        fill: c.feedbackMissFill,
        lip: c.feedbackMissLip,
        on: c.feedbackMissOn,
        bg: c.feedbackMissBg,
        ink: c.feedbackMissInk,
        icon: PindoroGlyph.reroute,
      ),
    };
  }

  static PindoroTheme of(BuildContext context) =>
      Theme.of(context).extension<PindoroTheme>()!;

  @override
  PindoroTheme copyWith({PindoroColors? colors, BoxShadow? floatShadow}) =>
      PindoroTheme(
        colors: colors ?? this.colors,
        floatShadow: floatShadow ?? this.floatShadow,
      );

  @override
  PindoroTheme lerp(PindoroTheme? other, double t) => other == null
      ? this
      : PindoroTheme(
          colors: PindoroColors.lerp(colors, other.colors, t),
          floatShadow: BoxShadow.lerp(floatShadow, other.floatShadow, t)!,
        );
}

/// Material 3 theme from the tokens (slot mapping: docs/design/flutter-handoff.md).
ThemeData buildPindoroTheme(Brightness brightness) {
  final pindoro = brightness == Brightness.dark
      ? PindoroTheme.dark
      : PindoroTheme.light;
  final c = pindoro.colors;
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: c.primaryBase,
      onPrimary: c.primaryOn,
      primaryContainer: c.primarySoft,
      onPrimaryContainer: c.primaryText,
      secondary: c.rewardBase,
      onSecondary: c.rewardOn,
      secondaryContainer: c.rewardSoft,
      onSecondaryContainer: c.rewardText,
      tertiary: c.successBase,
      onTertiary: c.successOn,
      tertiaryContainer: c.successSoft,
      onTertiaryContainer: c.successText,
      error: c.errorBase,
      onError: c.errorOn,
      errorContainer: c.errorSoft,
      onErrorContainer: c.errorText,
      surface: c.surfaceBase,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      surfaceContainerLowest: c.surfaceRaised,
      surfaceContainerLow: c.surfaceRaised,
      surfaceContainer: c.surfaceOverlay,
      surfaceContainerHigh: c.surfaceSunken,
      surfaceContainerHighest: c.surfaceSunken,
      outline: c.lineStrong,
      outlineVariant: c.lineBase,
      inverseSurface: c.surfaceInverse,
      onInverseSurface: c.textInverse,
      inversePrimary: PindoroPalette.cobalt300,
      scrim: c.scrim,
      shadow: PindoroPalette.asphalt975,
      // Depth is the solid lip, never Material's tonal tint.
      surfaceTint: Colors.transparent,
    ),
    textTheme: const TextTheme(
      displayLarge: PindoroType.displayLg,
      displayMedium: PindoroType.displayMd,
      displaySmall: PindoroType.headlineLg,
      headlineLarge: PindoroType.headlineLg,
      headlineMedium: PindoroType.headlineMd,
      headlineSmall: PindoroType.headlineSm,
      titleLarge: PindoroType.titleLg,
      titleMedium: PindoroType.titleMd,
      titleSmall: PindoroType.titleSm,
      bodyLarge: PindoroType.bodyLg,
      bodyMedium: PindoroType.bodyMd,
      bodySmall: PindoroType.bodySm,
      labelLarge: PindoroType.labelLg,
      labelMedium: PindoroType.labelMd,
      labelSmall: PindoroType.labelSm,
    ).apply(bodyColor: c.textPrimary, displayColor: c.textPrimary),
    fontFamily: PindoroType.family,
    package: PindoroType.package,
    scaffoldBackgroundColor: c.surfaceBase,
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.xpFill,
      linearTrackColor: c.xpTrack,
    ),
    extensions: [pindoro],
  );
}
