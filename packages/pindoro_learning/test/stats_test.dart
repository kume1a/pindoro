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
}
