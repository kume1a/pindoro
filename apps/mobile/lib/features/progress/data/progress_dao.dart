import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

part 'progress_dao.g.dart';

const _rowid = CustomExpression<int>('rowid');

typedef RoundProgress = ({
  Round round,
  List<String> planned,
  List<Answer> answers,
});

extension AnswerLog on Iterable<Answer> {
  /// The answers to [streetIds]: a resumed round plays on without the
  /// streets retired from the pack since.
  Iterable<Answer> to(Set<String> streetIds) =>
      where((a) => streetIds.contains(a.streetId));
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
}

/// Explore rounds, the append-only answer log, the days that counted and the
/// badges: what the player has played, and the rules read from it (saved
/// round, retry set, recent streets).
@DriftAccessor(
  tables: [
    Rounds,
    Answers,
    RoundQuestions,
    GoalDays,
    LegacyKnown,
    LearnCities,
    ReviewLogs,
    Badges,
  ],
)
class ProgressDao extends DatabaseAccessor<AppDatabase>
    with _$ProgressDaoMixin {
  ProgressDao(super.attachedDatabase);

  /// Distinct cities of past rounds, most recent first, then the cities
  /// placed or started from zero.
  Future<List<String>> recentCityIds() async => {
    for (final r in await (select(
      rounds,
    )..orderBy([(_) => OrderingTerm.desc(_rowid)])).get())
      r.cityId,
    for (final c in await select(learnCities).get()) c.cityId,
  }.toList();

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

  /// The latest finished round in [cityId]; null before any.
  Future<Round?> lastFinishedRound(String cityId) =>
      (select(rounds)
            ..where((r) => r.cityId.equals(cityId) & r.finishedAt.isNotNull())
            ..orderBy([(_) => OrderingTerm.desc(_rowid)])
            ..limit(1))
          .getSingleOrNull();

  /// Welcome shows until the player finished a round or placed a city (or
  /// started one from zero).
  Future<bool> hasPlayed() async =>
      await (select(rounds)
                ..where((r) => r.finishedAt.isNotNull())
                ..limit(1))
              .getSingleOrNull() !=
          null ||
      await (select(learnCities)..limit(1)).getSingleOrNull() != null;

  /// When play began: the first round's start or the first learning answer.
  /// Null before either.
  Future<DateTime?> firstPlayedAt() async {
    final round = rounds.startedAt.min();
    final logged = reviewLogs.ts.min();
    final times = [
      (await (selectOnly(rounds)..addColumns([round])).getSingle()).read(round),
      (await (selectOnly(
        reviewLogs,
      )..addColumns([logged])).getSingle()).read(logged),
    ].nonNulls;
    return times.isEmpty ? null : times.reduce((a, b) => a.isBefore(b) ? a : b);
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

  /// Appends one answer to the log (the `answer_immutable` trigger keeps it); no [pin] and
  /// no [distanceM] for "I don't know".
  Future<Answer> recordAnswer({
    required String roundId,
    required String streetId,
    required LatLng? pin,
    required double? distanceM,
    required Tier tier,
    required String packVersion,
  }) => into(answers).insertReturning(
    AnswersCompanion.insert(
      roundId: roundId,
      streetId: streetId,
      pinLat: Value(pin?.lat),
      pinLon: Value(pin?.lon),
      distanceM: Value(distanceM),
      tier: tier,
      packVersion: packVersion,
    ),
  );

  /// The answer-log counts badges read (pindoro_learning `BadgeStats`): pins
  /// dropped in Explore rounds and in sessions and placement (Explore's own
  /// log rows aside), the Explore Perfects, whether any answer came before
  /// [LearningConfig.nightOwlBefore] local time, and the days that counted.
  Future<({int pins, int perfects, bool lateAnswer, int goalDays})>
  badgeCounts() async {
    // Dates are ISO-8601 text with their offset; SQLite converts to local.
    String hour(String column) =>
        "CAST(strftime('%H', $column, 'localtime') AS INTEGER)";
    final row = await customSelect(
      'SELECT '
      '(SELECT COUNT(*) FROM answer WHERE pin_lat IS NOT NULL) + '
      '(SELECT COUNT(*) FROM review_log '
      "WHERE distance_m IS NOT NULL AND source <> 'explore') AS pins, "
      "(SELECT COUNT(*) FROM answer WHERE tier = 'perfect') AS perfects, "
      'EXISTS (SELECT 1 FROM answer WHERE ${hour('created_at')} < ?1) OR '
      'EXISTS (SELECT 1 FROM review_log WHERE ${hour('ts')} < ?1) AS late, '
      '(SELECT COUNT(*) FROM goal_day) AS days',
      variables: [Variable(LearningConfig.nightOwlBefore)],
      readsFrom: {answers, reviewLogs, goalDays},
    ).getSingle();
    return (
      pins: row.read<int>('pins'),
      perfects: row.read<int>('perfects'),
      lateAnswer: row.read<bool>('late'),
      goalDays: row.read<int>('days'),
    );
  }

  Future<Map<String, BadgeRow>> earnedBadges() async => {
    for (final b in await select(badges).get()) b.id: b,
  };

  Future<bool> hasBadges() async =>
      await (select(badges)..limit(1)).getSingleOrNull() != null;

  /// Saves [ids] as earned [now]; returns those that weren't saved yet, in
  /// [ids]' order (two awards at once never both get one).
  Future<List<String>> earn(List<String> ids, DateTime now) =>
      transaction(() async {
        final earned = <String>[];
        for (final id in ids) {
          final row = await into(badges).insertReturningOrNull(
            BadgesCompanion.insert(id: id, earnedAt: now),
            mode: InsertMode.insertOrIgnore,
          );
          if (row != null) earned.add(id);
        }
        return earned;
      });

  /// Marks [ids] seen [now] (a reward sheet closed, or Me showed them).
  Future<void> seeBadges(Iterable<String> ids, DateTime now) =>
      (update(badges)..where((b) => b.id.isIn(ids) & b.seenAt.isNull())).write(
        BadgesCompanion(seenAt: Value(now)),
      );

  /// The earned badges not seen yet, marked seen [now]: Me's New ones for a
  /// visit.
  Future<Set<String>> takeUnseenBadges(DateTime now) => transaction(() async {
    final ids = {
      for (final b in await (select(
        badges,
      )..where((b) => b.seenAt.isNull())).get())
        b.id,
    };
    await seeBadges(ids, now);
    return ids;
  });

  /// The last pin distance of each of [streetIds] in [cityId], from Explore
  /// (except the round [exceptRoundId]); none when that answer was "I don't know".
  Future<Map<String, double>> lastDistances(
    String cityId,
    Iterable<String> streetIds, {
    String? exceptRoundId,
  }) async {
    final ids = streetIds.toList();
    final freePlay =
        select(
            answers,
          ).join([innerJoin(rounds, rounds.id.equalsExp(answers.roundId))])
          ..where(
            rounds.cityId.equals(cityId) &
                answers.streetId.isIn(ids) &
                (exceptRoundId == null
                    ? const Constant(true)
                    : answers.roundId.equals(exceptRoundId).not()),
          )
          ..orderBy([OrderingTerm.asc(answers.createdAt)]);
    // The last answer wins; an "I don't know" has no distance to show.
    final last = {
      for (final row in await freePlay.get())
        if (row.readTable(answers) case final a) a.streetId: a.distanceM,
    };
    return {for (final MapEntry(:key, :value) in last.entries) key: ?value};
  }

  /// Every day that counted towards the streak, with the Explore round whose
  /// answer made it count (null for a session).
  Future<Map<DateTime, String?>> goalDayRounds() async => {
    for (final g in await select(goalDays).get())
      parseDayKey(g.date): g.roundId,
  };

  /// Marks the day of [now] as counted (SPEC §8); the first answer to get
  /// there keeps the mark.
  Future<void> markDay(DateTime now, {String? roundId}) =>
      into(goalDays).insert(
        GoalDaysCompanion.insert(
          date: dayKey(calendarDay(now)),
          roundId: Value(roundId),
        ),
        mode: InsertMode.insertOrIgnore,
      );

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
    final sameArea = parseArea(round.areaJson) == area;
    return sameCity && sameArea ? round : null;
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

  /// How far the pin was the last time each of [roundId]'s streets was
  /// answered outside that round, in its city (the plate's "you were 1.2 km
  /// away" in retry rounds).
  Future<Map<String, double>> previousDistances(String roundId) async {
    final progress = await roundProgress(roundId);
    return lastDistances(
      progress.round.cityId,
      progress.planned,
      exceptRoundId: roundId,
    );
  }

  /// Best tier per answered part id in [cityId], from Explore answers before
  /// [before] when given, with the old game's lesson knowledge (kept as
  /// [LegacyKnown]) as Great.
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
    final legacy = before != null
        ? const <LegacyKnownRow>[]
        : await (select(
            legacyKnown,
          )..where((k) => k.cityId.equals(cityId))).get();
    return bestTiers([
      for (final row in await query.get())
        if (row.readTable(answers) case final a) (a.streetId, a.tier),
      for (final k in legacy) (k.streetId, Tier.great),
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

/// Ticks whenever a round, answer, learning answer, counted day or badge is
/// written, so screens showing progress reload even when they stayed in the
/// navigator during play.
final progressChangesProvider = StreamProvider<Set<TableUpdate>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.tableUpdates(
    TableUpdateQuery.onAllTables([
      db.rounds,
      db.answers,
      db.goalDays,
      db.reviewLogs,
      db.badges,
    ]),
  );
});
