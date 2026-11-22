import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

part 'settings_dao.g.dart';

/// The single settings row (id = 1). Screens change it through these methods
/// rather than writing Drift rows themselves.
@DriftAccessor(tables: [UserSettings])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.attachedDatabase);

  /// The row before anything was saved; matches the table's defaults.
  static const _defaults = Settings(
    id: 1,
    streetNames: StreetNameMode.local,
    theme: ThemePreference.system,
    sound: true,
    haptics: true,
    homeCoachSeen: false,
    reminder: false,
    minutesPerDay: 20,
    zoomButtons: false,
    speedToleranceKmh: LearningConfig.speedToleranceKmh,
  );

  SimpleSelectStatement<$UserSettingsTable, Settings> get _row =>
      select(userSettings)..where((s) => s.id.equals(1));

  Future<Settings> read() async => await _row.getSingleOrNull() ?? _defaults;

  /// The settings row as it changes; defaults until the first write.
  Stream<Settings> watch() =>
      _row.watchSingleOrNull().map((row) => row ?? _defaults);

  /// Another city's area doesn't apply there, so a new city clears the area.
  Future<void> chooseCity(String cityId) async {
    final current = await read();
    await _update(
      UserSettingsCompanion(
        lastCity: Value(cityId),
        lastAreaJson: cityId == current.lastCity
            ? const Value.absent()
            : const Value(null),
      ),
    );
  }

  /// The area to play; with [cityId], also the city it belongs to.
  Future<void> chooseArea(Area area, {String? cityId}) => _update(
    UserSettingsCompanion(
      lastCity: cityId == null ? const Value.absent() : Value(cityId),
      lastAreaJson: Value(jsonEncode(area.toJson())),
    ),
  );

  Future<void> chooseDifficulty(Difficulty difficulty) =>
      _update(UserSettingsCompanion(lastDifficulty: Value(difficulty)));

  Future<void> setLanguage(AppLanguage language) =>
      _update(UserSettingsCompanion(appLanguage: Value(language)));

  Future<void> setStreetNames(StreetNameMode mode) =>
      _update(UserSettingsCompanion(streetNames: Value(mode)));

  Future<void> setTheme(ThemePreference theme) =>
      _update(UserSettingsCompanion(theme: Value(theme)));

  Future<void> setSound({required bool on}) =>
      _update(UserSettingsCompanion(sound: Value(on)));

  Future<void> setHaptics({required bool on}) =>
      _update(UserSettingsCompanion(haptics: Value(on)));

  Future<void> setZoomButtons({required bool on}) =>
      _update(UserSettingsCompanion(zoomButtons: Value(on)));

  Future<void> setSpeedTolerance(int kmh) =>
      _update(UserSettingsCompanion(speedToleranceKmh: Value(kmh)));

  /// Home ([home]) or Work for drives, as `DrivePlace` JSON; null clears it.
  Future<void> setDrivePlace(String? json, {required bool home}) => _update(
    home
        ? UserSettingsCompanion(driveHome: Value(json))
        : UserSettingsCompanion(driveWork: Value(json)),
  );

  /// This week's planned drives, as `DrivePlan` JSON.
  Future<void> setDrivePlan(String json) =>
      _update(UserSettingsCompanion(drivePlan: Value(json)));

  Future<void> setReminder({required bool on}) =>
      _update(UserSettingsCompanion(reminder: Value(on)));

  /// The learning session's length: 15, 20 or 30 minutes.
  Future<void> setMinutesPerDay(int minutes) =>
      _update(UserSettingsCompanion(minutesPerDay: Value(minutes)));

  /// Fitted FSRS weights as JSON, or null for SPEC §4's.
  Future<void> setFsrsWeights(String? json) =>
      _update(UserSettingsCompanion(fsrsWeights: Value(json)));

  Future<void> markHomeCoachSeen() =>
      _update(const UserSettingsCompanion(homeCoachSeen: Value(true)));

  Future<void> _update(UserSettingsCompanion changes) => into(
    userSettings,
  ).insertOnConflictUpdate(changes.copyWith(id: const Value(1)));
}

final settingsDaoProvider = Provider<SettingsDao>(
  (ref) => SettingsDao(ref.watch(databaseProvider)),
);
