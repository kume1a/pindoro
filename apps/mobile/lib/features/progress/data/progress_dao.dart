import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';

part 'progress_dao.g.dart';

const _rowid = CustomExpression<int>('rowid');

typedef RoundProgress = ({
  Round round,
  List<String> planned,
  List<Answer> answers,
});

/// Rounds and the append-only answer log: what the player has played, and the
/// rules read from it (saved round, retry set, recent streets).
@DriftAccessor(tables: [Rounds, Answers, RoundQuestions])
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

  /// Appends one answer to the log (the `answer_immutable` trigger keeps it).
  Future<Answer> recordAnswer({
    required String roundId,
    required String streetId,
    required LatLng pin,
    required double distanceM,
    required Tier tier,
    required int xp,
    required String packVersion,
  }) => into(answers).insertReturning(
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
    final settings = await SettingsDao(attachedDatabase).read();
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

final progressDaoProvider = Provider<ProgressDao>(
  (ref) => ProgressDao(ref.watch(databaseProvider)),
);
