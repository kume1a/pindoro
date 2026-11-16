import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.steps.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
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

  /// The chosen city; the default one until the player picks.
  String get cityId => lastCity ?? AppConfig.defaultCityId;
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

  /// The 19:00 reminder when today's day hasn't counted and reviews are due.
  BoolColumn get reminder => boolean().withDefault(const Constant(false))();

  /// The daily learning session's length: 15, 20 or 30 minutes.
  IntColumn get minutesPerDay => integer().withDefault(const Constant(20))();

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

/// Streets the old game knew (a Great or Perfect in a lesson), kept from the
/// lesson tables when v3 dropped them, so carry-over still finds them.
@DataClassName('LegacyKnownRow')
class LegacyKnown extends Table {
  @override
  String get tableName => 'legacy_known';

  TextColumn get cityId => text()();
  TextColumn get streetId => text()();

  @override
  Set<Column<Object>> get primaryKey => {cityId, streetId};
}

/// The account (one row): its username, the secret token for its
/// `/me` routes (null once a sign-in on another phone signed this one out),
/// when this phone last backed up, and since when it has progress the backup
/// lacks. Left out of the backups.
@DataClassName('Account')
class Accounts extends Table {
  @override
  String get tableName => 'account';

  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get username => text()();
  TextColumn get token => text().nullable()();
  DateTimeColumn get backedUpAt => dateTime().nullable()();
  DateTimeColumn get changedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// An earned badge (pindoro_learning `BadgeId` by name, or a City memory
/// milestone's `cityMemoryBadge`): saved once and never removed,
/// so a badge stays earned when its condition stops holding (a pack update
/// can unmaster a district).
@DataClassName('BadgeRow')
class Badges extends Table {
  @override
  String get tableName => 'badge';

  TextColumn get id => text()();
  DateTimeColumn get earnedAt => dateTime()();

  /// When the player saw it (its reward sheet closed, or Me showed it); null
  /// shows the New pill.
  DateTimeColumn get seenAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One learning card per item (docs/learning/SPEC.md §2.2); an unseen item
/// has no row. Mapped to pindoro_learning `CardState` by the learning
/// repository.
@DataClassName('CardStateRow')
class CardStates extends Table {
  @override
  String get tableName => 'card_state';

  TextColumn get itemId => text()();

  /// The item id's prefix (`P`, `N`, …), kept for filtering in SQL.
  TextColumn get type => text()();
  TextColumn get state => textEnum<CardPhase>()();
  RealColumn get stability => real().nullable()();
  RealColumn get difficulty => real().nullable()();
  DateTimeColumn get lastReviewAt => dateTime().nullable()();
  DateTimeColumn get dueAt => dateTime().nullable()();
  IntColumn get reps => integer().withDefault(const Constant(0))();
  IntColumn get lapses => integer().withDefault(const Constant(0))();

  /// 1 Again … 4 Easy.
  IntColumn get lastRating => integer().nullable()();
  RealColumn get lastDistanceM => real().nullable()();
  TextColumn get lastSnapId => text().nullable()();
  BoolColumn get priorKnown => boolean().withDefault(const Constant(false))();
  DateTimeColumn get introAt => dateTime().nullable()();

  /// The player's memory aid for a leech (SPEC §4).
  TextColumn get note => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {itemId};
}

/// Every graded answer, append-only (`review_log_immutable.drift`): the
/// FSRS optimiser and the progress numbers replay it.
@DataClassName('ReviewLogRow')
class ReviewLogs extends Table {
  @override
  String get tableName => 'review_log';

  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get ts => dateTime()();
  TextColumn get itemId => text()();
  TextColumn get type => text()();
  TextColumn get format => textEnum<ReviewFormat>()();

  /// 1 Again … 4 Easy.
  IntColumn get rating => integer()();
  RealColumn get distanceM => real().nullable()();
  TextColumn get snapId => text().nullable()();
  IntColumn get rtMs => integer().nullable()();
  RealColumn get elapsedDays => real().nullable()();
  RealColumn get rBefore => real().nullable()();
  RealColumn get sBefore => real().nullable()();
  RealColumn get dBefore => real().nullable()();
  TextColumn get sessionId => text().nullable()();
  TextColumn get source => textEnum<ReviewSource>()();
}

/// A pin for [streetA] landed on [streetB] (a mix-up), [count] times.
@DataClassName('ConfusionRow')
class Confusions extends Table {
  @override
  String get tableName => 'confusion';

