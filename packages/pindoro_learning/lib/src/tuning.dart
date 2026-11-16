import 'dart:math';

import 'cards.dart';
import 'constants.dart';
import 'planner.dart';
import 'stats.dart';

/// Reviews whose predicted recall fell in [from]–[to] (SPEC §12): how many, the mean prediction
/// and the share recalled.
typedef CalibrationBin = ({
  double from,
  double to,
  int reviews,
  double predicted,
  double recalled,
});

extension CalibrationCheck on CalibrationBin {
  /// Recalled within [LearningConfig.calibrationTolerance] of the prediction; null with fewer than
  /// [LearningConfig.calibrationMinReviews] reviews to judge by.
  bool? get calibrated => reviews < LearningConfig.calibrationMinReviews
      ? null
      : (recalled - predicted).abs() <= LearningConfig.calibrationTolerance;
}

/// The calibration check (SPEC §12): reviews a day or more after the last one that moved their
/// card, binned by the recall FSRS predicted; the bins with any. Implicit evidence stays out: only
/// its failures are logged.
List<CalibrationBin> calibration(Iterable<LogEntry> log) {
  const n = LearningConfig.calibrationBins;
  final predicted = List.filled(n, 0.0);
  final recalled = List.filled(n, 0);
  final reviews = List.filled(n, 0);
  for (final e in log) {
    final r = e.rBefore;
    if (r == null ||
        (e.elapsedDays ?? 0) < 1 ||
        e.source.implicit ||
        !changesSchedule(e)) {
      continue;
    }
    final bin = min((r * n).floor(), n - 1);
    predicted[bin] += r;
    reviews[bin]++;
    if (e.rating.isSuccess) recalled[bin]++;
  }
  return [
    for (var i = 0; i < n; i++)
      if (reviews[i] > 0)
        (
          from: i / n,
          to: (i + 1) / n,
          reviews: reviews[i],
          predicted: predicted[i] / reviews[i],
          recalled: recalled[i] / reviews[i],
        ),
  ];
}

/// Tier C relief (SPEC §4, §16.17): a day is relieved once the days played among the
/// [LearningConfig.tierCReliefDays] before it took on average more than
/// [LearningConfig.tierCReliefFactor] times [minutesPerDay], and not once they average under
/// [minutesPerDay]. Replayed day by day over [LearningConfig.tierCReliefReplayDays] from off, so
/// today's state holds all day; [meanS] is the average today is judged by.
({bool on, int meanS}) tierCRelief(
  Iterable<LogEntry> log, {
  required int minutesPerDay,
  required DateTime now,
}) {
  const window = LearningConfig.tierCReliefDays;
  const replay = LearningConfig.tierCReliefReplayDays;
  DateTime dayBefore(int days) => DateTime(now.year, now.month, now.day - days);
  final first = dayBefore(replay + window);
  final byDay = <DateTime, List<LogEntry>>{};
  for (final e in log) {
    final day = startOfDay(e.ts.toLocal());
    if (!day.isBefore(first)) byDay.putIfAbsent(day, () => []).add(e);
  }
  final spent = {
    for (final MapEntry(:key, :value) in byDay.entries) key: spentS(value),
  };
  final budget = minutesPerDay * 60;
  var on = false;
  var meanS = 0;
  for (var d = replay; d >= 0; d--) {
    final played = [for (var k = 1; k <= window; k++) ?spent[dayBefore(d + k)]];
    meanS = played.isEmpty
        ? 0
        : played.reduce((a, b) => a + b) ~/ played.length;
    if (meanS > budget * LearningConfig.tierCReliefFactor) {
      on = true;
    } else if (meanS < budget) {
      on = false;
    }
  }
  return (on: on, meanS: meanS);
}

/// The recall [type] is scheduled for (SPEC §4): tier C pin cards aim lower while
/// [tierCRelieved].
double retentionOf(CardType type, {bool tierCRelieved = false}) =>
    type == CardType.p && tierCRelieved
    ? LearningConfig.retentionTierCRelief
    : LearningConfig.retentionDefault;
