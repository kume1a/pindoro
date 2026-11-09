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
}

extension ReviewItemState on ReviewItem {
  ReviewState get state =>
      (step: step, greatRun: greatRun, dueOn: parseDayKey(dueOn));

  /// Due on or before the calendar day [today].
  bool dueBy(DateTime today) => !parseDayKey(dueOn).isAfter(today);
}

extension PitStopItems on Iterable<ReviewItem> {
  /// Items due by [today] whose street is still in the pack's [streets].
  Iterable<ReviewItem> dueIn(
    Map<String, NamedStreet> streets,
    DateTime today,
  ) => where((i) => i.dueBy(today) && streets.containsKey(i.streetId));
}

/// Rounds, the append-only answer log, goal-met days and the Pit stop: what
/// the player has played, and the rules read from it (saved round, retry set,
/// recent streets, the daily goal, streets to review).
@DriftAccessor(
  tables: [
    Rounds,
    Answers,
    RoundQuestions,
    GoalDays,
    UserSettings,
    ReviewItems,
    Courses,
    LessonResults,
    LessonAnswers,
  ],
)
class ProgressDao extends DatabaseAccessor<AppDatabase>
    with _$ProgressDaoMixin {
  ProgressDao(super.attachedDatabase);

  /// Distinct cities of past rounds, most recent first, then the cities
  /// played only in lessons.
  Future<List<String>> recentCityIds() async {
    final ids = <String>{};
    for (final r in await (select(
      rounds,
    )..orderBy([(_) => OrderingTerm.desc(_rowid)])).get()) {
      ids.add(r.cityId);
    }
    for (final r in await (select(
      lessonResults,
    )..orderBy([(r) => OrderingTerm.desc(r.finishedAt)])).get()) {
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

  /// Welcome shows until the player finishes a first round or lesson.
  Future<bool> hasPlayed() async =>
      await (select(rounds)
                ..where((r) => r.finishedAt.isNotNull())
                ..limit(1))
              .getSingleOrNull() !=
          null ||
      await (select(lessonResults)..limit(1)).getSingleOrNull() != null;

  /// When play began: the first round's start or the first lesson's end.
  /// Null before either.
  Future<DateTime?> firstPlayedAt() async {
    final round = rounds.startedAt.min();
    final lesson = lessonResults.finishedAt.min();
    final times = [
      (await (selectOnly(rounds)..addColumns([round])).getSingle()).read(round),
      (await (selectOnly(
        lessonResults,
      )..addColumns([lesson])).getSingle()).read(lesson),
    ].nonNulls;
    return times.isEmpty ? null : times.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  /// Every answer's XP plus every lesson result's.
  Future<int> totalXp() async {
    final answered = answers.xp.sum();
    final learned = lessonResults.xp.sum();
    return ((await (selectOnly(
              answers,
            )..addColumns([answered])).getSingle()).read(answered) ??
            0) +
        ((await (selectOnly(
              lessonResults,
            )..addColumns([learned])).getSingle()).read(learned) ??
            0);
  }

  /// Inserts the round and its planned streets atomically; returns the round id.
  Future<String> startRound({
    required String cityId,
    required Area area,
    required Difficulty difficulty,
    required String packVersion,
    required List<String> streetIds,
    String? retryOf,
    bool pitStop = false,
  }) => transaction(() async {
    final round = await into(rounds).insertReturning(
      RoundsCompanion.insert(
        cityId: cityId,
        areaJson: jsonEncode(area.toJson()),
        difficulty: difficulty,
        packVersion: packVersion,
        retryOf: Value(retryOf),
        pitStop: Value(pitStop),
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

  /// Appends one answer to the log (the `answer_immutable` trigger keeps it),
  /// moves its street in the Pit stop, and marks today when this answer
  /// reached the daily goal.
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
    final city = await (select(
      rounds,
    )..where((r) => r.id.equals(roundId))).map((r) => r.cityId).getSingle();
    await _review(city, streetId, tier, answer.createdAt);
    await markGoalIfMet(answer.createdAt, roundId: roundId);
    return answer;
  });

  /// Applies a [tier] answered [at] to [streetId]'s place in [cityId]'s Pit
  /// stop.
  Future<void> _review(
    String cityId,
    String streetId,
    Tier tier,
    DateTime at,
  ) async {
    Expression<bool> isItem(ReviewItems r) =>
        r.cityId.equals(cityId) & r.streetId.equals(streetId);
    final current = await (select(
      reviewItems,
    )..where(isItem)).getSingleOrNull();
    final next = nextReview(current?.state, tier, calendarDay(at));
    if (next == null) {
      await (delete(reviewItems)..where(isItem)).go();
      return;
    }
    await into(reviewItems).insertOnConflictUpdate(
      ReviewItemsCompanion.insert(
        cityId: cityId,
        streetId: streetId,
        step: next.step,
        greatRun: next.greatRun,
        dueOn: dayKey(next.dueOn),
        lastTier: tier,
        lastAt: at,
      ),
    );
  }

  /// Saves a finished lesson: its result, its answers and the [reviews] the
  /// Pit stop takes (pindoro_core `reviewAnswers`), then marks today when it
  /// reached the daily goal. Returns the result's id.
  Future<String> finishLesson({
    required String cityId,
    required String unitId,
    required LessonKind kind,
    required int? lesson,
    required Difficulty difficulty,
    required LessonRun run,
    required DateTime startedAt,
    required List<({String streetId, Tier tier})> reviews,
  }) => transaction(() async {
    final now = DateTime.now();
    final result = await into(lessonResults).insertReturning(
      LessonResultsCompanion.insert(
        cityId: cityId,
        unitId: unitId,
        kind: kind,
        lesson: Value(lesson),
        difficulty: difficulty,
        xp: run.xp,
        perfect: run.perfect,
        rightFirst: run.rightFirst,
        tests: run.tests,
        durationMs: now.difference(startedAt).inMilliseconds,
        finishedAt: Value(now),
      ),
    );
    await batch(
      (b) => b.insertAll(lessonAnswers, [
        for (final (i, a) in run.answers.indexed)
          LessonAnswersCompanion.insert(
            resultId: result.id,
            position: i,
            streetId: a.step.street.id,
            kind: a.step is NameStep
                ? LessonAnswerKind.name
                : LessonAnswerKind.pin,
            tier: a.tier,
            xp: a.xp,
            fix: a.step.fix,
            distanceM: Value(a.distanceM),
          ),
      ]),
    );
    for (final r in reviews) {
      await _review(cityId, r.streetId, r.tier, now);
    }
    await markGoalIfMet(now);
    return result.id;
  });

  Future<String?> courseStart(String cityId) =>
      (select(courses)..where((c) => c.cityId.equals(cityId)))
          .map((c) => c.startDistrictId)
          .getSingleOrNull();

  Future<void> saveCourseStart(String cityId, String districtId) =>
      into(courses).insertOnConflictUpdate(
        CoursesCompanion.insert(cityId: cityId, startDistrictId: districtId),
      );

  /// The area of [cityId]'s most recent round; null before one.
  Future<Area?> lastRoundArea(String cityId) async => parseArea(
    await (select(rounds)
          ..where((r) => r.cityId.equals(cityId))
          ..orderBy([(_) => OrderingTerm.desc(_rowid)])
          ..limit(1))
        .map((r) => r.areaJson)
        .getSingleOrNull(),
  );

  /// [cityId]'s lesson results, oldest first.
  Future<List<LessonResult>> lessonResultsIn(String cityId) =>
      (select(lessonResults)
            ..where((r) => r.cityId.equals(cityId))
            ..orderBy([(r) => OrderingTerm.asc(r.finishedAt)]))
          .get();

  Future<LessonResult> lessonResult(String id) =>
      (select(lessonResults)..where((r) => r.id.equals(id))).getSingle();

  /// [cityId]'s first-try mistakes in [unitId]'s lessons up to
  /// [throughLesson], in the order they happened, each street once: what the
  /// unit's Pit stop tunes up.
  Future<List<String>> unitMistakes(
    String cityId,
    String unitId, {
    required int throughLesson,
  }) async {
    final query =
        select(lessonAnswers).join([
            innerJoin(
              lessonResults,
              lessonResults.id.equalsExp(lessonAnswers.resultId),
            ),
          ])
          ..where(
            lessonResults.cityId.equals(cityId) &
                lessonResults.unitId.equals(unitId) &
                lessonResults.kind.equalsValue(LessonKind.lesson) &
                lessonResults.lesson.isSmallerOrEqualValue(throughLesson) &
                lessonAnswers.fix.equals(false) &
                lessonAnswers.tier.isInValues([Tier.close, Tier.miss]),
          )
          ..orderBy([
            OrderingTerm.asc(lessonResults.finishedAt),
            OrderingTerm.asc(lessonAnswers.position),
          ]);
    return {
      for (final row in await query.get())
        row.readTable(lessonAnswers).streetId,
    }.toList();
  }

  /// The last pin distance of each of [streetIds] in [cityId], from Free play
  /// and lessons.
  Future<Map<String, double>> lastDistances(
    String cityId,
    Iterable<String> streetIds,
  ) async {
    final ids = streetIds.toList();
    final freePlay =
        select(
            answers,
          ).join([innerJoin(rounds, rounds.id.equalsExp(answers.roundId))])
          ..where(rounds.cityId.equals(cityId) & answers.streetId.isIn(ids))
          ..orderBy([OrderingTerm.asc(answers.createdAt)]);
    final lessons =
        select(lessonAnswers).join([
            innerJoin(
              lessonResults,
              lessonResults.id.equalsExp(lessonAnswers.resultId),
            ),
          ])
          ..where(
            lessonResults.cityId.equals(cityId) &
                lessonAnswers.streetId.isIn(ids) &
                lessonAnswers.distanceM.isNotNull(),
          )
          ..orderBy([
            OrderingTerm.asc(lessonResults.finishedAt),
            OrderingTerm.asc(lessonAnswers.position),
          ]);
    final played = <({DateTime at, String id, double m})>[
      for (final row in await freePlay.get())
        if (row.readTable(answers) case final a)
          (at: a.createdAt, id: a.streetId, m: a.distanceM),
      for (final row in await lessons.get())
        if (row.readTable(lessonAnswers) case final a)
          (
            at: row.readTable(lessonResults).finishedAt,
            id: a.streetId,
            m: a.distanceM!,
          ),
    ];
    // Both lists are in time order; merge them, keeping that order on ties.
    final order = List.generate(played.length, (i) => i)
      ..sort((i, j) {
        final byTime = played[i].at.compareTo(played[j].at);
        return byTime != 0 ? byTime : i.compareTo(j);
      });
    return {for (final i in order) played[i].id: played[i].m};
  }

  /// Lessons done (not practice), in every city.
  Future<int> lessonsDone() async {
    final row = await customSelect(
      'SELECT COUNT(*) AS n FROM (SELECT DISTINCT city_id, unit_id, lesson '
      "FROM lesson_result WHERE kind = 'lesson')",
      readsFrom: {lessonResults},
    ).getSingle();
    return row.read<int>('n');
  }

  /// The Pit stop of [cityId], most overdue first.
  Future<List<ReviewItem>> pitStop(String cityId) =>
      (select(reviewItems)
            ..where((r) => r.cityId.equals(cityId))
            ..orderBy([
              (r) => OrderingTerm.asc(r.dueOn),
              (r) => OrderingTerm.asc(r.lastAt),
            ]))
          .get();

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

  /// XP earned on the local calendar [day] (a pindoro_core `calendarDay`):
  /// answers given and lessons finished that day.
  Future<int> xpOn(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    final answered = answers.xp.sum();
    final learned = lessonResults.xp.sum();
    final fromAnswers = selectOnly(answers)
      ..addColumns([answered])
      ..where(
        answers.createdAt.isBiggerOrEqualValue(start) &
            answers.createdAt.isSmallerThanValue(end),
      );
    final fromLessons = selectOnly(lessonResults)
      ..addColumns([learned])
      ..where(
        lessonResults.finishedAt.isBiggerOrEqualValue(start) &
            lessonResults.finishedAt.isSmallerThanValue(end),
      );
    return ((await fromAnswers.getSingle()).read(answered) ?? 0) +
        ((await fromLessons.getSingle()).read(learned) ?? 0);
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

  /// The answers of [cityId]'s most recent finished Pit stop round; empty
  /// before the first one.
  Future<List<Answer>> lastPitStopAnswers(String cityId) async {
    final round =
        await (select(rounds)
              ..where(
                (r) =>
                    r.cityId.equals(cityId) &
                    r.pitStop.equals(true) &
                    r.finishedAt.isNotNull(),
              )
              ..orderBy([(r) => OrderingTerm.desc(r.finishedAt)])
              ..limit(1))
            .getSingleOrNull();
    return round == null ? const [] : answersForRound(round.id);
  }

  /// How far the pin was the last time each of [roundId]'s streets was
  /// answered in another round of its city (the plate's "you were 1.2 km
  /// away" in retry and Pit stop rounds).
  Future<Map<String, double>> previousDistances(String roundId) async {
    final progress = await roundProgress(roundId);
    final query =
        select(
            answers,
          ).join([innerJoin(rounds, rounds.id.equalsExp(answers.roundId))])
          ..where(
            rounds.cityId.equals(progress.round.cityId) &
                answers.roundId.equals(roundId).not() &
                answers.streetId.isIn(progress.planned),
          )
          ..orderBy([OrderingTerm.asc(answers.createdAt)]);
    return {
      for (final row in await query.get())
        if (row.readTable(answers) case final a) a.streetId: a.distanceM,
    };
  }

  /// Best tier per answered part id in [cityId], from answers (and lessons
  /// finished) before [before] when given. A lesson's right name counts only
  /// the first time: a right name fix comes after the answer was shown.
  // ponytail: reads the city's answer log; aggregate in SQL past ~100k answers.
  Future<Map<String, Tier>> bestTierByPart(
    String cityId, {
    DateTime? before,
  }) async {
    final query = select(answers).join([
      innerJoin(rounds, rounds.id.equalsExp(answers.roundId)),
    ])..where(rounds.cityId.equals(cityId));
    final learned = select(lessonAnswers).join([
      innerJoin(
        lessonResults,
        lessonResults.id.equalsExp(lessonAnswers.resultId),
      ),
    ])..where(lessonResults.cityId.equals(cityId));
    if (before != null) {
      query.where(answers.createdAt.isSmallerThanValue(before));
      learned.where(lessonResults.finishedAt.isSmallerThanValue(before));
    }
    bool rightNameFix(LessonAnswer a) =>
        a.kind == LessonAnswerKind.name && a.fix && isKnownTier(a.tier);
    return bestTiers([
      for (final row in await query.get())
        if (row.readTable(answers) case final a) (a.streetId, a.tier),
      for (final row in await learned.get())
        if (row.readTable(lessonAnswers) case final a when !rightNameFix(a))
          (a.streetId, a.tier),
    ]);
  }

  /// Known / total streets of [pack]'s city and its districts, from the
  /// answers before [before] (all of them without it).
  Future<KnownCounts> knownIn(
    PackRepository pack,
    Map<String, NamedStreet> streets, {
    DateTime? before,
  }) async => knownCounts(
    streets: streets,
    partsByDistrict: pack.partsByDistrict(),
    known: knownStreetIds(
      await bestTierByPart(pack.city().id, before: before),
      streets,
    ),
  );

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

/// Ticks whenever a round, answer, goal day, course or lesson is written, so screens showing
/// progress reload even when they stayed in the navigator during the round.
final progressChangesProvider = StreamProvider<Set<TableUpdate>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.tableUpdates(
    TableUpdateQuery.onAllTables([
      db.rounds,
      db.answers,
      db.goalDays,
      db.courses,
      db.lessonResults,
    ]),
  );
});

/// The player's total XP, kept current with progress.
final totalXpProvider = FutureProvider.autoDispose<int>((ref) {
  ref.watch(progressChangesProvider);
  return ref.watch(progressDaoProvider).totalXp();
});
