import 'dart:math';

import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 3, 10, 9);

  CardState card({
    required DateTime lastReview,
    double stability = 10,
    Rating lastRating = Rating.good,
    DateTime? introAt,
    bool priorKnown = false,
    CardPhase phase = CardPhase.review,
  }) => CardState(
    itemId: 'P:x',
    phase: phase,
    memory: Memory(stability: stability, difficulty: 5, lastReview: lastReview),
    lastRating: lastRating,
    introAt: introAt,
    priorKnown: priorKnown,
  );

  group('isKnown (SPEC §8, §16.17)', () {
    test('a success on a later day than the intro, with R ≥ 0.80', () {
      final c = card(
        introAt: DateTime.utc(2026, 3, 8, 9),
        lastReview: DateTime.utc(2026, 3, 9, 9),
      );
      expect(isKnown(c, now), isTrue);
    });

    test('not on the intro day, however well answered', () {
      final c = card(
        introAt: DateTime.utc(2026, 3, 10, 8),
        lastReview: DateTime.utc(2026, 3, 10, 8, 30),
      );
      expect(isKnown(c, now), isFalse);
    });

    test('it decays: low recall is no longer known', () {
      final c = card(
        introAt: DateTime.utc(2026, 1, 1),
        lastReview: DateTime.utc(2026, 1, 5),
        stability: 2,
      );
      expect(isKnown(c, now), isFalse);
    });

    test('a forgotten last answer is not known', () {
      final c = card(
        introAt: DateTime.utc(2026, 3, 1),
        lastReview: DateTime.utc(2026, 3, 9),
        lastRating: Rating.again,
      );
      expect(isKnown(c, now), isFalse);
    });

    test('placement cards count without the later-day success', () {
      final c = card(
        priorKnown: true,
        lastReview: DateTime.utc(2026, 3, 10, 8),
      );
      expect(isKnown(c, now), isTrue);
    });

    test('an intro with no answer yet is not known', () {
      expect(isKnown(introduce('P:x', now), now), isFalse);
    });
  });

  test('cityMemory sums recall over core streets only', () {
    const fsrs = Fsrs();
    final a = card(
      lastReview: DateTime.utc(2026, 3, 5),
      introAt: DateTime.utc(2026, 3, 1),
    );
    final b = CardState(
      itemId: 'P:short',
      phase: CardPhase.review,
      memory: Memory(
        stability: 30,
        difficulty: 5,
        lastReview: DateTime.utc(2026, 3, 9),
      ),
    );
    final memory = cityMemory(
      [a, b, introduce('P:new', now)],
      now,
      isCore: (id) => id != 'P:short',
    );
    expect(memory, closeTo(fsrs.retrievability(a.memory!, now), 1e-12));
  });

  group('memoryState (SPEC §8)', () {
    test('the strongest label: mastered, solid, known, else seen', () {
      final old = DateTime.utc(2026, 1, 1);
      final yesterday = DateTime.utc(2026, 3, 9, 9);
      expect(
        memoryState(
          card(lastReview: yesterday, stability: 95, introAt: old),
          now,
        ),
        MemoryState.mastered,
      );
      expect(
        memoryState(
          card(
            lastReview: yesterday,
            stability: 95,
            introAt: old,
            lastRating: Rating.again,
          ),
          now,
        ),
        MemoryState.solid,
      );
      expect(
        memoryState(
          card(lastReview: yesterday, stability: 21, introAt: old),
          now,
        ),
        MemoryState.solid,
      );
      expect(
        memoryState(card(lastReview: yesterday, introAt: old), now),
        MemoryState.known,
      );
      expect(memoryState(introduce('P:x', now), now), MemoryState.seen);
    });

    test('Mastered needs each name and ends card that applies at 21 days', () {
      final p = card(
        lastReview: DateTime.utc(2026, 3, 9),
        stability: 95,
        introAt: DateTime.utc(2026),
      );
      CardState side(double s) => card(lastReview: now, stability: s);
      expect(isMastered(p, sides: [side(21), side(30)]), isTrue);
      expect(isMastered(p, sides: [side(20)]), isFalse);
      expect(isMastered(p, sides: [null]), isFalse, reason: 'not started');
      expect(
        memoryCounts([p], now, sidesOf: (_) => [null])[MemoryState.solid],
        1,
      );
    });

    test('City memory counts only pin cards', () {
      final seen = card(lastReview: now);
      final name = CardState(
        itemId: 'N:x',
        phase: CardPhase.review,
        memory: seen.memory,
      );
      expect(
        cityMemory([seen, name], now, isCore: (_) => true),
        closeTo(1, 1e-9),
      );
    });

    test('memoryCounts tallies every state, zeros included', () {
      final counts = memoryCounts([
        introduce('P:a', now),
        introduce('P:b', now),
      ], now);
      expect(counts, {
        MemoryState.mastered: 0,
        MemoryState.solid: 0,
        MemoryState.known: 0,
        MemoryState.seen: 2,
      });
    });
  });

  LogEntry entry(
    String item,
    DateTime ts,
    Rating rating, {
    ReviewFormat format = ReviewFormat.review,
    double? sBefore,
    double? dBefore,
    double? elapsedDays,
  }) => LogEntry(
    ts: ts,
    itemId: item,
    format: format,
    rating: rating,
    source: ReviewSource.session,
    sBefore: sBefore,
    dBefore: dBefore,
    elapsedDays: elapsedDays,
  );

  test('recallRate: due reviews of the last 30 days, a pass is Hard or '
      'better', () {
    final day = DateTime.utc(2026, 3, 1);
    expect(recallRate(const [], now), isNull);
    expect(
      recallRate([
        entry('P:a', day, Rating.good),
        entry('P:b', day, Rating.hard),
        entry('P:c', day, Rating.again),
        entry('P:d', day, Rating.again, format: ReviewFormat.retrieval1),
        entry('P:e', DateTime.utc(2026, 1, 1), Rating.again),
        entry('P:f', day, Rating.good, format: ReviewFormat.relearn),
      ], now),
      closeTo(2 / 3, 1e-12),
    );
  });

  test('forecast: reviews due on each of the next days, overdue on today', () {
    CardState due(String id, DateTime at) => CardState(
      itemId: id,
      phase: CardPhase.review,
      memory: Memory(stability: 5, difficulty: 5, lastReview: at),
      dueAt: at,
    );
    final local = DateTime(2026, 3, 10, 9);
    expect(
      forecast(
        [
          due('P:a', DateTime(2026, 3, 8)),
          due('P:b', DateTime(2026, 3, 10, 23)),
          due('P:c', DateTime(2026, 3, 11, 1)),
          due('P:d', DateTime(2026, 3, 13, 12)),
          due('P:e', DateTime(2026, 4, 30)),
          introduce('P:f', local),
        ],
        local,
        days: 4,
      ),
      [2, 1, 0, 1],
    );
  });

  test('wholeCityBy: today plus the unseen core streets at the daily new '
      'number', () {
    final local = DateTime(2026, 3, 10, 9);
    expect(
      wholeCityBy(unseenCore: 25, newPerDay: 10, now: local),
      DateTime(2026, 3, 13),
    );
    expect(
      wholeCityBy(unseenCore: 0, newPerDay: 10, now: local),
      DateTime(2026, 3, 10),
    );
    expect(wholeCityBy(unseenCore: 5, newPerDay: 0, now: local), isNull);
  });

  group('memoryAt replays the log (SPEC §16.20)', () {
    const fsrs = Fsrs();
    final intro = DateTime.utc(2026, 3, 1, 9);

    test('nothing before the first answer, then each answer\'s memory', () {
      final r1 = applyReview(
        introduce('P:a', intro),
        itemId: 'P:a',
        rating: Rating.good,
        now: intro.add(const Duration(minutes: 2)),
        format: ReviewFormat.retrieval1,
        source: ReviewSource.session,
      );
      final pre = LogEntry(
        ts: intro.add(const Duration(minutes: 3)),
        itemId: 'P:a',
        format: ReviewFormat.pretest,
        rating: Rating.again,
        source: ReviewSource.session,
      );
      final r2 = applyReview(
        r1.card,
        itemId: 'P:a',
        rating: Rating.easy,
        now: DateTime.utc(2026, 3, 4, 9),
        format: ReviewFormat.review,
        source: ReviewSource.session,
      );
      final log = [r1.log, pre, r2.log];
      expect(memoryAt(r2.card, log, intro), isNull);
      final mid = memoryAt(r2.card, log, DateTime.utc(2026, 3, 2));
      expect(mid!.stability, r1.card.memory!.stability);
      expect(mid.lastReview, r1.log.ts);
      expect(memoryAt(r2.card, log, now), same(r2.card.memory));
    });

    test('a carried-over card counts from its creation, with or without '
        'reviews', () {
      final created = carriedOver('P:c', intro, Random(1));
      expect(
        memoryAt(created, const [], intro.subtract(const Duration(days: 1))),
        isNull,
      );
      expect(memoryAt(created, const [], now), same(created.memory));
      final reviewed = applyReview(
        created,
        itemId: 'P:c',
        rating: Rating.good,
        now: DateTime.utc(2026, 3, 5, 9),
        format: ReviewFormat.review,
        source: ReviewSource.session,
      );
      final before = memoryAt(reviewed.card, [
        reviewed.log,
      ], DateTime.utc(2026, 3, 3));
      expect(before!.stability, created.memory!.stability);
      expect(before.lastReview.difference(intro).inSeconds.abs(), lessThan(2));
      expect(
        memoryAt(reviewed.card, [
          reviewed.log,
        ], intro.subtract(const Duration(days: 1))),
        isNull,
      );
    });

    group('cityMemoryHistory (SPEC §16.4)', () {
      final r1 = applyReview(
        introduce('P:a', intro),
        itemId: 'P:a',
        rating: Rating.good,
        now: intro,
        format: ReviewFormat.retrieval1,
        source: ReviewSource.session,
      );
      MemoryHistory at(DateTime t) => cityMemoryHistory(
        cards: [r1.card],
        log: [r1.log],
        now: t,
        isCore: (_) => true,
      );
      double r(DateTime t) => fsrs.retrievability(r1.card.memory!, t);

      test('first two weeks: a 14-day frame ending today, a point a day '
          'since the first answer (each past day at its end)', () {
        final history = at(now);
        expect(history.window, MemoryWindow.daily);
        expect(history.days, 14);
        expect(history.start, DateTime.utc(2026, 2, 25));
        // 1 to 10 March.
        expect(history.points, hasLength(10));
        expect(history.points.first.at, closeTo(4 / 13, 1e-9));
        expect(
          history.points.first.value,
          closeTo(r(DateTime.utc(2026, 3, 2)), 1e-9),
        );
        expect(history.points.last.at, 1);
        expect(history.points.last.value, closeTo(r(now), 1e-9));
      });

      test('the first day alone is one point at today', () {
        final history = at(intro.add(const Duration(hours: 2)));
        expect(history.points, hasLength(1));
        expect(history.points.single.at, 1);
      });

      test('from day 15: a point a week from the first answer, then now', () {
        final t = intro.add(const Duration(days: 30));
        final history = at(t);
        expect(history.window, MemoryWindow.weekly);
        expect(history.days, 0);
        expect(history.start, intro);
        expect(
          [for (final p in history.points) p.at],
          [
            0,
            closeTo(7 / 30, 1e-9),
            closeTo(14 / 30, 1e-9),
            closeTo(21 / 30, 1e-9),
            closeTo(28 / 30, 1e-9),
            1,
          ],
        );
        expect(history.points.first.value, closeTo(1, 1e-9));
      });

      test('from week 10: the last 10 weeks, 11 points', () {
        final t = intro.add(const Duration(days: 100));
        final history = at(t);
        expect(history.window, MemoryWindow.lastWeeks);
        expect(history.start, t.subtract(const Duration(days: 70)));
        expect(history.points, hasLength(11));
        expect(history.points.last.value, closeTo(r(t), 1e-9));
      });

      test('no play: one point of 0', () {
        final empty = cityMemoryHistory(
          cards: const [],
          log: const [],
          now: now,
          isCore: (_) => true,
        );
        expect(empty.points, [(at: 1.0, value: 0.0)]);
        expect(empty.window, MemoryWindow.daily);
      });
    });
  });
}
