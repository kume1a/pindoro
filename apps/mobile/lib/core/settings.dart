import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// The settings row, live: theme, language and toggles apply immediately.
final settingsProvider = StreamProvider<Settings>(
  (ref) => ref.watch(settingsDaoProvider).watch(),
);

extension SettingsPresentation on Settings {
  ThemeMode get themeMode => switch (theme) {
    ThemePreference.system => ThemeMode.system,
    ThemePreference.light => ThemeMode.light,
    ThemePreference.dark => ThemeMode.dark,
  };

  /// Null follows the device.
  Locale? get locale => switch (appLanguage) {
    null => null,
    final language => Locale(language.name),
  };
}

/// Haptics per game event, behind the Haptics toggle; sounds behind the Sound
/// toggle (motion-sound-haptics.md).
class GameFeedback {
  const GameFeedback({required this.haptics, required this.sound});

  final bool haptics;
  final bool sound;

  void tap() => _haptic(HapticFeedback.selectionClick);

  void pinDrop() => _haptic(HapticFeedback.lightImpact);

  /// The next stop on the Path opens.
  void unlock() => _haptic(HapticFeedback.lightImpact);

  /// A road trip's route reaches the next junction.
  void junction() => _haptic(HapticFeedback.selectionClick);

  /// A road trip's route reaches B.
  void reached() => _haptic(HapticFeedback.lightImpact);

  /// A unit is complete, and the next unit's signpost flips open.
  void unitDone() => _haptic(HapticFeedback.mediumImpact);

  void confirm() => _haptic(HapticFeedback.mediumImpact);

  void error() => _haptic(HapticFeedback.heavyImpact);

  /// The round's reward total lands after counting up.
  void reward() => _haptic(HapticFeedback.mediumImpact);

  /// The streak grows by a day (component Streak § Streak increase).
  void streak() => _haptic(HapticFeedback.mediumImpact);

  void tier(Tier tier) => switch (tier) {
    Tier.perfect => _sequence([
      HapticFeedback.heavyImpact,
      HapticFeedback.mediumImpact,
    ], const Duration(milliseconds: 90)),
    Tier.great => _haptic(HapticFeedback.mediumImpact),
    Tier.close => _haptic(HapticFeedback.lightImpact),
    Tier.miss => _sequence([
      HapticFeedback.selectionClick,
      HapticFeedback.selectionClick,
    ], const Duration(milliseconds: 60)),
  };

  void levelUp() => _sequence([
    HapticFeedback.heavyImpact,
    HapticFeedback.mediumImpact,
    HapticFeedback.lightImpact,
  ], const Duration(milliseconds: 120));

  void _haptic(Future<void> Function() feedback) {
    if (haptics) unawaited(feedback());
  }

  void _sequence(List<Future<void> Function()> steps, Duration gap) {
    if (!haptics) return;
    for (final (i, step) in steps.indexed) {
      unawaited(Future<void>.delayed(gap * i, step));
    }
  }
}

// ponytail: no sound kit exists yet, so `sound` gates nothing; add an audio
// player here once the designed sounds land.
final feedbackProvider = Provider<GameFeedback>((ref) {
  final settings = ref.watch(settingsProvider).value;
  return GameFeedback(
    haptics: settings?.haptics ?? true,
    sound: settings?.sound ?? true,
  );
});
