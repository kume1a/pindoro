import 'dart:math';

import 'constants.dart';
import 'fsrs.dart';

/// Card types; an item id is `<TYPE>:<key>` (SPEC §3).
enum CardType {
  p,
  n,
  e,
  j,
  g,
  b,
  c,
  l,
  s1,
  s2,
  s3,
  r;

  String item(String key) => '${name.toUpperCase()}:$key';

  static CardType ofItem(String itemId) =>
      values.byName(itemId.substring(0, itemId.indexOf(':')).toLowerCase());
}

/// What follows the type in an item id: a street id, `n123:n456`, …
String itemKey(String itemId) => itemId.substring(itemId.indexOf(':') + 1);

/// `card_state.state` (SPEC §16.4); an unseen item has no row.
enum CardPhase { learning, review, relearning, suspended }

/// `review_log.format` (SPEC §16.10); later milestones add theirs.
enum ReviewFormat {
  placement,
  pretest,
  retrieval1,
  retrieval2,
  review,
  relearn,
  explore,
}

/// `review_log.source` (SPEC §2.2).
enum ReviewSource { session, placement, explore, recital, drive }

/// One `card_state` row (SPEC §2.2).
class CardState {
  const CardState({
    required this.itemId,
    required this.phase,
    this.memory,
    this.dueAt,
    this.reps = 0,
    this.lapses = 0,
    this.lastRating,
    this.lastDistanceM,
    this.lastSnapId,
    this.priorKnown = false,
    this.introAt,
  });

  final String itemId;
  final CardPhase phase;

  /// Null until the first graded answer (an intro alone sets none).
  final Memory? memory;
  final DateTime? dueAt;
  final int reps;
  final int lapses;
  final Rating? lastRating;
  final double? lastDistanceM;
  final String? lastSnapId;

  /// Created by placement or carried over from the old game, not taught.
  final bool priorKnown;
  final DateTime? introAt;

  CardType get type => CardType.ofItem(itemId);
}

/// One append-only `review_log` row (SPEC §2.2).
class LogEntry {
  const LogEntry({
    required this.ts,
    required this.itemId,
    required this.format,
    required this.rating,
    required this.source,
    this.distanceM,
    this.snapId,
    this.rtMs,
    this.elapsedDays,
    this.rBefore,
    this.sBefore,
    this.dBefore,
    this.sessionId,
  });

  final DateTime ts;
  final String itemId;
  final ReviewFormat format;
  final Rating rating;
  final ReviewSource source;
  final double? distanceM;
  final String? snapId;
  final int? rtMs;
  final double? elapsedDays;
  final double? rBefore;
  final double? sBefore;
  final double? dBefore;
  final String? sessionId;

  CardType get type => CardType.ofItem(itemId);
}

/// The intro card: the street is shown, nothing is graded yet (SPEC §16.5).
CardState introduce(String itemId, DateTime now) =>
    CardState(itemId: itemId, phase: CardPhase.learning, introAt: now);

/// Applies a graded answer at [now] to [card] (null: first sight, with no intro) and returns the
/// new card and its log row. Fuzz is seeded by the item and the time, so replays agree.
({CardState card, LogEntry log}) applyReview(
  CardState? card, {
  required String itemId,
  required Rating rating,
  required DateTime now,
  required ReviewFormat format,
  required ReviewSource source,
  String? sessionId,
  double? distanceM,
  String? snapId,
  int? rtMs,
  bool priorKnown = false,
  double retention = LearningConfig.retentionDefault,
  Fsrs fsrs = const Fsrs(),
}) {
  final before = card?.memory;
  final scheduled = fsrs.next(
    before,
    rating,
    now,
    retention: retention,
    fuzz: fuzzFor(itemId, now),
  );
  final lapsed = rating == Rating.again && card?.phase == CardPhase.review;
  final next = CardState(
    itemId: itemId,
    phase: rating == Rating.again ? CardPhase.relearning : CardPhase.review,
    memory: scheduled.memory,
    dueAt: scheduled.due,
    reps: (card?.reps ?? 0) + 1,
    lapses: (card?.lapses ?? 0) + (lapsed ? 1 : 0),
    lastRating: rating,
    lastDistanceM: distanceM,
    lastSnapId: snapId,
    priorKnown: (card?.priorKnown ?? false) || priorKnown,
    introAt: card?.introAt,
  );
  final log = LogEntry(
    ts: now,
    itemId: itemId,
    format: format,
    rating: rating,
    source: source,
    distanceM: distanceM,
    snapId: snapId,
    rtMs: rtMs,
    elapsedDays: before == null
        ? null
        : now.difference(before.lastReview).inMicroseconds /
              Duration.microsecondsPerDay,
    rBefore: before == null ? null : fsrs.retrievability(before, now),
    sBefore: before?.stability,
    dBefore: before?.difficulty,
    sessionId: sessionId,
  );
  return (card: next, log: log);
}

/// A [Random] seeded by FNV-1a of the item and the time: the same review always fuzzes alike.
Random fuzzFor(String itemId, DateTime now) {
  var hash = 0x811c9dc5;
  for (final unit in '$itemId@${now.microsecondsSinceEpoch}'.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return Random(hash);
}
