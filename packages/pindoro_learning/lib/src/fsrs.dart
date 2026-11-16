import 'dart:convert';
import 'dart:math';

import 'constants.dart';

/// An FSRS rating; [grade] is the 1–4 number the formulas use.
enum Rating {
  again,
  hard,
  good,
  easy;

  int get grade => index + 1;
  bool get isSuccess => this != again;
}

/// What FSRS knows about a card after its first review.
class Memory {
  const Memory({
    required this.stability,
    required this.difficulty,
    required this.lastReview,
  });

  final double stability;
  final double difficulty;
  final DateTime lastReview;
}

/// One review's outcome: the new memory and the whole-day interval to the next review.
class Scheduled {
  const Scheduled(this.memory, this.intervalDays);

  final Memory memory;
  final int intervalDays;

  DateTime get due => memory.lastReview.add(Duration(days: intervalDays));
}

/// The weights every `Fsrs()` uses (SPEC §12, §16.9): §4's defaults until the app loads a set
/// fitted to the player's own log at launch.
// ponytail: one process-wide memory model, set before anything is scheduled; pass an Fsrs
// through instead if two models ever have to run side by side.
abstract final class FsrsWeights {
  static List<double> active = LearningConfig.fsrsWeights;

  /// Fitted weights from [json]: a list of 21 numbers, or an object holding one as `weights`
  /// (what `just fsrs-fit` prints). Null unless the initial stabilities are positive and the
  /// decay lies in (0, 1].
  static List<double>? parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return null;
    }
    final list = switch (decoded) {
      {'weights': final List<Object?> w} => w,
      final List<Object?> w => w,
      _ => null,
    };
    if (list == null || list.length != LearningConfig.fsrsWeights.length) {
      return null;
    }
    final weights = [
      for (final w in list)
        if (w is num && w.isFinite) w.toDouble(),
    ];
    final plausible =
        weights.length == list.length &&
        weights.take(4).every((s) => s > 0) &&
        weights[20] > 0 &&
        weights[20] <= 1;
    return plausible ? List.unmodifiable(weights) : null;
  }
}

/// FSRS-6 as py-fsrs 6.3.2 runs it with no learning steps (SPEC §4). Pure: the caller passes the
/// time and, for fuzz, a seeded [Random].
class Fsrs {
  const Fsrs({
    List<double>? weights,
    this.maxIntervalDays = LearningConfig.maxIntervalDays,
  }) : _weights = weights;

  final List<double>? _weights;
  final int maxIntervalDays;

  /// The given weights, else [FsrsWeights.active].
  List<double> get weights => _weights ?? FsrsWeights.active;

  static const double _minStability = 0.001;

  double get _decay => -weights[20];
  double get _factor => pow(0.9, 1 / _decay) - 1;

  /// The chance of recalling the card at [now], counting whole days since the last review.
  double retrievability(Memory memory, DateTime now) {
    final days = _wholeDays(memory.lastReview, now);
    return pow(1 + _factor * days / memory.stability, _decay).toDouble();
  }

  /// Rates a review at [now]; [memory] is null for a card's first review.
  Scheduled next(
    Memory? memory,
    Rating rating,
    DateTime now, {
    double retention = LearningConfig.retentionDefault,
    Random? fuzz,
  }) {
    final (stability, difficulty) = switch (memory) {
      null => (
        _initialStability(rating),
        _initialDifficulty(rating).clamp(1.0, 10.0),
      ),
      _ when _wholeDays(memory.lastReview, now) < 1 => (
        _shortTermStability(memory.stability, rating),
        _nextDifficulty(memory.difficulty, rating),
      ),
      _ => (
        _longTermStability(memory, retrievability(memory, now), rating),
        _nextDifficulty(memory.difficulty, rating),
      ),
    };
    final next = Memory(
      stability: stability,
      difficulty: difficulty,
      lastReview: now,
    );
    return Scheduled(next, _fuzzed(_interval(stability, retention), fuzz));
  }

  int _interval(double stability, double retention) {
    final days = stability / _factor * (pow(retention, 1 / _decay) - 1);
    return _roundHalfEven(days).clamp(1, maxIntervalDays);
  }

  int _fuzzed(int days, Random? fuzz) {
    if (fuzz == null || days <= LearningConfig.fuzzMinDays) return days;
    final spread = LearningConfig.fuzzFraction * (2 * fuzz.nextDouble() - 1);
    return _roundHalfEven(days * (1 + spread)).clamp(1, maxIntervalDays);
  }

  double _initialStability(Rating rating) =>
      max(weights[rating.grade - 1], _minStability);

  // Unclamped: mean reversion uses the raw D0(Easy) (SPEC §4).
  double _initialDifficulty(Rating rating) =>
      weights[4] - exp(weights[5] * (rating.grade - 1)) + 1;

  double _nextDifficulty(double difficulty, Rating rating) {
    final delta = -weights[6] * (rating.grade - 3);
    final damped = difficulty + (10 - difficulty) * delta / 9;
    final reverted =
        weights[7] * _initialDifficulty(Rating.easy) +
        (1 - weights[7]) * damped;
    return reverted.clamp(1.0, 10.0);
  }

  double _shortTermStability(double stability, Rating rating) {
    var increase =
        exp(weights[17] * (rating.grade - 3 + weights[18])) *
        pow(stability, -weights[19]);
    if (rating.isSuccess) increase = max(increase, 1.0);
    return max(stability * increase, _minStability);
  }

  double _longTermStability(Memory memory, double r, Rating rating) {
    final s = memory.stability;
    final d = memory.difficulty;
    final next = rating == Rating.again
        ? min(
            weights[11] *
                pow(d, -weights[12]) *
                (pow(s + 1, weights[13]) - 1) *
                exp((1 - r) * weights[14]),
            s / exp(weights[17] * weights[18]),
          )
        : s *
              (1 +
                  exp(weights[8]) *
                      (11 - d) *
                      pow(s, -weights[9]) *
                      (exp((1 - r) * weights[10]) - 1) *
                      (rating == Rating.hard ? weights[15] : 1) *
                      (rating == Rating.easy ? weights[16] : 1));
    return max(next, _minStability);
  }
}

// Whole 24 h periods, never negative: py-fsrs's `timedelta.days`.
int _wholeDays(DateTime from, DateTime to) =>
    max(0, to.difference(from).inDays);

// Python's round(): halves go to the even neighbour.
int _roundHalfEven(double x) {
  final floor = x.floorToDouble();
  final diff = x - floor;
  if (diff != 0.5) return x.round();
  return floor.toInt().isEven ? floor.toInt() : floor.toInt() + 1;
}
