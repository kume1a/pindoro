import 'dart:math';

import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

final now = DateTime.utc(2026, 3, 2, 9);

/// A reviewed card [overdueDays] past its due date (negative: due later), with stability [s].
CardState due(String id, {double overdueDays = 0, double s = 5}) {
  final dueAt = now.subtract(
    Duration(minutes: (overdueDays * 24 * 60).round()),
  );
  return CardState(
    itemId: CardType.p.item(id),
    phase: CardPhase.review,
    memory: Memory(
      stability: s,
      difficulty: 5,
      lastReview: dueAt.subtract(Duration(days: s.round())),
    ),
    dueAt: dueAt,
    reps: 3,
  );
}

List<CardState> dueCards(int n) => [
  for (var i = 0; i < n; i++) due('d$i', overdueDays: i / 10),
];

List<String> candidates(int n) => [
  for (var i = 0; i < n; i++) CardType.p.item('n$i'),
];

SessionPlan plan({
  List<CardState> cards = const [],
  List<String>? fresh,
  int minutes = 20,
  int seed = 1,
  int introducedToday = 0,
  int spentTodayS = 0,
  int? extraNew,
  int tReviewS = LearningConfig.tReviewS,
  int tNewS = LearningConfig.tNewS,
}) => Planner.plan(
  cards: cards,
  newCandidates: fresh ?? candidates(30),
  minutesPerDay: minutes,
  now: now,
  seed: seed,
  introducedToday: introducedToday,
  spentTodayS: spentTodayS,
  extraNew: extraNew,
  tReviewS: tReviewS,
  tNewS: tNewS,
);

Iterable<String> ofKind(SessionPlan p, StepKind kind) =>
    p.steps.where((s) => s.kind == kind).map((s) => s.itemId);

