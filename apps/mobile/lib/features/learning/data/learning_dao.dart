import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

part 'learning_dao.g.dart';

/// The learning cards, the append-only review log and the mix-up pairs
/// (docs/learning/SPEC.md §2.2). pindoro_learning decides every change; this
/// only maps rows and writes them.
@DriftAccessor(tables: [CardStates, ReviewLogs, Confusions])
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

  /// The review log, oldest first; from [since] when given.
  Future<List<LogEntry>> log({DateTime? since}) async {
    final query = select(reviewLogs)..orderBy([(l) => OrderingTerm.asc(l.id)]);
    if (since != null) query.where((l) => l.ts.isBiggerOrEqualValue(since));
    return [for (final row in await query.get()) _log(row)];
  }

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

final learningDaoProvider = Provider<LearningDao>(
  (ref) => LearningDao(ref.watch(databaseProvider)),
);
