import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro_core/pindoro_core.dart';

part 'progress_dao.g.dart';

const _rowid = CustomExpression<int>('rowid');

typedef RoundProgress = ({
  Round round,
  List<String> planned,
  List<Answer> answers,
});

extension AnswerLog on Iterable<Answer> {
  /// XP these answers earned.
  int get xp => fold(0, (sum, a) => sum + a.xp);
}

extension RoundProgressRules on RoundProgress {
  /// The last answer's time, or the start of a round without answers.
  DateTime get lastActiveAt => answers.lastOrNull?.createdAt ?? round.startedAt;

  /// Planned street ids answered Close or Miss, in position order.
  List<String> get retryIds {
    final missed = {
      for (final a in answers)
        if (isRetryTier(a.tier)) a.streetId,
    };
    return [
      for (final id in planned)
        if (missed.contains(id)) id,
    ];
  }

  /// How far each answer's pin was from its street, by street id.
  Map<String, double> get distanceByStreet => {
    for (final a in answers) a.streetId: a.distanceM,
  };
}

/// Rounds, the append-only answer log and the goal-met days: what the player
/// has played, and the rules read from it (saved round, retry set, recent
/// streets, the daily goal).
@DriftAccessor(
  tables: [Rounds, Answers, RoundQuestions, GoalDays, UserSettings],
)
class ProgressDao extends DatabaseAccessor<AppDatabase>
    with _$ProgressDaoMixin {
  ProgressDao(super.attachedDatabase);

  /// Distinct cities of past rounds, most recent first.
  Future<List<String>> recentCityIds() async {
    final ids = <String>{};
    for (final r in await (select(
      rounds,
    )..orderBy([(_) => OrderingTerm.desc(_rowid)])).get()) {
      ids.add(r.cityId);
    }
    return ids.toList();
  }

  /// District ids of past rounds in [cityId], most recently played first.
  Future<List<String>> recentDistrictIds(String cityId) async {
    final ids = <String>{};
    for (final r
        in await (select(rounds)
              ..where((r) => r.cityId.equals(cityId))
              ..orderBy([(_) => OrderingTerm.desc(_rowid)]))
            .get()) {
      if (parseArea(r.areaJson) case DistrictsArea(ids: final picked)) {
        ids.addAll(picked);
      }
    }
    return ids.toList();
  }

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

  /// Appends one answer to the log (the `answer_immutable` trigger keeps it)
  /// and marks today when this answer reached the daily goal.
  Future<Answer> recordAnswer({
    required String roundId,
    required String streetId,
    required LatLng pin,
    required double distanceM,
    required Tier tier,
    required int xp,
    required String packVersion,
  }) => transaction(() async {
    final answer = await into(answers).insertReturning(
      AnswersCompanion.insert(
        roundId: roundId,
        streetId: streetId,
        pinLat: pin.lat,
        pinLon: pin.lon,
        distanceM: distanceM,
        tier: tier,
        xp: xp,
        packVersion: packVersion,
      ),
    );
    await markGoalIfMet(answer.createdAt, roundId: roundId);
    return answer;
  });

  /// Marks the day of [now] once its XP reaches the daily goal; the round
  /// that got there first keeps the mark.
  Future<void> markGoalIfMet(DateTime now, {String? roundId}) async {
    final day = calendarDay(now);
    if (await xpOn(day) < await _dailyGoal()) return;
    await into(goalDays).insert(
      GoalDaysCompanion.insert(date: dayKey(day), roundId: Value(roundId)),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<int> _dailyGoal() async =>
      (await (select(
        userSettings,
      )..where((s) => s.id.equals(1))).getSingleOrNull())?.dailyGoal ??
      StreakRules.defaultGoal;

  /// XP earned on the local calendar [day] (a pindoro_core `calendarDay`).
  Future<int> xpOn(DateTime day) async {
    final sum = answers.xp.sum();
    final query = selectOnly(answers)
      ..addColumns([sum])
      ..where(
        answers.createdAt.isBiggerOrEqualValue(
              DateTime(day.year, day.month, day.day),
            ) &
            answers.createdAt.isSmallerThanValue(
              DateTime(day.year, day.month, day.day + 1),
            ),
      );
    return (await query.getSingle()).read(sum) ?? 0;
  }

  /// Every goal-met day with the round that reached the goal (null when
  /// lowering the goal did).
  Future<Map<DateTime, String?>> goalDayRounds() async => {
    for (final g in await select(goalDays).get())
      parseDayKey(g.date): g.roundId,
  };

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

  /// [resumableRound] when it was played in the chosen [cityId] (any city
  /// before one is chosen) and [area].
  Future<Round?> savedRound(
    DateTime now, {
    required String? cityId,
    required Area? area,
  }) async {
    final round = await resumableRound(now);
    if (round == null) return null;
    final sameCity = cityId == null || cityId == round.cityId;
    return sameCity && parseArea(round.areaJson) == area ? round : null;
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

  /// Stamps the round finished; a finished round keeps its first stamp.
  Future<void> finishRound(String roundId) =>
      (update(rounds)
            ..where((r) => r.id.equals(roundId) & r.finishedAt.isNull()))
          .write(RoundsCompanion(finishedAt: Value(DateTime.now())));

  Future<List<Answer>> answersForRound(String roundId) =>
      (select(answers)
            ..where((a) => a.roundId.equals(roundId))
            ..orderBy([(_) => OrderingTerm.asc(_rowid)]))
          .get();

  /// Best tier per answered part id in [cityId], from answers created before
  /// [before] when given.
  // ponytail: reads the city's answer log; aggregate in SQL past ~100k answers.
  Future<Map<String, Tier>> bestTierByPart(
    String cityId, {
    DateTime? before,
  }) async {
    final query = select(answers).join([
      innerJoin(rounds, rounds.id.equalsExp(answers.roundId)),
    ])..where(rounds.cityId.equals(cityId));
    if (before != null) {
      query.where(answers.createdAt.isSmallerThanValue(before));
    }
    return bestTiers([
      for (final row in await query.get())
        if (row.readTable(answers) case final a) (a.streetId, a.tier),
    ]);
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
}

final progressDaoProvider = Provider<ProgressDao>(
  (ref) => ProgressDao(ref.watch(databaseProvider)),
);

/// Ticks whenever a round, answer or goal day is written, so screens showing
/// progress reload even when they stayed in the navigator during the round.
final progressChangesProvider = StreamProvider<Set<TableUpdate>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.tableUpdates(
    TableUpdateQuery.onAllTables([db.rounds, db.answers, db.goalDays]),
  );
});
