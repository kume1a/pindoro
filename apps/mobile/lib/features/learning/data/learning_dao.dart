import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

part 'learning_dao.g.dart';

/// The learning cards, the append-only review log and the mix-up pairs
/// (docs/learning/SPEC.md §2.2). pindoro_learning decides every change; this
/// only maps rows and writes them.
@DriftAccessor(
  tables: [
    CardStates,
    ReviewLogs,
    Confusions,
    LearnCities,
    LandmarkPersonal,
    ImplicitEvidence,
    Runs,
    TurnOverrides,
  ],
)
class LearningDao extends DatabaseAccessor<AppDatabase>
    with _$LearningDaoMixin {
  LearningDao(super.attachedDatabase);

  Future<List<CardState>> cards() async => [
    for (final row in await select(cardStates).get()) _card(row),
  ];

  Future<CardState?> card(String itemId) async {
    final row = await (select(
      cardStates,
    )..where((c) => c.itemId.equals(itemId))).getSingleOrNull();
    return row == null ? null : _card(row);
  }

  /// Saves a card without a graded answer (an intro).
  Future<void> putCard(CardState card) =>
      into(cardStates).insertOnConflictUpdate(_row(card));

  /// Saves cards without graded answers in one batch (carried-over streets).
  Future<void> putCards(Iterable<CardState> cards) => batch(
    (b) => b.insertAllOnConflictUpdate(cardStates, [
      for (final card in cards) _row(card),
    ]),
  );

  /// Saves one answer at once: the card's new state (none for an answer that
  /// schedules nothing, like a pretest), its log row and, for a mix-up, the
  /// confused pair.
  Future<void> saveAnswer({
    required LogEntry log,
    CardState? card,
    ({String target, String hit})? mixUp,
  }) => transaction(() async {
    if (card != null) await putCard(card);
    await into(reviewLogs).insert(_logRow(log));
    if (mixUp != null) {
      await into(confusions).insert(
        ConfusionsCompanion.insert(
          streetA: mixUp.target,
          streetB: mixUp.hit,
          lastAt: log.ts,
        ),
        onConflict: DoUpdate(
          (old) => ConfusionsCompanion.custom(
            count: old.count + const Constant(1),
            lastAt: Variable(log.ts),
          ),
        ),
      );
    }
  });

  /// Every logged confusion as (target, the street the pin hit).
  Future<List<(String, String)>> confusionPairs() async => [
    for (final row in await select(confusions).get())
      (row.streetA, row.streetB),
  ];

  /// Confusions last logged from [from] until [to], latest first, as
  /// (target, the street the pin hit).
  Future<List<(String, String)>> confusionsBetween(
    DateTime from,
    DateTime to,
  ) async => [
    for (final row
        in await (select(confusions)
              ..where(
                (c) =>
                    c.lastAt.isBiggerOrEqualValue(from) &
                    c.lastAt.isSmallerThanValue(to),
              )
              ..orderBy([(c) => OrderingTerm.desc(c.lastAt)]))
            .get())
      (row.streetA, row.streetB),
  ];

  /// The review log, oldest first; from [since] when given.
  Future<List<LogEntry>> log({DateTime? since}) async {
    final query = select(reviewLogs)..orderBy([(l) => OrderingTerm.asc(l.id)]);
    if (since != null) query.where((l) => l.ts.isBiggerOrEqualValue(since));
    return [for (final row in await query.get()) _log(row)];
  }

  /// The street [streetId] was most often mixed up with, either way round;
  /// null with none.
  Future<String?> topConfusion(String streetId) async {
    final rows =
        await (select(confusions)
              ..where(
                (c) => c.streetA.equals(streetId) | c.streetB.equals(streetId),
              )
              ..orderBy([
                (c) => OrderingTerm.desc(c.count),
                (c) => OrderingTerm.desc(c.lastAt),
              ])
              ..limit(1))
            .get();
    return switch (rows) {
      [final row] => row.streetA == streetId ? row.streetB : row.streetA,
      _ => null,
    };
  }

  /// [cityId]'s placement and anchors; null before either.
  Future<LearnCityRow?> learnCity(String cityId) => (select(
    learnCities,
  )..where((c) => c.cityId.equals(cityId))).getSingleOrNull();

  /// Placement ended, or the player started from zero.
  Future<void> markPlaced(String cityId, DateTime at) =>
      into(learnCities).insert(
        LearnCitiesCompanion.insert(cityId: cityId, placedAt: Value(at)),
        onConflict: DoUpdate((_) => LearnCitiesCompanion(placedAt: Value(at))),
      );

  /// Sets the home or work neighbourhood ([anchor]) to [chunkId].
  Future<void> setAnchor(String cityId, Anchor anchor, String chunkId) {
    final row = switch (anchor) {
      Anchor.home => LearnCitiesCompanion(homeId: Value(chunkId)),
      Anchor.work => LearnCitiesCompanion(workId: Value(chunkId)),
    };
    return into(learnCities).insert(
      row.copyWith(cityId: Value(cityId)),
      onConflict: DoUpdate((_) => row),
    );
  }

  /// The player's own landmarks, newest first (SPEC §9).
  Future<List<PersonalLandmarkRow>> personalLandmarks() =>
      (select(landmarkPersonal)..orderBy([
            (l) => OrderingTerm.desc(l.createdAt),
            (l) => OrderingTerm.desc(l.id),
          ]))
          .get();

  Future<void> savePersonalLandmark(PersonalLandmarkRow landmark) =>
      into(landmarkPersonal).insertOnConflictUpdate(landmark);

  Future<void> deletePersonalLandmark(String id) =>
      (delete(landmarkPersonal)..where((l) => l.id.equals(id))).go();

  /// A recital's or drive's outcome at once (SPEC §4): its own answer ([log] and [card], none
  /// for a drive), every decision's [evidence] row and the J card [reviews] the near-due
  /// failures make.
  Future<void> saveTest({
    LogEntry? log,
    CardState? card,
    required ReviewSource source,
    required DateTime at,
    required List<({String itemId, bool ok})> evidence,
    required List<({CardState card, LogEntry log})> reviews,
  }) => transaction(() async {
    if (card != null) await putCard(card);
    if (log != null) await into(reviewLogs).insert(_logRow(log));
    await batch((b) {
      b.insertAll(implicitEvidence, [
        for (final e in evidence)
          ImplicitEvidenceCompanion.insert(
            itemId: e.itemId,
            ts: at,
            source: source,
            outcome: e.ok ? 1 : 0,
          ),
      ]);
      b.insertAllOnConflictUpdate(cardStates, [
        for (final r in reviews) _row(r.card),
      ]);
      b.insertAll(reviewLogs, [for (final r in reviews) _logRow(r.log)]);
    });
  });

  /// The recitals' runs, oldest first (SPEC §16.7).
  Future<List<Run>> recitalRuns() async => [
    for (final r in await (select(
      runs,
    )..orderBy([(r) => OrderingTerm.asc(r.createdAt)])).get())
      (
        id: r.id,
        fromNode: r.fromNode,
        toNode: r.toNode,
        random: r.random,
        items: r.items.isEmpty ? const <String>[] : r.items.split(' '),
        createdAt: r.createdAt,
      ),
  ];

  Future<void> saveRun(Run run) => into(runs).insertOnConflictUpdate(
    RunRow(
      id: run.id,
      fromNode: run.fromNode,
      toNode: run.toNode,
      random: run.random,
      items: run.items.join(' '),
      createdAt: run.createdAt,
    ),
  );

  /// The moves the player reported as legal (`oneway:…`, `turn:…`).
  Future<Set<String>> reportedMoves() async => {
    for (final r in await select(turnOverrides).get()) r.id,
  };

  Future<void> reportMove(String id, DateTime at) => into(
    turnOverrides,
  ).insertOnConflictUpdate(TurnOverrideRow(id: id, createdAt: at));

  static CardState _card(CardStateRow r) => CardState(
    itemId: r.itemId,
    phase: r.state,
    memory: r.stability == null
        ? null
        : Memory(
            stability: r.stability!,
            difficulty: r.difficulty!,
            lastReview: r.lastReviewAt!,
          ),
    dueAt: r.dueAt,
    reps: r.reps,
    lapses: r.lapses,
    lastRating: _rating(r.lastRating),
    lastDistanceM: r.lastDistanceM,
    lastSnapId: r.lastSnapId,
    priorKnown: r.priorKnown,
    introAt: r.introAt,
    note: r.note,
  );

  static CardStateRow _row(CardState c) => CardStateRow(
    itemId: c.itemId,
    type: _typeKey(c.type),
    state: c.phase,
    stability: c.memory?.stability,
    difficulty: c.memory?.difficulty,
    lastReviewAt: c.memory?.lastReview,
    dueAt: c.dueAt,
    reps: c.reps,
    lapses: c.lapses,
    lastRating: c.lastRating?.grade,
    lastDistanceM: c.lastDistanceM,
    lastSnapId: c.lastSnapId,
    priorKnown: c.priorKnown,
    introAt: c.introAt,
    note: c.note,
  );

  static ReviewLogsCompanion _logRow(LogEntry l) => ReviewLogsCompanion.insert(
    ts: l.ts,
    itemId: l.itemId,
    type: _typeKey(l.type),
    format: l.format,
    rating: l.rating.grade,
    source: l.source,
    distanceM: Value(l.distanceM),
    snapId: Value(l.snapId),
    rtMs: Value(l.rtMs),
    elapsedDays: Value(l.elapsedDays),
    rBefore: Value(l.rBefore),
    sBefore: Value(l.sBefore),
    dBefore: Value(l.dBefore),
    sessionId: Value(l.sessionId),
  );

  static LogEntry _log(ReviewLogRow r) => LogEntry(
    ts: r.ts,
    itemId: r.itemId,
    format: r.format,
    rating: _rating(r.rating)!,
    source: r.source,
    distanceM: r.distanceM,
    snapId: r.snapId,
    rtMs: r.rtMs,
    elapsedDays: r.elapsedDays,
    rBefore: r.rBefore,
    sBefore: r.sBefore,
    dBefore: r.dBefore,
    sessionId: r.sessionId,
  );

  static Rating? _rating(int? grade) =>
      grade == null ? null : Rating.values[grade - 1];

  /// SPEC §2.2 writes types upper case: `P`, `S1`, …
  static String _typeKey(CardType type) => type.name.toUpperCase();
}

/// The neighbourhoods new streets start in (SPEC §6.3).
enum Anchor { home, work }

final learningDaoProvider = Provider<LearningDao>(
  (ref) => LearningDao(ref.watch(databaseProvider)),
);
