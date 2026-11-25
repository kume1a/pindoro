import 'dart:math';

import 'cards.dart';
import 'constants.dart';
import 'days.dart';

/// Cards of [types] introduced since the start of [now]'s day: streets come off today's new
/// number, places off today's places.
int introducedToday(
  Iterable<CardState> cards,
  DateTime now, {
  Set<CardType> types = const {CardType.p},
}) {
  final today = startOfDay(now);
  return cards
      .where(
        (c) =>
            types.contains(c.type) &&
            c.introAt != null &&
            !c.introAt!.isBefore(today),
      )
      .length;
}

/// Seconds spent learning since the start of [now]'s day (SPEC §16.9), each
/// session counted with [activeSeconds].
int spentTodayS(Iterable<LogEntry> log, DateTime now) {
  final today = startOfDay(now);
  return spentS(log.where((e) => !e.ts.isBefore(today)));
}

/// Seconds spent on [entries], each session counted with [activeSeconds].
int spentS(Iterable<LogEntry> entries) {
  final bySession = <String?, List<DateTime>>{};
  for (final entry in entries) {
    bySession.putIfAbsent(entry.sessionId, () => []).add(entry.ts);
  }
  return bySession.values.fold(0, (sum, times) => sum + activeSeconds(times));
}

/// Whether today counts towards the streak (SPEC §8, §16.8): something was answered [today] and
/// then either nothing is due before midnight or the day's minutes are spent.
bool dayCounts({
  required Iterable<CardState> cards,
  required List<LogEntry> today,
  required int minutesPerDay,
  required DateTime now,
}) {
  if (!today.any((e) => !e.ts.isBefore(startOfDay(now)))) return false;
  final midnight = nextMidnight(now);
  return !cards.any((c) => isDueBefore(c, midnight)) ||
      spentTodayS(today, now) >= minutesPerDay * 60;
}

/// The session's time estimates from the log (SPEC §16.9): once there are
/// [LearningConfig.timeEstimateMinSamples] reviews, a review takes the median
/// gap before a review answer and a new street the default share of it.
({int tReviewS, int tNewS}) timeEstimates(Iterable<LogEntry> log) {
  final bySession = <String?, List<LogEntry>>{};
  for (final e in log) {
    bySession.putIfAbsent(e.sessionId, () => []).add(e);
  }
  final gaps = <int>[];
  for (final rows in bySession.values) {
    rows.sort((a, b) => a.ts.compareTo(b.ts));
    for (var i = 1; i < rows.length; i++) {
      if (rows[i].format != ReviewFormat.review) continue;
      gaps.add(
        min(
          rows[i].ts.difference(rows[i - 1].ts).inSeconds,
          LearningConfig.answerGapCapS,
        ),
      );
    }
  }
  if (gaps.length < LearningConfig.timeEstimateMinSamples) {
    return (tReviewS: LearningConfig.tReviewS, tNewS: LearningConfig.tNewS);
  }
  gaps.sort();
  final tReview = max(1, gaps[gaps.length ~/ 2]);
  return (
    tReviewS: tReview,
    tNewS: (tReview * LearningConfig.tNewS / LearningConfig.tReviewS).round(),
  );
}

/// Seconds between consecutive [times] of one session, each gap capped at
/// [LearningConfig.answerGapCapS] (SPEC §16.9).
int activeSeconds(Iterable<DateTime> times) {
  final sorted = times.toList()..sort();
  var seconds = 0;
  for (var i = 1; i < sorted.length; i++) {
    seconds += min(
      sorted[i].difference(sorted[i - 1]).inSeconds,
      LearningConfig.answerGapCapS,
    );
  }
  return seconds;
}

/// Cards of [types] started since the start of [now]'s day (their first log row is today).
int startedToday(Iterable<LogEntry> log, DateTime now, Set<CardType> types) {
  final today = startOfDay(now);
  return log
      .where(
        (e) =>
            types.contains(e.type) &&
            e.sBefore == null &&
            !e.ts.isBefore(today),
      )
      .map((e) => e.itemId)
      .toSet()
      .length;
}

/// Days of the day's minutes that [dueCount] reviews take (Today's catching
/// up: "About 3 days at 20 min").
int catchUpDays({
  required int dueCount,
  required int minutesPerDay,
  int tReviewS = LearningConfig.tReviewS,
}) => (dueCount * tReviewS / (minutesPerDay * 60)).ceil();
