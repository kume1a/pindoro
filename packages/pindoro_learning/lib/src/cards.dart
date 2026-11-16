import 'dart:math';

import 'constants.dart';
import 'fsrs.dart';
import 'grader.dart';
import 'tuning.dart';

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

  /// An Explore answer that schedules nothing (SPEC §16.16).
  exploreLog,

  /// A name card, self-graded or (every [LearningConfig.nameCheckEvery]th) checked with a choice.
  name,
  nameCheck,
  extent,

  /// A child's pin card graded by the family sweep (SPEC §7).
  familySweep,
  crossings,
  bearing,

  /// Route cards (SPEC §3): turns, gateways, bridges, connections, landmarks.
  junction,
  gateway,
  bridge,
  connection,
  landmark,

  /// A recital (an R card in a session), or a J card's Again from a recital decision (SPEC §4).
  recital,

  /// A J card's Again from a decision on a GPS-free drive (SPEC §4).
  drive;

  /// Drill answers that are only logged (SPEC §16.10): they move no card.
  bool get logsOnly => this == crossings || this == bearing;
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
    this.note,
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

  /// The player's own memory aid for a leech (SPEC §4).
  final String? note;

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

/// A leech shown again (SPEC §4, §16.13): a fresh intro with the street beside its top confusion
/// and the player's [note], then due at once, so the session's retrievals relearn it on its
/// kept memory.
CardState reintroduce(CardState leech, DateTime now, {String? note}) =>
    CardState(
      itemId: leech.itemId,
      phase: CardPhase.relearning,
      memory: leech.memory,
      dueAt: now,
      reps: leech.reps,
      lapses: leech.lapses,
      lastRating: leech.lastRating,
      lastDistanceM: leech.lastDistanceM,
      lastSnapId: leech.lastSnapId,
      priorKnown: leech.priorKnown,
      introAt: now,
      note: note,
    );

/// A card for a street the old game already knew (PLAN M2 step 7): first sight rated Good and
/// marked prior knowledge, due on a [random] day [LearningConfig.migrationDueMinDays]–
/// [LearningConfig.migrationDueMaxDays] out, so the first reviews spread over a week. No intro and
/// no log row: nothing was answered.
CardState carriedOver(
  String itemId,
  DateTime now,
  Random random, {
  Fsrs fsrs = const Fsrs(),
}) {
  const span =
      LearningConfig.migrationDueMaxDays - LearningConfig.migrationDueMinDays;
  return CardState(
    itemId: itemId,
    phase: CardPhase.review,
    memory: fsrs.next(null, Rating.good, now).memory,
    dueAt: now.add(
      Duration(
        days: LearningConfig.migrationDueMinDays + random.nextInt(span + 1),
      ),
    ),
    reps: 1,
    lastRating: Rating.good,
    priorKnown: true,
  );
}

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
  double? retention,
  Fsrs fsrs = const Fsrs(),
}) {
  final before = card?.memory;
  final scheduled = fsrs.next(
    before,
    rating,
    now,
    retention: retention ?? retentionOf(CardType.ofItem(itemId)),
    fuzz: fuzzFor(itemId, now),
  );
  final lapsed = rating == Rating.again && card?.phase == CardPhase.review;
  final lapses = (card?.lapses ?? 0) + (lapsed ? 1 : 0);
  final next = CardState(
    itemId: itemId,
    phase: switch (rating) {
      _ when lapsed && lapses % LearningConfig.leechLapses == 0 =>
        CardPhase.suspended,
      Rating.again => CardPhase.relearning,
      _ => CardPhase.review,
    },
    memory: scheduled.memory,
    dueAt: scheduled.due,
    reps: (card?.reps ?? 0) + 1,
    lapses: lapses,
    lastRating: rating,
    lastDistanceM: distanceM,
    lastSnapId: snapId,
    priorKnown: (card?.priorKnown ?? false) || priorKnown,
    introAt: card?.introAt,
    note: card?.note,
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

/// An Explore answer (SPEC §16.16): it reviews [card] only when the card is due or near due (due
/// within [LearningConfig.nearDueFraction] of its interval); a first-sight Good or Easy creates the
/// card as known from before, like placement; anything else is only logged.
({CardState? card, LogEntry log}) exploreAnswer(
  CardState? card, {
  required String itemId,
  required PinGrade grade,
  required DateTime now,
  required int rtMs,
  String? sessionId,
}) {
  final reviews = card == null
      ? grade.rating == Rating.good || grade.rating == Rating.easy
      : isNearDue(card, now);
  final applied = applyReview(
    card,
    itemId: itemId,
    rating: grade.rating,
    now: now,
    format: reviews ? ReviewFormat.explore : ReviewFormat.exploreLog,
    source: ReviewSource.explore,
    sessionId: sessionId,
    distanceM: grade.distanceM,
    snapId: grade.snapStreetId,
    rtMs: rtMs,
    priorKnown: card == null,
  );
  return (card: reviews ? applied.card : null, log: applied.log);
}

/// Due or near due at [now]: due within [LearningConfig.nearDueFraction] of its interval (SPEC
/// §4, §16.16).
bool isNearDue(CardState card, DateTime now) {
  final memory = card.memory;
  final dueAt = card.dueAt;
  return memory != null &&
      dueAt != null &&
      dueAt.difference(now).inSeconds <=
          LearningConfig.nearDueFraction *
              dueAt.difference(memory.lastReview).inSeconds;
}

/// What a decision a recital or drive tested does to its J [card] (SPEC §4 implicit evidence): a
/// failure ([ok] false) reviews a reviewed card as Again when it is near due; anything else only
/// leaves the evidence row (null here).
({CardState card, LogEntry log})? implicitReview(
  CardState? card, {
  required bool ok,
  required DateTime now,
  required ReviewSource source,
  String? sessionId,
}) =>
    ok ||
        card == null ||
        card.phase != CardPhase.review ||
        !isNearDue(card, now)
    ? null
    : applyReview(
        card,
        itemId: card.itemId,
        rating: Rating.again,
        now: now,
        format: source == ReviewSource.drive
            ? ReviewFormat.drive
            : ReviewFormat.recital,
        source: source,
        sessionId: sessionId,
      );
