import 'dart:convert';

import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

final _now = DateTime(2026, 3, 30, 21);

LogEntry _review(
  double rBefore,
  Rating rating, {
  double elapsedDays = 3,
  ReviewFormat format = ReviewFormat.review,
  ReviewSource source = ReviewSource.session,
}) => LogEntry(
  ts: _now,
  itemId: 'P:s',
  format: format,
  rating: rating,
  source: source,
  elapsedDays: elapsedDays,
  rBefore: rBefore,
);

/// A session [daysAgo] taking [minutes]: an answer every 30 s.
List<LogEntry> _day(int daysAgo, int minutes) {
  final start = DateTime(_now.year, _now.month, _now.day - daysAgo, 9);
  return [
    for (var i = 0; i <= minutes * 2; i++)
      LogEntry(
        ts: start.add(Duration(seconds: 30 * i)),
        itemId: 'P:s',
        format: ReviewFormat.review,
        rating: Rating.good,
        source: ReviewSource.session,
        sessionId: 'd$daysAgo',
      ),
  ];
}

/// [minutes] a day for the days [from] to [to] ago.
List<LogEntry> _days(int from, int to, int minutes) => [
  for (var d = from; d >= to; d--) ..._day(d, minutes),
];

void main() {
  group('fitted FSRS weights (SPEC §12, §16.9)', () {
    tearDown(() => FsrsWeights.active = LearningConfig.fsrsWeights);

    test('a list of 21 weights, or the fit tool\'s object, is read', () {
      final fitted = [...LearningConfig.fsrsWeights]..[0] = 0.5;
      expect(FsrsWeights.parse(jsonEncode(fitted)), fitted);
      expect(
        FsrsWeights.parse(jsonEncode({'weights': fitted, 'reviews': 1200})),
        fitted,
      );
    });

    test('anything else is refused', () {
      final decayless = [...LearningConfig.fsrsWeights]..[20] = 0;
      final stabilityless = [...LearningConfig.fsrsWeights]..[2] = -1;
      final slipped = [...LearningConfig.fsrsWeights]..[8] = 18722;
      for (final json in [
        'nonsense',
        '{}',
        jsonEncode(LearningConfig.fsrsWeights.take(20).toList()),
        jsonEncode([...LearningConfig.fsrsWeights.take(20), 'x']),
        jsonEncode(decayless),
        jsonEncode(stabilityless),
        jsonEncode(slipped),
      ]) {
        expect(FsrsWeights.parse(json), isNull, reason: json);
      }
    });

    test('every scheduler uses the active weights', () {
      expect(FsrsWeights.fitted, isFalse);
      final first = DateTime(2026, 3, 2);
      double againStability() =>
          const Fsrs().next(null, Rating.again, first).memory.stability;
      expect(againStability(), LearningConfig.fsrsWeights[0]);
      FsrsWeights.active = [...LearningConfig.fsrsWeights]..[0] = 0.5;
      expect(againStability(), 0.5);
      expect(FsrsWeights.fitted, isTrue);
    });
  });

  group('calibration (SPEC §12)', () {
    test('bins reviews by predicted recall; same-day answers, drills and '
        'implicit evidence stay out', () {
      final bins = calibration([
        for (var i = 0; i < 20; i++)
          _review(0.92, i < 18 ? Rating.good : Rating.again),
        _review(0.85, Rating.hard),
        _review(0.85, Rating.again),
        _review(0.3, Rating.again, elapsedDays: 0),
        _review(0.3, Rating.again, format: ReviewFormat.bearing),
        for (final source in [ReviewSource.recital, ReviewSource.drive])
          _review(0.3, Rating.again, source: source),
      ]);
      expect(bins.map((b) => (b.from, b.reviews)), [(0.8, 2), (0.9, 20)]);
      expect(bins.last.predicted, closeTo(0.92, 1e-9));
      expect(bins.last.recalled, 0.9);
      expect(bins.last.calibrated, isTrue);
      expect(bins.first.recalled, 0.5);
      expect(bins.first.calibrated, isNull, reason: 'too few to judge');
    });

    test('a bin recalled more than 5 points off its prediction is off', () {
      final bins = calibration([
        for (var i = 0; i < 20; i++)
          _review(0.95, i < 16 ? Rating.good : Rating.again),
      ]);
      expect(bins.single.calibrated, isFalse);
    });
  });

  group('tier C relief (SPEC §4)', () {
    ({bool on, int meanS}) relief(List<LogEntry> log) =>
        tierCRelief(log, minutesPerDay: 20, now: _now);

    test('on once the days played average over 1.2 × the minutes', () {
      expect(relief(_days(6, 0, 22)).on, isFalse);
      final over = relief(_days(6, 0, 25));
      expect(over.on, isTrue);
      expect(over.meanS, 25 * 60);
    });

    test('stays on between the minutes and 1.2 ×, off under the minutes', () {
      expect(relief([..._days(20, 14, 30), ..._days(13, 0, 22)]).on, isTrue);
      expect(relief([..._days(20, 14, 30), ..._days(13, 0, 15)]).on, isFalse);
    });

    test('a day is judged by the days before it, so a short today keeps '
        'it on', () {
      final log = [..._days(14, 8, 30), ..._days(7, 1, 22), ..._day(0, 1)];
      expect(relief(log).on, isTrue);
      expect(relief(log).meanS, 22 * 60);
    });

    test('only days played count towards the mean', () {
      expect(relief([..._day(5, 26), ..._day(1, 26)]).on, isTrue);
      expect(relief(const []).on, isFalse);
    });

    test('relieved tier C pin cards aim for 85 % recall', () {
      expect(
        retentionOf(CardType.p, tierCRelieved: true),
        LearningConfig.retentionTierCRelief,
      );
      expect(
        retentionOf(CardType.j, tierCRelieved: true),
        LearningConfig.retentionDefault,
      );
    });
  });
}