  TextColumn get streetA => text()();
  TextColumn get streetB => text()();
  IntColumn get count => integer().withDefault(const Constant(1))();
  DateTimeColumn get lastAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {streetA, streetB};
}

/// Per city: when placement ended (or the player chose to start from zero)
/// and the home and work neighbourhoods new streets start in (SPEC §6.2, §6.3).
@DataClassName('LearnCityRow')
class LearnCities extends Table {
  @override
  String get tableName => 'learn_city';

  TextColumn get cityId => text()();
  DateTimeColumn get placedAt => dateTime().nullable()();
  TextColumn get homeId => text().nullable()();
  TextColumn get workId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {cityId};
}

@DriftDatabase(
  tables: [
    UserSettings,
    Rounds,
    Answers,
    RoundQuestions,
    GoalDays,
    LegacyKnown,
    Badges,
    Accounts,
    CardStates,
    ReviewLogs,
    Confusions,
    LearnCities,
  ],
  include: {'answer_immutable.drift', 'review_log_immutable.drift'},
)
class AppDatabase extends _$AppDatabase {
  /// The app opens it with `openDatabase()`, tests in memory.
  AppDatabase(super.e);

  static const int version = 18;

  @override
  int get schemaVersion => version;

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
      from8To9: (m, schema) async {
        await m.createTable(schema.savedLesson);
        await m.addColumn(schema.userSettings, schema.userSettings.turnList);
      },
      from9To10: (m, schema) => m.createTable(schema.leaguePlayer),
      from10To11: (m, schema) async {
        await m.createTable(schema.badge);
        await m.createTable(schema.reviewCleared);
      },
      from11To12: (m, schema) => m.createTable(schema.account),
      // Rebuilds the table: the token becomes nullable, changed_at is new.
      from12To13: (m, schema) => m.alterTable(
        TableMigration(schema.account, newColumns: [schema.account.changedAt]),
      ),
      // Leagues sign in with the account, so the anonymous league player goes.
      from13To14: (m, schema) => m.deleteTable('league_player'),
      // The v3 learning system: cards, the append-only review log, mix-ups
      // and the minutes a day.
      from14To15: (m, schema) async {
        await m.createTable(schema.cardState);
        await m.createTable(schema.reviewLog);
        await m.createTable(schema.confusion);
        await m.create(schema.reviewLogNoUpdate);
        await m.create(schema.reviewLogNoDelete);
        await m.addColumn(
          schema.userSettings,
          schema.userSettings.minutesPerDay,
        );
      },
      from15To16: (m, schema) => m.createTable(schema.learnCity),
      // v3 replaces the old game layer: lessons, the Path, the Pit stop, XP
      // and the daily XP goal go. Lesson knowledge stays for carry-over.
      from16To17: (m, schema) async {
        await m.createTable(schema.legacyKnown);
        await customStatement('''
          INSERT OR IGNORE INTO legacy_known (city_id, street_id)
          SELECT r.city_id, a.street_id
          FROM lesson_answer a JOIN lesson_result r ON r.id = a.result_id
          WHERE a.kind <> 'trip' AND a.tier IN ('perfect', 'great')
            AND NOT (a.kind = 'name' AND a.fix = 1)
        ''');
        for (final table in [
          'saved_lesson',
          'lesson_answer',
          'lesson_result',
          'course',
          'review_item',
          'review_cleared',
        ]) {
          await m.deleteTable(table);
        }
        await m.dropColumn(schema.answer, 'xp');
        await m.dropColumn(schema.round, 'pit_stop');
        await m.dropColumn(schema.userSettings, 'daily_goal');
        await m.dropColumn(schema.userSettings, 'turn_list');
      },
      from17To18: (m, schema) =>
          m.addColumn(schema.cardState, schema.cardState.note),
    ),
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}

/// Overridden in main() and in tests.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);
