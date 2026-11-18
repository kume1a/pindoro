import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';

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
