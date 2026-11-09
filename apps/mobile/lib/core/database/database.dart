import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.steps.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:uuid/uuid.dart';

part 'database.g.dart';

String newId() => const Uuid().v7();

/// Parses a stored area; null when unset or unreadable (e.g. the M1 whole city).
Area? parseArea(String? json) {
  if (json == null) return null;
  try {
    return switch (jsonDecode(json)) {
      final Map<String, Object?> map => Area.fromJson(map),
      _ => null,
    };
  } on FormatException {
    return null;
  }
}

extension SettingsArea on Settings {
  /// The saved area; null until the player picks one.
  Area? get area => parseArea(lastAreaJson);

  /// The saved difficulty; medium (the picker's default) until one is picked.
  Difficulty get difficulty => lastDifficulty ?? Difficulty.medium;
}

enum AppLanguage { en, ka }

/// How street names show: as the city writes them, or in English when the
/// pack has an English name.
enum StreetNameMode { local, english }

/// Light, dark, or the device setting (kept Flutter-free for drift's exporter).
enum ThemePreference { system, light, dark }

/// Single row (id = 1) of local preferences.
@DataClassName('Settings')
class UserSettings extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get lastCity => text().nullable()();
  TextColumn get lastAreaJson => text().nullable()();
  TextColumn get lastDifficulty => textEnum<Difficulty>().nullable()();

  /// Null follows the device language.
  TextColumn get appLanguage => textEnum<AppLanguage>().nullable()();
  // Literal defaults: drift copies them into the generated migration steps.
  TextColumn get streetNames =>
      textEnum<StreetNameMode>().withDefault(const Constant('local'))();
  TextColumn get theme =>
      textEnum<ThemePreference>().withDefault(const Constant('system'))();
  BoolColumn get sound => boolean().withDefault(const Constant(true))();
  BoolColumn get haptics => boolean().withDefault(const Constant(true))();

  /// The first Home's coach mark was closed.
  BoolColumn get homeCoachSeen =>
      boolean().withDefault(const Constant(false))();

  /// XP a day that counts toward the streak (pindoro_core `StreakRules`).
  IntColumn get dailyGoal => integer().withDefault(const Constant(500))();

  /// The 19:00 reminder when today's goal isn't met.
  BoolColumn get reminder => boolean().withDefault(const Constant(false))();

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

  /// The round whose Close and Miss streets this round retries.
  TextColumn get retryOf => text().nullable().references(Rounds, #id)();

  /// A Pit stop round: the due streets of the Pit stop.
  BoolColumn get pitStop => boolean().withDefault(const Constant(false))();

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

/// The streets planned for a round, in order. With the answer log this
/// derives where a round stands, so rounds resume after an app kill.
@DataClassName('RoundQuestion')
class RoundQuestions extends Table {
  @override
  String get tableName => 'round_question';

  TextColumn get roundId => text().references(Rounds, #id)();
  IntColumn get position => integer()();
  TextColumn get streetId => text()();

  @override
  Set<Column<Object>> get primaryKey => {roundId, position};
}

/// Local dates when the daily XP goal was met; the streak, its freezes and
/// the best run are derived from them (pindoro_core `streakOf`).
@DataClassName('GoalDay')
class GoalDays extends Table {
  @override
  String get tableName => 'goal_day';

  /// The local date as `YYYY-MM-DD` (pindoro_core `dayKey`).
  TextColumn get date => text()();

  /// The round whose answer reached the goal; null when lowering it did.
  TextColumn get roundId => text().nullable().references(Rounds, #id)();

  @override
  Set<Column<Object>> get primaryKey => {date};
}

/// A street in the Pit stop (pindoro_core `nextReview`), kept with every
/// answer; graduated streets have no row.
@DataClassName('ReviewItem')
class ReviewItems extends Table {
  @override
  String get tableName => 'review_item';

  TextColumn get cityId => text()();
  TextColumn get streetId => text()();

  /// 1–4: due 1, 3, 7 or 21 days after the last answer.
  IntColumn get step => integer()();

  /// Great-or-better answers in a row.
  IntColumn get greatRun => integer()();

  /// The calendar day it's due (`YYYY-MM-DD`, pindoro_core `dayKey`).
  TextColumn get dueOn => text()();
  TextColumn get lastTier => textEnum<Tier>()();
  DateTimeColumn get lastAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {cityId, streetId};
}

/// Where a city's course starts (pindoro_core `buildCourse`): saved the first
/// time its Path opens.
@DataClassName('CourseRow')
class Courses extends Table {
  @override
  String get tableName => 'course';

  TextColumn get cityId => text()();
  TextColumn get startDistrictId => text()();

  @override
  Set<Column<Object>> get primaryKey => {cityId};
}

/// A finished lesson, practice or unit Pit stop; nothing is written before
/// it finishes, so leaving one drops its XP.
@DataClassName('LessonResult')
class LessonResults extends Table {
  @override
  String get tableName => 'lesson_result';

  TextColumn get id => text().clientDefault(newId)();
  TextColumn get cityId => text()();

  /// The unit's raion (district id).
  TextColumn get unitId => text()();
  TextColumn get kind => textEnum<LessonKind>()();

  /// The lesson's number in its unit; null for the unit's Pit stop.
  IntColumn get lesson => integer().nullable()();
  TextColumn get difficulty => textEnum<Difficulty>()();

  /// Everything it earned, bonuses included.
  IntColumn get xp => integer()();
  BoolColumn get perfect => boolean()();

  /// Tests right first time, out of [tests].
  IntColumn get rightFirst => integer()();
  IntColumn get tests => integer()();
  IntColumn get durationMs => integer()();
  DateTimeColumn get finishedAt => dateTime().clientDefault(DateTime.now)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

enum LessonAnswerKind { pin, name }

/// A lesson result's answers in order; a name answer is Great when right and
/// Miss when wrong, and has no distance.
@DataClassName('LessonAnswer')
class LessonAnswers extends Table {
  @override
  String get tableName => 'lesson_answer';

  TextColumn get resultId => text().references(LessonResults, #id)();
  IntColumn get position => integer()();
  TextColumn get streetId => text()();
  TextColumn get kind => textEnum<LessonAnswerKind>()();
  TextColumn get tier => textEnum<Tier>()();
  IntColumn get xp => integer()();

  /// A mistake's second try at the end of the lesson.
  BoolColumn get fix => boolean()();
  RealColumn get distanceM => real().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {resultId, position};
}

@DriftDatabase(
  tables: [
    UserSettings,
    Rounds,
    Answers,
    RoundQuestions,
    GoalDays,
    ReviewItems,
    Courses,
    LessonResults,
    LessonAnswers,
  ],
  include: {'answer_immutable.drift'},
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'pindoro'));

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: stepByStep(
      from1To2: (m, schema) => m.createTable(schema.roundQuestion),
      from2To3: (m, schema) => m.addColumn(schema.round, schema.round.retryOf),
      // Rebuilds the table: adds the preference columns, drops onboarding_done.
      from3To4: (m, schema) {
        final t = schema.userSettings;
        return m.alterTable(
          TableMigration(
            t,
            newColumns: [
              t.appLanguage,
              t.streetNames,
              t.theme,
              t.sound,
              t.haptics,
            ],
          ),
        );
      },
      from4To5: (m, schema) =>
          m.addColumn(schema.userSettings, schema.userSettings.homeCoachSeen),
      from5To6: (m, schema) async {
        await m.createTable(schema.goalDay);
        await m.addColumn(schema.userSettings, schema.userSettings.dailyGoal);
        await m.addColumn(schema.userSettings, schema.userSettings.reminder);
      },
      from6To7: (m, schema) async {
        await m.createTable(schema.reviewItem);
        await m.addColumn(schema.round, schema.round.pitStop);
      },
      from7To8: (m, schema) async {
        await m.createTable(schema.course);
        await m.createTable(schema.lessonResult);
        await m.createTable(schema.lessonAnswer);
      },
    ),
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}

/// Overridden in main() and in tests.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);
