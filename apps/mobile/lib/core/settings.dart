import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/sounds.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

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

/// Haptics and sounds per game event, behind the Haptics and Sound toggles
/// (motion-sound-haptics.md, sound kit on canvas M-60).
class GameFeedback {
  const GameFeedback({
    required this.sounds,
    required this.haptics,
    required this.sound,
  });

  final Sounds sounds;
  final bool haptics;
  final bool sound;

  /// Chips, tabs and steps: the tap sound is for hero buttons only.
  void tap() => _haptic(HapticFeedback.selectionClick);

  /// A hero button (Play, Start, Continue).
  void press() => _play(Sound.tap);

  void pinDrop() {
    _play(Sound.pinTok);
    _haptic(HapticFeedback.lightImpact);
  }

  /// The pin lands in the cold-start moment.
  void launch() {
    _play(Sound.launchTok);
    _haptic(HapticFeedback.lightImpact);
  }

  /// The next stop on the Path opens.
  void unlock() {
    _play(Sound.unlock);
    _haptic(HapticFeedback.lightImpact);
  }

  /// A road trip's route reaches the next junction.
  void junction() {
    _play(Sound.countTick);
    _haptic(HapticFeedback.selectionClick);
  }

  /// A road trip's route reaches B (a two-note arrive).
  void reached() {
    _play(Sound.tierGreat);
    _haptic(HapticFeedback.lightImpact);
  }

  /// A unit is complete, and the next unit's signpost flips open (a
  /// three-note rise).
  void unitDone() {
    _play(Sound.tierPerfect);
    _haptic(HapticFeedback.mediumImpact);
  }

  /// A badge's reward sheet opens (component Badge § Reward moment).
  void badge() {
    _play(Sound.unlock);
    _haptic(HapticFeedback.mediumImpact);
  }

  void confirm() {
    _play(Sound.confirm);
    _haptic(HapticFeedback.mediumImpact);
  }

  void error() {
    _play(Sound.errorSoft);
    _haptic(HapticFeedback.heavyImpact);
  }

  /// Soft rising ticks while a reward counts up after [delay]: they follow
  /// [CountUp]'s ease-out, so they thin out as the digits slow down.
  void countUp(Duration delay) {
    if (!sound) return;
    const ticks = 10;
    for (var i = 0; i < ticks; i++) {
      final at = 1 - pow(1 - i / ticks, 1 / 3);
      unawaited(
        Future<void>.delayed(
          delay + PindoroMotion.countUp * at,
          () => sounds.play(Sound.countTick, speed: 1 + 0.5 * i / (ticks - 1)),
        ),
      );
    }
  }

  /// The round's reward total lands after counting up.
  void reward() {
    _play(Sound.land);
    _haptic(HapticFeedback.mediumImpact);
  }

  /// The streak grows by a day (component Streak § Streak increase).
  void streak() {
    _play(Sound.streak);
    _haptic(HapticFeedback.mediumImpact);
  }

  void tier(Tier tier) {
    switch (tier) {
      case Tier.perfect:
        _play(Sound.tierPerfect);
        _sequence([
          HapticFeedback.heavyImpact,
          HapticFeedback.mediumImpact,
        ], const Duration(milliseconds: 90));
      case Tier.great:
        _play(Sound.tierGreat);
        _haptic(HapticFeedback.mediumImpact);
      case Tier.close:
        _play(Sound.tierClose);
        _haptic(HapticFeedback.lightImpact);
      case Tier.miss:
        _play(Sound.tierMiss);
        _sequence([
          HapticFeedback.selectionClick,
          HapticFeedback.selectionClick,
        ], const Duration(milliseconds: 60));
    }
  }

  void levelUp() {
    _play(Sound.levelupFanfare);
    _sequence([
      HapticFeedback.heavyImpact,
      HapticFeedback.mediumImpact,
      HapticFeedback.lightImpact,
    ], const Duration(milliseconds: 120));
  }

  void _play(Sound s) {
    if (sound) sounds.play(s);
  }

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

final feedbackProvider = Provider<GameFeedback>((ref) {
  final settings = ref.watch(settingsProvider).value;
  return GameFeedback(
    sounds: ref.watch(soundsProvider),
    haptics: settings?.haptics ?? true,
    sound: settings?.sound ?? true,
  );
});

/// Plays the count-up ticks once per end screen, with its reward [CountUp].
mixin CountUpTicks<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool _ticked = false;

  void tickCountUp(int value, Duration delay) {
    if (_ticked) return;
    _ticked = true;
    // Reduce motion shows the final value at once: nothing to tick through.
    if (value > 0 && !MediaQuery.disableAnimationsOf(context)) {
      ref.read(feedbackProvider).countUp(delay);
    }
  }
}
