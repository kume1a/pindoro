import 'dart:math';

import 'cards.dart';
import 'constants.dart';
import 'drive_log.dart';
import 'fsrs.dart';
import 'stats.dart';

/// What the player's past says about one decision (by its key): when it last failed anywhere
/// (a session, a recital or a drive), and on the drives through it, latest first, whether they
/// took it right on their own (no prompt, no recovery).
typedef DecisionHistory = ({DateTime? lastFailure, List<bool> ownDrives});

/// An earlier drive, for the level steps: its level, the decision keys it passed, its stretch
/// (null when it didn't arrive) and its recoveries.
typedef PastDrive = ({
  DriveLevel level,
  Set<String> decisions,
  double? stretch,
  int recoveries,
});

/// Whether a decision may stay silent (SPEC §16.23 item 113): its J [card] Known, recall at
/// least [LearningConfig.silentMinR] and no failure in [LearningConfig.silentNoFailDays]; with
/// no card, taken right on the player's own on the last [LearningConfig.silentOwnDrives] drives
/// through it, and no failure either.
bool silentEligible(
  CardState? card,
  DecisionHistory? history,
  DateTime now, {
  Fsrs fsrs = const Fsrs(),
}) {
  final failed = history?.lastFailure;
  if (failed != null &&
      now.difference(failed).inDays < LearningConfig.silentNoFailDays) {
    return false;
  }
  if (card != null) {
    final memory = card.memory;
    return memory != null &&
        isKnown(card, now, fsrs: fsrs) &&
        fsrs.retrievability(memory, now) >= LearningConfig.silentMinR;
  }
  final own = history?.ownDrives ?? const [];
  return own.length >= LearningConfig.silentOwnDrives &&
      own.take(LearningConfig.silentOwnDrives).every((ok) => ok);
}

/// The level to suggest for a route (SPEC §16.23 item 114) from its decisions' [keys] (null: a
/// decision without OSM nodes): by the share silent-eligible ([silent]), Off also needing every card's recall at
/// [LearningConfig.levelOffMinR] and a Quiet drive on this route with at most one recovery;
/// Guided while the destination's raion has fewer than [LearningConfig.levelMinAreaJ]
/// introduced J cards ([areaJ]). Then [past] drives on this route (latest first) step it at
/// most one level from the last: less help after [LearningConfig.stepDrives] good ones, more
/// after as many poor ones.
DriveLevel suggestLevel({
  required List<String?> keys,
  required Set<String> silent,
  required double? minRecall,
  required List<PastDrive> past,
  required int areaJ,
}) {
  if (areaJ < LearningConfig.levelMinAreaJ) return DriveLevel.guided;
  final route = keys.nonNulls.toSet();
  final onRoute = [
    for (final p in past)
      if (_overlaps(route, p.decisions)) p,
  ];
  final share = keys.isEmpty
      ? 1.0
      : keys.where(silent.contains).length / keys.length;
  final base = switch (share) {
    _
        when share >= LearningConfig.levelOffShare &&
            (minRecall ?? 1) >= LearningConfig.levelOffMinR &&
            onRoute.any(
              (p) => p.level == DriveLevel.quiet && p.recoveries <= 1,
            ) =>
      DriveLevel.off,
    _ when share >= LearningConfig.levelQuietShare => DriveLevel.quiet,
    _ when share >= LearningConfig.levelCoachedShare => DriveLevel.coached,
    _ => DriveLevel.guided,
  };
  if (onRoute.isEmpty) return base;
  final last = onRoute.first.level;
  final recent = onRoute
      .take(LearningConfig.stepDrives)
      .where((p) => p.level == last)
      .toList();
  final full = recent.length == LearningConfig.stepDrives;
  if (full && recent.every(_poor)) return _step(last, -1);
  if (base.index > last.index) {
    return full && recent.every(_good) ? _step(last, 1) : last;
  }
  if (base.index < last.index) return _step(last, -1);
  return last;
}

/// The levels the player may pick (item 114): any with more help, and one step less.
List<DriveLevel> levelChoices(DriveLevel suggested) => [
  for (final l in DriveLevel.values)
    if (l.index <= suggested.index + 1) l,
];

bool _overlaps(Set<String> route, Set<String> drove) =>
    route.isEmpty ||
    route.where(drove.contains).length / route.length >=
        LearningConfig.routeOverlap;

bool _good(PastDrive p) =>
    (p.stretch ?? double.infinity) <= LearningConfig.stepDownStretch &&
    p.recoveries <= 1;

bool _poor(PastDrive p) =>
    (p.stretch ?? double.infinity) > LearningConfig.stepUpStretch ||
    p.recoveries >= LearningConfig.stepUpRecoveries;

/// [level] [by] steps less help (negative: more), within the levels.
DriveLevel _step(DriveLevel level, int by) =>
    DriveLevel.values[min(
      max(level.index + by, 0),
      DriveLevel.values.length - 1,
    )];

/// The help a decision had on a drive (SPEC §16.23 item 124).
enum NavHelp {
  /// Nothing said or shown: Coached silent, Quiet, Off.
  none,

  /// Coached's cue before it.
  cue,

  /// Guided's prompts, or Guided after a rescue.
  guided,

  /// Taken while recovering.
  recovery,
}

/// Why a drive decision reviews no card (SPEC §16.23 item 119).
enum CreditSkip {
  /// Guided, cued or recovering: exposure only.
  helped,

  /// A prompt or a recovery in the [LearningConfig.noCreditAfterPromptS] before it.
  recentHelp,

  /// The route book has no J card for it.
  noCard,

