import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:uuid/uuid.dart';

import 'database.steps.dart';

part 'database.g.dart';

String newId() => const Uuid().v7();

const _rowid = CustomExpression<int>('rowid');

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

typedef RoundProgress = ({
  Round round,
  List<String> planned,
  List<Answer> answers,
});

@DriftDatabase(
  tables: [UserSettings, Rounds, Answers, RoundQuestions],
  include: {'answer_immutable.drift'},
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'pindoro'));

  @override
  int get schemaVersion => 4;

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
    ),
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );

  Future<Settings> readSettings() async =>
      await (select(
        userSettings,
      )..where((s) => s.id.equals(1))).getSingleOrNull() ??
      const Settings(
        id: 1,
        streetNames: StreetNameMode.local,
        theme: ThemePreference.system,
        sound: true,
        haptics: true,
      );

  /// The settings row as it changes; defaults until the first write.
  Stream<Settings> watchSettings() =>
      (select(userSettings)..where((s) => s.id.equals(1)))
          .watchSingleOrNull()
          .asyncMap((row) async => row ?? await readSettings());

  /// Whether the player has ever answered (the first-question hint shows once).
  Future<bool> hasAnswered() async =>
      await (select(answers)..limit(1)).getSingleOrNull() != null;

  /// Welcome shows until the player finishes a first round.
  Future<bool> hasFinishedRound() async =>
      await (select(rounds)
            ..where((r) => r.finishedAt.isNotNull())
            ..limit(1))
          .getSingleOrNull() !=
      null;

  Future<void> updateSettings(UserSettingsCompanion changes) => into(
    userSettings,
  ).insertOnConflictUpdate(changes.copyWith(id: const Value(1)));

  Future<int> totalXp() async {
    final sum = answers.xp.sum();
    final row = await (selectOnly(answers)..addColumns([sum])).getSingle();
    return row.read(sum) ?? 0;
  }

  /// Inserts the round and its planned streets atomically; returns the round id.
  Future<String> startRound({
    required String cityId,
    required Area area,
    required Difficulty difficulty,
    required String packVersion,
    required List<String> streetIds,
    String? retryOf,
  }) => transaction(() async {
    final round = await into(rounds).insertReturning(
      RoundsCompanion.insert(
        cityId: cityId,
        areaJson: jsonEncode(area.toJson()),
        difficulty: difficulty,
        packVersion: packVersion,
        retryOf: Value(retryOf),
      ),
    );
    await batch(
      (b) => b.insertAll(roundQuestions, [
        for (final (i, streetId) in streetIds.indexed)
          RoundQuestionsCompanion.insert(
            roundId: round.id,
            position: i,
            streetId: streetId,
          ),
      ]),
    );
    return round.id;
  });

  /// A saved round expires this long after its last answer (or its start).
  static const Duration savedRoundLifetime = Duration(days: 7);

  /// The most recent round while it is unfinished and active within
  /// [savedRoundLifetime]; starting a new round abandons older ones.
  Future<Round?> resumableRound(DateTime now) async {
    final latest =
        await (select(rounds)
              ..orderBy([(_) => OrderingTerm.desc(_rowid)])
              ..limit(1))
            .getSingleOrNull();
    if (latest == null || latest.finishedAt != null) return null;
    final lastAnswer =
        await (select(answers)
              ..where((a) => a.roundId.equals(latest.id))
              ..orderBy([(_) => OrderingTerm.desc(_rowid)])
              ..limit(1))
            .getSingleOrNull();
    final active = lastAnswer?.createdAt ?? latest.startedAt;
    return now.difference(active) > savedRoundLifetime ? null : latest;
  }

  /// [resumableRound] when it is for the current settings' city and area.
  Future<Round?> savedRound(DateTime now) async {
    final round = await resumableRound(now);
    if (round == null) return null;
    final settings = await readSettings();
    final city = settings.lastCity;
    final sameCity = city == null || city == round.cityId;
    return sameCity && parseArea(round.areaJson) == settings.area
        ? round
        : null;
  }

  Future<RoundProgress> roundProgress(String roundId) async => (
    round: await (select(
      rounds,
    )..where((r) => r.id.equals(roundId))).getSingle(),
    planned:
        await (select(roundQuestions)
              ..where((q) => q.roundId.equals(roundId))
              ..orderBy([(q) => OrderingTerm.asc(q.position)]))
            .map((q) => q.streetId)
            .get(),
    answers: await answersForRound(roundId),
  );

  Future<void> finishRound(String roundId) =>
      (update(rounds)..where((r) => r.id.equals(roundId))).write(
        RoundsCompanion(finishedAt: Value(DateTime.now())),
      );

  Future<List<Answer>> answersForRound(String roundId) =>
      (select(answers)
            ..where((a) => a.roundId.equals(roundId))
            ..orderBy([(_) => OrderingTerm.asc(_rowid)]))
          .get();

  /// Best tier per answered street in [cityId], from answers created before
  /// [before] when given.
  // ponytail: reads the city's answer log; aggregate in SQL past ~100k answers.
  Future<Map<String, Tier>> bestTierByStreet(
    String cityId, {
    DateTime? before,
  }) async {
    final query = select(answers).join([
      innerJoin(rounds, rounds.id.equalsExp(answers.roundId)),
    ])..where(rounds.cityId.equals(cityId));
    if (before != null) {
      query.where(answers.createdAt.isSmallerThanValue(before));
    }
    final best = <String, Tier>{};
    for (final row in await query.get()) {
      final a = row.readTable(answers);
      final current = best[a.streetId];
      if (current == null || a.tier.index < current.index) {
        best[a.streetId] = a.tier;
      }
    }
    return best;
  }

  /// Street ids planned in the [count] most recent rounds of [cityId].
  Future<Set<String>> askedInLastRounds(String cityId, {int count = 3}) async {
    final recent =
        await (select(rounds)
              ..where((r) => r.cityId.equals(cityId))
              ..orderBy([(_) => OrderingTerm.desc(_rowid)])
              ..limit(count))
            .map((r) => r.id)
            .get();
    return {
      for (final q in await (select(
        roundQuestions,
      )..where((q) => q.roundId.isIn(recent))).get())
        q.streetId,
    };
  }

  /// The round's planned street ids answered Close or Miss, in position order.
  Future<List<String>> retrySet(String roundId) async {
    final progress = await roundProgress(roundId);
    final missed = {
      for (final a in progress.answers)
        if (a.tier == Tier.close || a.tier == Tier.miss) a.streetId,
    };
    return [
      for (final id in progress.planned)
        if (missed.contains(id)) id,
    ];
  }
}

/// Overridden in main() and in tests.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);
