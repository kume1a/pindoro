import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

final Map<String, dynamic> vectors =
    jsonDecode(
          File('../../shared/fixtures/fsrs_vectors.json').readAsStringSync(),
        )
        as Map<String, dynamic>;

void main() {
  const fsrs = Fsrs();
  final tolerance = vectors['tolerance'] as double;

  test('weights and settings match the vectors', () {
    expect(LearningConfig.fsrsWeights, vectors['parameters']);
    expect(LearningConfig.retentionDefault, vectors['desired_retention']);
    expect(LearningConfig.maxIntervalDays, vectors['maximum_interval']);
  });

  group('matches py-fsrs', () {
    for (final sequence
        in (vectors['sequences'] as List).cast<Map<String, dynamic>>()) {
      test(sequence['name'], () {
        Memory? memory;
        for (final (i, review)
            in (sequence['reviews'] as List)
                .cast<Map<String, dynamic>>()
                .indexed) {
          final at = DateTime.parse(review['at'] as String);
          final reason = 'review ${i + 1}';
          if (memory != null) {
            expect(
              fsrs.retrievability(memory, at),
              closeTo(review['retrievability'] as double, tolerance),
              reason: reason,
            );
          }
          final scheduled = fsrs.next(
            memory,
            Rating.values[(review['rating'] as int) - 1],
            at,
          );
          expect(
            scheduled.memory.stability,
            closeTo(review['stability'] as double, tolerance),
            reason: reason,
          );
          expect(
            scheduled.memory.difficulty,
            closeTo(review['difficulty'] as double, tolerance),
            reason: reason,
          );
          expect(
            scheduled.intervalDays,
            review['interval_days'],
            reason: reason,
          );
          expect(
            scheduled.due,
            DateTime.parse(review['due'] as String),
            reason: reason,
          );
          memory = scheduled.memory;
        }
      });
    }
  });

  test('retrievability matches the probes', () {
    final start = DateTime.utc(2026);
    for (final probe
        in (vectors['retrievability'] as List).cast<Map<String, dynamic>>()) {
      final memory = Memory(
        stability: probe['stability'] as double,
        difficulty: 5,
        lastReview: start,
      );
      final at = start.add(Duration(days: probe['elapsed_days'] as int));
      expect(
        fsrs.retrievability(memory, at),
        closeTo(probe['retrievability'] as double, tolerance),
        reason: '$probe',
      );
    }
  });

  test('retrievability counts whole days only', () {
    final start = DateTime.utc(2026);
    final memory = Memory(stability: 10, difficulty: 5, lastReview: start);
    expect(
      fsrs.retrievability(memory, start.add(const Duration(hours: 23))),
      1,
    );
    expect(
      fsrs.retrievability(
        memory,
        start.add(const Duration(days: 1, hours: 23)),
      ),
      fsrs.retrievability(memory, start.add(const Duration(days: 1))),
    );
  });

  group('fuzz', () {
    final start = DateTime.utc(2026);
    Memory memoryFor(double stability) =>
        Memory(stability: stability, difficulty: 5, lastReview: start);

    test('is deterministic for a seed and stays within ±5 %', () {
      final base = fsrs.next(
        memoryFor(100),
        Rating.good,
        start.add(const Duration(days: 100)),
      );
      final seen = <int>{};
      for (var seed = 0; seed < 200; seed++) {
        final a = fsrs.next(
          memoryFor(100),
          Rating.good,
          start.add(const Duration(days: 100)),
          fuzz: Random(seed),
        );
        final b = fsrs.next(
          memoryFor(100),
          Rating.good,
          start.add(const Duration(days: 100)),
          fuzz: Random(seed),
        );
        expect(a.intervalDays, b.intervalDays);
        expect(
          (a.intervalDays - base.intervalDays).abs(),
          lessThanOrEqualTo(base.intervalDays * 0.05 + 0.5),
        );
        seen.add(a.intervalDays);
      }
      expect(seen.length, greaterThan(1));
    });

    test('leaves intervals of 3 days or less alone', () {
      final first = fsrs.next(null, Rating.good, start);
      for (var seed = 0; seed < 50; seed++) {
        expect(
          fsrs.next(null, Rating.good, start, fuzz: Random(seed)).intervalDays,
          first.intervalDays,
        );
      }
    });

    test('never passes the maximum interval', () {
      final memory = memoryFor(5000);
      for (var seed = 0; seed < 50; seed++) {
        final scheduled = fsrs.next(
          memory,
          Rating.easy,
          start.add(const Duration(days: 365)),
          fuzz: Random(seed),
        );
        expect(
          scheduled.intervalDays,
          lessThanOrEqualTo(LearningConfig.maxIntervalDays),
        );
      }
    });
  });

  test('a lower retention gives a longer interval', () {
    final start = DateTime.utc(2026);
    final memory = Memory(stability: 10, difficulty: 5, lastReview: start);
    final at = start.add(const Duration(days: 10));
    expect(
      fsrs
          .next(
            memory,
            Rating.good,
            at,
            retention: LearningConfig.retentionTierCRelief,
          )
          .intervalDays,
      greaterThan(fsrs.next(memory, Rating.good, at).intervalDays),
    );
  });
}