void main() {
  group('normal mode (SPEC §7)', () {
    test('takes every due review and up to nBase new streets', () {
      final p = plan(cards: dueCards(10));
      expect(p.backlog, isFalse);
      expect(p.dueCount, 10);
      expect(p.reviewCount, 10);
      expect(p.newCount, 10);
      expect(ofKind(p, StepKind.intro), hasLength(10));
      expect(ofKind(p, StepKind.retrieval1), hasLength(10));
      expect(ofKind(p, StepKind.retrieval2), hasLength(10));
      expect(ofKind(p, StepKind.review), hasLength(10));
      expect(p.estimatedS, 10 * 12 + 10 * 45);
    });

    test('nBase follows the minutes: 7 / 10 / 14', () {
      expect(plan(minutes: 15).newCount, 7);
      expect(plan(minutes: 20).newCount, 10);
      expect(plan(minutes: 30).newCount, 14);
    });

    test('new streets shrink to the time left after reviews', () {
      expect(plan(cards: dueCards(80)).newCount, (1200 - 80 * 12) ~/ 45);
      expect(plan(cards: dueCards(100)).newCount, 0);
      expect(plan(cards: dueCards(100)).backlog, isFalse);
    });

    test(
      'new streets come in candidate order and skip ones already carded',
      () {
        final carded = due('n1', overdueDays: -3);
        final p = plan(cards: [carded], fresh: candidates(5), minutes: 15);
        expect(ofKind(p, StepKind.intro), ['P:n0', 'P:n2', 'P:n3', 'P:n4']);
      },
    );
  });

  test('Learn 5 more: five new streets past the daily number and the '
      'minutes', () {
    final p = plan(introducedToday: 10, spentTodayS: 1200, extraNew: 5);
    expect(p.newCount, 5);
    expect(ofKind(p, StepKind.intro), hasLength(5));
  });

  test('catchUpDays: the due reviews in days of the minutes', () {
    expect(catchUpDays(dueCount: 186, minutesPerDay: 20), 2);
    expect(catchUpDays(dueCount: 300, minutesPerDay: 15), 4);
  });

  group('backlog mode', () {
    test(
      'no new streets, at most budget × 1.5 of reviews, most at risk first',
      () {
        final cards = [
          for (var i = 0; i < 200; i++)
            due('d$i', overdueDays: (i % 37).toDouble(), s: 1 + i % 13),
        ];
        final p = plan(cards: cards);
        expect(p.backlog, isTrue);
        expect(p.dueCount, 200);
        expect(p.newCount, 0);
        expect(p.reviewCount, (1200 * 1.5 / 12).floor());
        const fsrs = Fsrs();
        final r = {
          for (final c in cards) c.itemId: fsrs.retrievability(c.memory!, now),
        };
        final reviewed = ofKind(p, StepKind.review).toList();
        for (var i = 1; i < reviewed.length; i++) {
          expect(r[reviewed[i]]!, greaterThanOrEqualTo(r[reviewed[i - 1]]!));
        }
        final left = cards
            .map((c) => c.itemId)
            .toSet()
            .difference(reviewed.toSet());
        expect(
          left.map((id) => r[id]!).reduce(min),
          greaterThanOrEqualTo(r[reviewed.last]!),
        );
      },
    );
  });

  group('what counts as due', () {
    test('due before the next local midnight, never suspended or tomorrow', () {
      final laterToday = due('later', overdueDays: -0.5);
      final tomorrow = due('tomorrow', overdueDays: -1.2);
      final suspended = CardState(
        itemId: 'P:sus',
        phase: CardPhase.suspended,
        memory: Memory(stability: 1, difficulty: 9, lastReview: now),
        dueAt: now.subtract(const Duration(days: 3)),
      );
      final p = plan(cards: [laterToday, tomorrow, suspended], fresh: const []);
      expect(ofKind(p, StepKind.review), ['P:later']);
    });

    test(
      'a street left in learning gets retrieval 1 first, then retrieval 2',
      () {
        final left = introduce(
          'P:left',
          now.subtract(const Duration(hours: 20)),
        );
        final p = plan(cards: [left, ...dueCards(3)], fresh: const []);
        expect(p.steps.first.kind, StepKind.retrieval1);
        expect(p.steps.first.itemId, 'P:left');
        expect(p.steps.last, (kind: StepKind.retrieval2, itemId: 'P:left'));
        expect(ofKind(p, StepKind.intro), isEmpty);
      },
    );
  });

  group('interleaving (SPEC §7, §16.6)', () {
    test(
      '3 intros, reviews, retrieval 1 after 3–6 other items, retrieval 2s last',
      () {
        for (final dueN in [12, 25, 40, 60]) {
          for (var seed = 0; seed < 40; seed++) {
            final p = plan(cards: dueCards(dueN), seed: seed);
            final steps = p.steps;
            final why = '$dueN due, seed $seed';
            expect(
              steps.take(3).map((s) => s.kind),
              everyElement(StepKind.intro),
            );
            for (final id in ofKind(p, StepKind.intro)) {
              final intro = steps.indexOf((kind: StepKind.intro, itemId: id));
              final r1 = steps.indexOf((kind: StepKind.retrieval1, itemId: id));
              expect(
                r1 - intro - 1,
                inInclusiveRange(3, 6),
                reason: '$id, $why',
              );
            }
            final firstR2 = steps.indexWhere(
              (s) => s.kind == StepKind.retrieval2,
            );
            expect(
              steps.skip(firstR2).map((s) => s.kind),
              everyElement(isIn([StepKind.retrieval1, StepKind.retrieval2])),
              reason: why,
            );
            for (final id in ofKind(p, StepKind.intro)) {
              expect(
                steps.indexOf((kind: StepKind.retrieval2, itemId: id)),
                greaterThan(
                  steps.indexOf((kind: StepKind.retrieval1, itemId: id)),
                ),
                reason: '$id, $why',
              );
            }
            expect(
              ofKind(p, StepKind.retrieval2).toSet(),
              ofKind(p, StepKind.intro).toSet(),
            );
          }
        }
      },
    );

    test('reviews sit between groups of new streets', () {
      final steps = plan(cards: dueCards(25)).steps;
      final kinds = steps.map((s) => s.kind).toList();
      final secondGroup = kinds.indexWhere((k) => k == StepKind.intro, 3);
      expect(kinds.sublist(3, secondGroup), contains(StepKind.review));
    });

    test(
      'with few items, retrieval 1 still waits for 2 others when it can',
      () {
        final steps = plan(
          fresh: candidates(3),
          minutes: 15,
        ).steps.take(7).toList();
        expect(steps.map((s) => s.kind).take(3), everyElement(StepKind.intro));
        for (final id in ['P:n0', 'P:n1']) {
          final intro = steps.indexOf((kind: StepKind.intro, itemId: id));
          final r1 = steps.indexOf((kind: StepKind.retrieval1, itemId: id));
          expect(r1 - intro - 1, greaterThanOrEqualTo(2), reason: id);
        }
      },
    );

    test('the same inputs and seed give the same session', () {
      expect(
        plan(cards: dueCards(25), seed: 7).steps,
        plan(cards: dueCards(25), seed: 7).steps,
      );
      final seeds = {
        for (var s = 0; s < 10; s++)
          plan(cards: dueCards(25), seed: s).steps.join(),
      };
      expect(seeds.length, greaterThan(1));
    });
  });

  group('several sessions a day (SPEC §16.8)', () {
    test('streets introduced today come off the daily number', () {
      expect(plan(introducedToday: 4).newCount, 6);
      expect(plan(introducedToday: 12).newCount, 0);
    });

    test('minutes already spent come off the budget', () {
      final p = plan(cards: dueCards(40), spentTodayS: 700);
      expect(p.backlog, isFalse);
      expect(p.newCount, 0);
      final spent = plan(cards: dueCards(10), spentTodayS: 1200);
      expect(spent.backlog, isTrue);
      expect(spent.steps, isEmpty);
    });
  });

  group('relearn after Again', () {
    final rest = [
      for (var i = 0; i < 12; i++) (kind: StepKind.review, itemId: 'P:r$i'),
    ];

    test('comes back after 5–10 other items', () {
      for (var seed = 0; seed < 30; seed++) {
        final next = Planner.withRelearn(rest, 'P:x', Random(seed));
        final at = next.indexOf((kind: StepKind.relearn, itemId: 'P:x'));
        expect(at, inInclusiveRange(5, 10));
        expect(next, hasLength(rest.length + 1));
      }
    });

    test('goes last when fewer than 5 items are left', () {
      final next = Planner.withRelearn(rest.take(3).toList(), 'P:x', Random(1));
      expect(next.last, (kind: StepKind.relearn, itemId: 'P:x'));
    });

    test('comes before its own retrieval 2', () {
      final withR2 = [
        ...rest.take(2),
        (kind: StepKind.retrieval2, itemId: 'P:x'),
        ...rest,
      ];
      for (var seed = 0; seed < 30; seed++) {
        final next = Planner.withRelearn(withR2, 'P:x', Random(seed));
        final relearn = next.indexOf((kind: StepKind.relearn, itemId: 'P:x'));
        final r2 = next.indexOf((kind: StepKind.retrieval2, itemId: 'P:x'));
        expect(relearn, lessThan(r2));
      }
    });
  });

  test('nextMidnight is the start of the next calendar day', () {
    expect(
      nextMidnight(DateTime.utc(2026, 3, 2, 23, 59)),
      DateTime.utc(2026, 3, 3),
    );
    expect(nextMidnight(DateTime(2026, 12, 31, 8)), DateTime(2027));
  });

  group('today so far (SPEC §16.8, §16.9)', () {
    LogEntry answer(String session, DateTime at) => LogEntry(
      ts: at,
      itemId: 'P:x',
      format: ReviewFormat.review,
      rating: Rating.good,
      source: ReviewSource.session,
      sessionId: session,
    );

    test('introducedToday counts intros since local midnight', () {
      final cards = [
        introduce('P:a', now.subtract(const Duration(hours: 2))),
        introduce('P:b', now.subtract(const Duration(hours: 10))),
        due('c'),
      ];
      expect(introducedToday(cards, now), 1);
    });

    test('the daily day counts once something was answered and nothing is '
        'due, or the minutes are spent (SPEC §8)', () {
      final today = [answer('s1', now.subtract(const Duration(minutes: 5)))];
      expect(
        dayCounts(
          cards: const [],
          today: const [],
          minutesPerDay: 20,
          now: now,
        ),
        isFalse,
      );
      expect(
        dayCounts(cards: const [], today: today, minutesPerDay: 20, now: now),
        isTrue,
      );
      final stillDue = [due('a')];
      expect(
        dayCounts(cards: stillDue, today: today, minutesPerDay: 20, now: now),
        isFalse,
      );
      final long = [
        for (var i = 0; i <= 40; i++)
          answer('s1', now.subtract(Duration(seconds: 30 * (40 - i)))),
      ];
      expect(
        dayCounts(cards: stillDue, today: long, minutesPerDay: 20, now: now),
        isTrue,
      );
    });

    test('time estimates follow the log medians once there are 50 reviews', () {
      final start = DateTime.utc(2026, 3, 1, 8);
      List<LogEntry> reviews(int n, int gapS) => [
        for (var i = 0; i <= n; i++)
          answer('s', start.add(Duration(seconds: gapS * i))),
      ];
      expect(timeEstimates(reviews(10, 6)), (
        tReviewS: LearningConfig.tReviewS,
        tNewS: LearningConfig.tNewS,
      ));
      expect(timeEstimates(reviews(60, 6)), (tReviewS: 6, tNewS: 23));
    });

    test('spentTodayS sums the gaps between answers, each capped at 60 s', () {
      final start = DateTime.utc(2026, 3, 2, 8);
      final log = [
        answer('yesterday', DateTime.utc(2026, 3, 1, 23, 59, 50)),
        answer('yesterday', DateTime.utc(2026, 3, 2, 0, 0, 10)),
        answer('s1', start),
        answer('s1', start.add(const Duration(seconds: 12))),
        answer('s1', start.add(const Duration(seconds: 30))),
        answer('s1', start.add(const Duration(minutes: 30))),
        answer('s2', start.add(const Duration(hours: 1))),
        answer('s2', start.add(const Duration(hours: 1, seconds: 20))),
      ];
      expect(spentTodayS(log, now), 12 + 18 + 60 + 20);
    });
  });

  test('remainingSeconds: 12 s a review, 15 s an intro or retrieval', () {
    final steps = [
      (kind: StepKind.intro, itemId: 'P:a'),
      (kind: StepKind.review, itemId: 'P:b'),
      (kind: StepKind.retrieval1, itemId: 'P:a'),
      (kind: StepKind.relearn, itemId: 'P:b'),
      (kind: StepKind.retrieval2, itemId: 'P:a'),
    ];
    expect(remainingSeconds(steps), 15 + 12 + 15 + 12 + 15);
    expect(remainingSeconds(const []), 0);
  });

  group('finishedBlocks', () {
    test('24 steps: 2 per block, a block with a forgotten answer is red', () {
      expect(finishedBlocks(total: 24, answered: 0, forgotten: {}), isEmpty);
      expect(finishedBlocks(total: 24, answered: 1, forgotten: {}), isEmpty);
      expect(finishedBlocks(total: 24, answered: 5, forgotten: {3}), [
        false,
        true,
      ]);
      expect(
        finishedBlocks(total: 24, answered: 24, forgotten: {}),
        hasLength(12),
      );
    });

    test('fewer steps than blocks still ends with all 12 done', () {
      expect(
        finishedBlocks(total: 5, answered: 5, forgotten: {}),
        hasLength(12),
      );
      expect(finishedBlocks(total: 5, answered: 0, forgotten: {}), isEmpty);
      expect(finishedBlocks(total: 5, answered: 1, forgotten: {0}), [
        true,
        false,
      ]);
    });
  });
}
