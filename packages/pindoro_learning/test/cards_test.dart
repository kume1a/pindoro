import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime.utc(2026, 3, 2, 9);
  const fsrs = Fsrs();
  final itemId = CardType.p.item('street-1');

  ({CardState card, LogEntry log}) rate(
    CardState? card,
    Rating rating,
    DateTime at, {
    ReviewFormat format = ReviewFormat.review,
  }) => applyReview(
    card,
    itemId: itemId,
    rating: rating,
    now: at,
    format: format,
    source: ReviewSource.session,
    sessionId: 's1',
  );

  group('item ids', () {
    test('carry the card type and its key', () {
      expect(itemId, 'P:street-1');
      expect(CardType.ofItem(itemId), CardType.p);
      expect(itemKey(itemId), 'street-1');
      expect(CardType.ofItem(CardType.r.item('n1:n2')), CardType.r);
      expect(itemKey('J:n123:n456'), 'n123:n456');
    });
  });

  test('an intro opens a learning card with no memory and no log row', () {
    final card = introduce(itemId, t0);
    expect(card.phase, CardPhase.learning);
    expect(card.memory, isNull);
    expect(card.introAt, t0);
    expect(card.reps, 0);
  });

  test('retrieval 1 is the first FSRS review and keeps the intro time', () {
    final at = t0.add(const Duration(minutes: 3));
    final r = rate(
      introduce(itemId, t0),
      Rating.good,
      at,
      format: ReviewFormat.retrieval1,
    );
    final expected = fsrs.next(null, Rating.good, at);
    expect(r.card.phase, CardPhase.review);
    expect(r.card.memory!.stability, expected.memory.stability);
    expect(r.card.memory!.difficulty, expected.memory.difficulty);
    expect(r.card.dueAt, expected.due);
    expect(r.card.introAt, t0);
    expect(r.card.reps, 1);
    expect(r.card.lastRating, Rating.good);
    expect(r.log.format, ReviewFormat.retrieval1);
    expect(r.log.elapsedDays, isNull);
    expect(r.log.rBefore, isNull);
    expect(r.log.sBefore, isNull);
    expect(r.log.dBefore, isNull);
  });

  test(
    'a later review logs the memory before it, with fractional elapsed days',
    () {
      final first = rate(introduce(itemId, t0), Rating.good, t0).card;
      final at = t0.add(const Duration(days: 2, hours: 12));
      final r = rate(first, Rating.good, at);
      expect(r.log.elapsedDays, 2.5);
      expect(r.log.sBefore, first.memory!.stability);
      expect(r.log.dBefore, first.memory!.difficulty);
      expect(r.log.rBefore, fsrs.retrievability(first.memory!, at));
      expect(r.log.sessionId, 's1');
      expect(r.log.source, ReviewSource.session);
      expect(r.card.reps, 2);
    },
  );

  test('Again on a review card is a lapse and needs a relearn', () {
    final reviewed = rate(introduce(itemId, t0), Rating.good, t0).card;
    final r = rate(reviewed, Rating.again, t0.add(const Duration(days: 2)));
    expect(r.card.lapses, 1);
    expect(r.card.phase, CardPhase.relearning);
  });

  test('Again on retrieval 1 or on a relearn is not a lapse', () {
    final first = rate(introduce(itemId, t0), Rating.again, t0).card;
    expect(first.lapses, 0);
    expect(first.phase, CardPhase.relearning);
    final again = rate(
      first,
      Rating.again,
      t0.add(const Duration(minutes: 5)),
    ).card;
    expect(again.lapses, 0);
    final relearned = rate(
      again,
      Rating.good,
      t0.add(const Duration(minutes: 9)),
    ).card;
    expect(relearned.phase, CardPhase.review);
  });

  test('a first-sight success (placement) creates the card as prior known', () {
    final r = applyReview(
      null,
      itemId: itemId,
      rating: Rating.easy,
      now: t0,
      format: ReviewFormat.placement,
      source: ReviewSource.placement,
      priorKnown: true,
    );
    expect(r.card.priorKnown, isTrue);
    expect(r.card.introAt, isNull);
    expect(r.card.memory!.stability, closeTo(8.2956, 1e-9));
  });

  test('the answer details reach the card and the log', () {
    final r = applyReview(
      introduce(itemId, t0),
      itemId: itemId,
      rating: Rating.hard,
      now: t0,
      format: ReviewFormat.retrieval1,
      source: ReviewSource.session,
      distanceM: 42.5,
      snapId: 'street-2',
      rtMs: 7100,
    );
    expect(r.card.lastDistanceM, 42.5);
    expect(r.card.lastSnapId, 'street-2');
    expect(r.log.distanceM, 42.5);
    expect(r.log.snapId, 'street-2');
    expect(r.log.rtMs, 7100);
    expect(r.log.rating, Rating.hard);
    expect(r.log.ts, t0);
    expect(r.log.itemId, itemId);
  });

  test(
    'fuzz is seeded by the item and the time, so a replay gives the same due date',
    () {
      final reviewed = CardState(
        itemId: itemId,
        phase: CardPhase.review,
        memory: Memory(stability: 100, difficulty: 5, lastReview: t0),
      );
      final at = t0.add(const Duration(days: 100));
      final dues = {
        for (var i = 0; i < 2; i++) rate(reviewed, Rating.good, at).card.dueAt,
      };
      expect(dues, hasLength(1));
      final plain = fsrs.next(reviewed.memory, Rating.good, at).intervalDays;
      final fuzzed = rate(
        reviewed,
        Rating.good,
        at,
      ).card.dueAt!.difference(at).inDays;
      expect((fuzzed - plain).abs(), lessThanOrEqualTo(plain * 0.05 + 0.5));
    },
  );

  test('a street the old game knew: Good, prior knowledge, due in 1–7 '
      'days', () {
    final random = Random(3);
    final cards = [
      for (var i = 0; i < 40; i++) carriedOver('P:s$i', t0, random),
    ];
    final first = cards.first;
    expect(first.phase, CardPhase.review);
    expect(first.priorKnown, isTrue);
    expect(first.introAt, isNull);
    expect(first.lastRating, Rating.good);
    expect(
      first.memory!.stability,
      fsrs.next(null, Rating.good, t0).memory.stability,
    );
    final days = {for (final c in cards) c.dueAt!.difference(t0).inDays};
    expect(days, {1, 2, 3, 4, 5, 6, 7});
  });

  group('Explore answers (SPEC §16.16)', () {
    PinGrade grade(Rating rating) => PinGrade(
      tier: rating.isSuccess ? Tier.great : Tier.miss,
      rating: rating,
      distanceM: rating.isSuccess ? 40 : 900,
      snapStreetId: null,
      isMixUp: false,
    );
    ({CardState? card, LogEntry log}) explore(
      CardState? card,
      Rating r,
      DateTime at,
    ) => exploreAnswer(
      card,
      itemId: itemId,
      grade: grade(r),
      now: at,
      rtMs: 5000,
    );

    test('a first-sight Good creates a prior-known card; a miss is only '
        'logged', () {
      final made = explore(null, Rating.good, t0);
      expect(made.card!.priorKnown, isTrue);
      expect(made.log.format, ReviewFormat.explore);
      final missed = explore(null, Rating.again, t0);
      expect(missed.card, isNull);
      expect(missed.log.format, ReviewFormat.exploreLog);
      expect(changesSchedule(missed.log), isFalse);
    });

    test('a card far from due is only logged; near or past due it is '
        'reviewed', () {
      final card = rate(
        null,
        Rating.good,
        t0,
        format: ReviewFormat.retrieval1,
      ).card;
      final interval = card.dueAt!.difference(t0);
      final early = explore(card, Rating.good, t0.add(interval * 0.2));
      expect(early.card, isNull);
      expect(early.log.format, ReviewFormat.exploreLog);
      final near = explore(card, Rating.good, t0.add(interval * 0.6));
      expect(near.card!.reps, card.reps + 1);
      expect(near.log.format, ReviewFormat.explore);
      expect(near.log.source, ReviewSource.explore);
    });

    test('a card still waiting for retrieval 1 is left to the session', () {
      expect(explore(introduce(itemId, t0), Rating.good, t0).card, isNull);
    });
  });

  group('leeches (SPEC §4)', () {
    test(
      'every 6th lapse suspends; a re-intro relearns on the kept memory',
      () {
        var card = rate(null, Rating.good, t0).card;
        var at = t0;
        for (var lapse = 1; lapse <= LearningConfig.leechLapses; lapse++) {
          at = at.add(const Duration(days: 3));
          card = rate(card, Rating.again, at).card;
          expect(
            card.phase,
            lapse < LearningConfig.leechLapses
                ? CardPhase.relearning
                : CardPhase.suspended,
          );
          if (card.phase == CardPhase.relearning) {
            at = at.add(const Duration(days: 1));
            card = rate(card, Rating.good, at).card;
          }
        }
        expect(card.lapses, LearningConfig.leechLapses);
        final back = reintroduce(
          card,
          at.add(const Duration(days: 1)),
          note: 'by the bakery',
        );
        expect(back.phase, CardPhase.relearning);
        expect(back.memory, card.memory);
        expect(back.note, 'by the bakery');
        expect(isDueBefore(back, at.add(const Duration(days: 2))), isTrue);
        final relearnt = rate(
          back,
          Rating.good,
          at.add(const Duration(days: 1)),
        );
        expect(
          relearnt.card.note,
          'by the bakery',
          reason: 'answers keep the note',
        );
        expect(relearnt.card.phase, CardPhase.review);
      },
    );
  });
}
