import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:uuid/uuid.dart';

part 'database.g.dart';

String newId() => const Uuid().v7();

/// Single row (id = 1) of local preferences.
@DataClassName('Settings')
class UserSettings extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get lastCity => text().nullable()();
  TextColumn get lastAreaJson => text().nullable()();
  TextColumn get lastDifficulty => textEnum<Difficulty>().nullable()();
  BoolColumn get onboardingDone =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Round')
class Rounds extends Table {
  @override
  String get tableName => 'round';

  TextColumn get id => text().clientDefault(newId)();
  TextColumn get cityId => text()();
  TextColumn get areaJson => text()();
  TextColumn get difficulty => textEnum<Difficulty>()();
  TextColumn get packVersion => text()();
  DateTimeColumn get startedAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get finishedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Answer')
class Answers extends Table {
  @override
  String get tableName => 'answer';

  TextColumn get id => text().clientDefault(newId)();
  TextColumn get roundId => text().references(Rounds, #id)();
  TextColumn get streetId => text()();
  RealColumn get pinLat => real()();
  RealColumn get pinLon => real()();
  RealColumn get distanceM => real()();
  TextColumn get tier => textEnum<Tier>()();
  IntColumn get xp => integer()();
  TextColumn get packVersion => text()();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [UserSettings, Rounds, Answers],
  include: {'answer_immutable.drift'},
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'pindoro'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );

  Future<Settings> readSettings() async =>
      await (select(
        userSettings,
      )..where((s) => s.id.equals(1))).getSingleOrNull() ??
      const Settings(id: 1, onboardingDone: false);

  Future<void> updateSettings(UserSettingsCompanion changes) => into(
    userSettings,
  ).insertOnConflictUpdate(changes.copyWith(id: const Value(1)));

  Future<int> totalXp() async {
    final sum = answers.xp.sum();
    final row = await (selectOnly(answers)..addColumns([sum])).getSingle();
    return row.read(sum) ?? 0;
  }
}

/// Overridden in main() and in tests.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);