  /// Recall above [LearningConfig.creditMaxR]: too early to count.
  notDue,

  /// Already credited today.
  creditedToday,

  /// A habitual corridor credited within [LearningConfig.habitCreditDays].
  habitual,

  /// A miss on a card not in review or not near due, or a success on one without a memory or
  /// suspended: left to the sessions (SPEC §4).
  sessionOnly,
}

/// What a decision taken on a drive does to its J [card] (SPEC §16.23 item 119): a success with
/// no help reviews Good, or Hard after a [hesitated] stop within
/// [LearningConfig.hesitationBeforeM] before it, while recall is at most
/// [LearningConfig.creditMaxR], once a day, and on a habitual corridor ([passes] of it in
/// [LearningConfig.habitWindowDays], this one included) once per
/// [LearningConfig.habitCreditDays] since [lastCredited]. A failure is Again (applied as
/// `implicitReview` does). Never Easy.
({Rating? rating, CreditSkip? skip}) driveCredit({
  required CardState? card,
  required bool ok,
  required NavHelp help,
  required bool recentHelp,
  required bool hesitated,
  required DateTime now,
  List<DateTime> passes = const [],
  DateTime? lastCredited,
  Fsrs fsrs = const Fsrs(),
}) {
  if (help != NavHelp.none) return (rating: null, skip: CreditSkip.helped);
  if (recentHelp) return (rating: null, skip: CreditSkip.recentHelp);
  if (card == null) return (rating: null, skip: CreditSkip.noCard);
  if (!ok) return (rating: Rating.again, skip: null);
  final memory = card.memory;
  if (memory != null &&
      fsrs.retrievability(memory, now) > LearningConfig.creditMaxR) {
    return (rating: null, skip: CreditSkip.notDue);
  }
  if (lastCredited != null && _sameDay(lastCredited, now)) {
    return (rating: null, skip: CreditSkip.creditedToday);
  }
  final habitual =
      passes
          .where(
            (t) => now.difference(t).inDays < LearningConfig.habitWindowDays,
          )
          .length >=
      LearningConfig.habitPasses;
  if (habitual &&
      lastCredited != null &&
      now.difference(lastCredited).inDays < LearningConfig.habitCreditDays) {
    return (rating: null, skip: CreditSkip.habitual);
  }
  return (rating: hesitated ? Rating.hard : Rating.good, skip: null);
}

bool _sameDay(DateTime a, DateTime b) {
  final x = a.toLocal(), y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// A drive in the log, for [navHistory]: its level, stretch and recoveries.
typedef LoggedDrive = ({
  String id,
  DriveLevel level,
  double? stretch,
  int recoveries,
});

/// A decision in the drive log, for [navHistory].
typedef LoggedDecision = ({
  String driveId,
  String? key,
  bool? ok,
  NavHelp help,
  bool recentHelp,
  DateTime at,
});

/// The player's decision history and past drives (latest first) from the drive log ([drives]
/// latest first, their [decisions]) and the last [failures] elsewhere by item id: a decision
/// fails at a wrong move, and is taken on the player's own when right with no help.
({Map<String, DecisionHistory> decisions, List<PastDrive> past}) navHistory({
  required List<LoggedDrive> drives,
  required List<LoggedDecision> decisions,
  Map<String, DateTime> failures = const {},
}) {
  final byDrive = <String, List<LoggedDecision>>{};
  for (final d in decisions) {
    byDrive.putIfAbsent(d.driveId, () => []).add(d);
  }
  final lastFailure = Map.of(failures);
  final own = <String, List<bool>>{};
  for (final drive in drives) {
    for (final d in byDrive[drive.id] ?? const <LoggedDecision>[]) {
      final key = d.key;
      final ok = d.ok;
      if (key == null || ok == null) continue;
      if (!ok) {
        final seen = lastFailure[key];
        if (seen == null || d.at.isAfter(seen)) lastFailure[key] = d.at;
      }
      own
          .putIfAbsent(key, () => [])
          .add(ok && d.help == NavHelp.none && !d.recentHelp);
    }
  }
  return (
    decisions: {
      for (final key in {...lastFailure.keys, ...own.keys})
        key: (lastFailure: lastFailure[key], ownDrives: own[key] ?? const []),
    },
    past: [
      for (final drive in drives)
        (
          level: drive.level,
          decisions: {
            for (final d in byDrive[drive.id] ?? const <LoggedDecision>[])
              ?d.key,
          },
          stretch: drive.stretch,
          recoveries: drive.recoveries,
        ),
    ],
  );
}

/// The level to suggest for a route's decisions by their [keys] (SPEC §16.23 items 113–114) and
/// the decisions that may stay silent, from the player's J [cards] (by item id), decision
/// [history] (by key), [past] drives and [areaJ].
({DriveLevel level, Set<String> silent}) routeSuggestion({
  required List<String?> keys,
  required Map<String, CardState> cards,
  required Map<String, DecisionHistory> history,
  required List<PastDrive> past,
  required int areaJ,
  required DateTime now,
  Fsrs fsrs = const Fsrs(),
}) {
  final silent = {
    for (final key in keys.nonNulls)
      if (silentEligible(cards[key], history[key], now, fsrs: fsrs)) key,
  };
  final recalls = [
    for (final key in keys)
      if (cards[key]?.memory case final memory?)
        fsrs.retrievability(memory, now),
  ];
  return (
    level: suggestLevel(
      keys: keys,
      silent: silent,
      minRecall: recalls.isEmpty ? null : recalls.reduce(min),
      past: past,
      areaJ: areaJ,
    ),
    silent: silent,
  );
}
