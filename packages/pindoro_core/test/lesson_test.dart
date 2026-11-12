import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';
import 'package:test/test.dart';

NamedStreet _street(
  String id, {
  String? name,
  List<LatLng> line = const [LatLng(41.7, 44.8), LatLng(41.701, 44.8)],
  String roadClass = 'residential',
}) => NamedStreet([
  Street(
    id: id,
    nameKa: name ?? 'name $id',
    nameEn: null,
    roadClass: roadClass,
    difficulty: Difficulty.expert,
    lengthM: 500,
    midpoint: line[line.length ~/ 2],
    bbox: Bbox.of(line),
    geometry: [line],
  ),
]);

final _at = DateTime(2026, 11, 9, 10);

/// A road trip to [destination]; its route is never drawn here.
Trip _tripTo(NamedStreet destination) => (
  from: 0,
  to: 1,
  destination: destination,
  best: const Route([0, 1], [], 500),
);

void main() {
  final streets = [for (final id in 'abcd'.split('')) _street(id)];
  final unit = [
    ...streets,
    for (final id in 'efgh'.split('')) _street(id),
    _street('dup', name: 'name a'),
  ];

  group('planLesson', () {
    test(
      '4 cards, then a pin on each street and 2 names, never twice in a row',
      () {
        for (var seed = 0; seed < 200; seed++) {
          final steps = planLesson(
            kind: LessonKind.lesson,
            streets: streets,
            unitStreets: unit,
            random: Random(seed),
          );
          expect(steps.take(4).map((s) => (s as CardStep).number), [
            1,
            2,
            3,
            4,
          ]);
          expect(steps.take(4).map((s) => s.street.id), ['a', 'b', 'c', 'd']);
          final tests = steps.skip(4).toList();
          expect(tests, hasLength(6));
          expect(tests.whereType<PinStep>().map((s) => s.street.id).toSet(), {
            'a',
            'b',
            'c',
            'd',
          });
          expect(tests.whereType<NameStep>(), hasLength(2));
          for (var i = 1; i < tests.length; i++) {
            expect(tests[i].street.id, isNot(tests[i - 1].street.id));
          }
        }
      },
    );

    test('the road trip comes last; a Pit stop has none', () {
      final trip = _tripTo(streets[2]);
      for (final kind in [LessonKind.lesson, LessonKind.practice]) {
        final steps = planLesson(
          kind: kind,
          streets: streets,
          unitStreets: unit,
          trip: trip,
          random: Random(3),
        );
        expect(steps.last, isA<TripStep>().having((s) => s.trip, 'trip', trip));
        expect(steps.whereType<TripStep>(), hasLength(1));
      }
      expect(
        planLesson(
          kind: LessonKind.pitStop,
          streets: streets,
          unitStreets: unit,
          trip: trip,
        ).whereType<TripStep>(),
        isEmpty,
      );
    });

    test('name options: the answer and two other names', () {
      for (var seed = 0; seed < 50; seed++) {
        final steps = planLesson(
          kind: LessonKind.lesson,
          streets: streets,
          unitStreets: unit,
          random: Random(seed),
        );
        for (final step in steps.whereType<NameStep>()) {
          expect(step.options, hasLength(3));
          expect(step.options, contains(step.street));
          expect(step.options.map((s) => s.name).toSet(), hasLength(3));
        }
      }
    });

    test('practice has no cards; a Pit stop is pins with last distances', () {
      final practice = planLesson(
        kind: LessonKind.practice,
        streets: streets,
        unitStreets: unit,
      );
      expect(practice.whereType<CardStep>(), isEmpty);
      expect(practice, hasLength(6));
      final pitStop = planLesson(
        kind: LessonKind.pitStop,
        streets: streets.take(2).toList(),
        unitStreets: unit,
        lastDistances: const {'a': 240},
      );
      expect(pitStop.map((s) => (s as PinStep).lastDistanceM), [240, null]);
    });
  });

  group('LessonRun', () {
    LessonRun play(
      LessonKind kind,
      List<LessonStep> steps, {
      Tier Function(TestStep step)? tierFor,
    }) {
      var run = LessonRun(kind, steps);
      while (!run.finished) {
        final step = run.step;
        if (step is TestStep) {
          final tier = tierFor?.call(step) ?? Tier.perfect;
          run = switch (step) {
            PinStep() => run.answerPin(
              (
                tier: tier,
                xp: tier == Tier.perfect
                    ? 100
                    : tier == Tier.close
                    ? 40
                    : 0,
              ),
              tier == Tier.perfect ? 0 : 250,
              _at,
            ),
            NameStep() => run.answerName(right: tier != Tier.miss, at: _at),
            TripStep() => run.answerTrip((
              tier: tier,
              xp: tier == Tier.perfect
                  ? 100
                  : tier == Tier.close
                  ? 40
                  : 0,
            ), _at),
          };
          expect(run.answered, isTrue);
        }
        run = run.next();
      }
      return run;
    }

    final steps = [
      for (final (i, s) in streets.indexed) CardStep(s, i + 1),
      PinStep(streets[0]),
      NameStep(streets[1], [streets[1], streets[2], streets[3]]),
      PinStep(streets[1]),
      PinStep(streets[2]),
      NameStep(streets[3], [streets[3], streets[0], streets[1]]),
      PinStep(streets[3]),
    ];

    final withTrip = [...steps, TripStep(_tripTo(streets[2]))];

    test('a Perfect lesson earns every step, +20 and +50', () {
      final run = play(LessonKind.lesson, withTrip);
      expect(run.steps, hasLength(11));
      expect(run.perfect, isTrue);
      expect(run.stepXp, 4 * 100 + 2 * 50 + 100);
      expect(run.xp, LessonRules.maxXp);
      expect(LessonRules.maxXp, 670);
      expect((run.tests, run.rightFirst), (7, 7));
    });

    test('a Miss road trip comes back as the same trip at half XP', () {
      final run = play(
        LessonKind.lesson,
        withTrip,
        tierFor: (step) => switch (step) {
          TripStep(fix: false) => Tier.miss,
          _ => Tier.perfect,
        },
      );
      final fix = run.steps.last as TripStep;
      expect(fix.fix, isTrue);
      expect(fix.trip, (withTrip.last as TripStep).trip);
      expect(run.answers.last.xp, 50);
      expect(run.answers.last.distanceM, isNull);
      expect(run.perfect, isFalse);
      expect((run.tests, run.rightFirst), (7, 6));
    });

    test('a Close road trip is no mistake', () {
      final run = play(
        LessonKind.lesson,
        withTrip,
        tierFor: (step) => step is TripStep ? Tier.close : Tier.perfect,
      );
      expect(run.mistakes, isEmpty);
      expect(run.perfect, isTrue);
      expect(run.stepXp, 4 * 100 + 2 * 50 + 40);
      expect((run.tests, run.rightFirst), (7, 7));
    });

    test('mistakes come back once, in order, at half XP', () {
      var answeredFixes = 0;
      final run = play(
        LessonKind.lesson,
        steps,
        tierFor: (step) => switch (step) {
          TestStep(fix: true) => [Tier.perfect, Tier.miss][answeredFixes++],
          PinStep(street: final s) when s.id == 'c' => Tier.close,
          NameStep(street: final s) when s.id == 'b' => Tier.miss,
          _ => Tier.perfect,
        },
      );
      final fixes = run.steps.skip(10).cast<TestStep>().toList();
      expect(fixes.map((s) => (s.runtimeType, s.street.id, s.fix)), [
        (NameStep, 'b', true),
        (PinStep, 'c', true),
      ]);
      expect((fixes.last as PinStep).lastDistanceM, 250);
      expect(run.total, 12);
      expect(run.mistakes, hasLength(2));
      expect(run.perfect, isFalse);
      // Pins 100 + 100 + 40 + 100, name 0 + 50, fixes 25 + 0.
      expect(run.stepXp, 340 + 50 + 25);
      expect(run.fixXp, 25);
      expect(run.bonusXp, 20);
      expect((run.tests, run.rightFirst), (6, 4));
    });

    test(
      'the bar counts the fixes to come; the fixes start after the last step',
      () {
        var run = LessonRun(LessonKind.lesson, steps);
        for (var i = 0; i < 4; i++) {
          run = run.next();
        }
        run = run.answerPin((tier: Tier.miss, xp: 0), 900, _at);
        expect(run.total, 11);
        for (var i = 0; i < 6; i++) {
          if (!run.answered && run.step is TestStep) {
            run = run.step is PinStep
                ? run.answerPin((tier: Tier.perfect, xp: 100), 0, _at)
                : run.answerName(right: true, at: _at);
          }
          run = run.next();
        }
        expect(run.startsFixes, isTrue);
        expect(run.step, isA<PinStep>().having((s) => s.fix, 'fix', isTrue));
      },
    );

    test('practice: half XP, no fixes, no bonus', () {
      final run = play(
        LessonKind.practice,
        withTrip.skip(4).toList(),
        tierFor: (step) => step is NameStep ? Tier.miss : Tier.perfect,
      );
      expect(run.steps, hasLength(7));
      expect(run.mistakes, isEmpty);
      expect(run.xp, 4 * 50 + 50);
      expect(run.perfect, isFalse);
    });
  });

  group('reviewAnswers', () {
    final steps = [
      PinStep(streets[0]),
      NameStep(streets[1], [streets[1], streets[2], streets[3]]),
    ];

    LessonRun twoMistakes(LessonKind kind, {required bool fixRight}) {
      var run = LessonRun(kind, steps)
          .answerPin((tier: Tier.miss, xp: 0), 900, _at)
          .next()
          .answerName(right: false, at: _at)
          .next();
      if (kind != LessonKind.lesson) return run;
      run = fixRight
          ? run.answerPin((tier: Tier.great, xp: 80), 50, _at)
          : run.answerPin((tier: Tier.close, xp: 40), 200, _at);
      return run.next().answerName(right: fixRight, at: _at).next();
    }

    test('a lesson sends only fixes wrong again', () {
      expect(
        reviewAnswers(
          twoMistakes(LessonKind.lesson, fixRight: false),
          inPitStop: const {},
        ),
        [(streetId: 'a', tier: Tier.close), (streetId: 'b', tier: Tier.miss)],
      );
      expect(
        reviewAnswers(
          twoMistakes(LessonKind.lesson, fixRight: true),
          inPitStop: const {},
        ),
        isEmpty,
      );
    });

    test('a street already in the Pit stop takes every answer', () {
      expect(
        reviewAnswers(
          twoMistakes(LessonKind.lesson, fixRight: true),
          inPitStop: const {'a'},
        ),
        [(streetId: 'a', tier: Tier.miss), (streetId: 'a', tier: Tier.great)],
      );
    });

    test('never a road trip', () {
      final run = LessonRun(LessonKind.practice, [
        TripStep(_tripTo(streets[0])),
      ]).answerTrip((tier: Tier.miss, xp: 0), _at).next();
      expect(reviewAnswers(run, inPitStop: const {'a'}), isEmpty);
    });

    test('practice gives every answer', () {
      expect(
        reviewAnswers(
          twoMistakes(LessonKind.practice, fixRight: false),
          inPitStop: const {},
        ),
        [(streetId: 'a', tier: Tier.miss), (streetId: 'b', tier: Tier.miss)],
      );
    });
  });

  group('card facts', () {
    test('road types', () {
      expect(roadTypeOf('trunk'), RoadType.mainRoad);
      expect(roadTypeOf('primary'), RoadType.mainRoad);
      expect(roadTypeOf('tertiary'), RoadType.street);
      expect(roadTypeOf('residential'), RoadType.sideStreet);
    });

    test('crossings: lines that cross or touch, once per name', () {
      const west = LatLng(41.700, 44.800);
      const east = LatLng(41.700, 44.810);
      final main = _street('main', line: const [west, east]);
      final crossing = _street(
        'x',
        line: const [LatLng(41.699, 44.805), LatLng(41.701, 44.805)],
      );
      final crossingAgain = _street(
        'x2',
        name: 'name x',
        line: const [LatLng(41.699, 44.806), LatLng(41.701, 44.806)],
      );
      final touching = _street(
        't',
        line: const [LatLng(41.700, 44.808), LatLng(41.702, 44.808)],
      );
      final parallel = _street(
        'p',
        line: const [LatLng(41.701, 44.800), LatLng(41.701, 44.810)],
      );
      expect(
        crossingCount(main, [
          main,
          crossing,
          crossingAgain,
          touching,
          parallel,
        ]),
        2,
      );
      // The main road has no vertex where the side street ends on it.
      expect(crossingCount(touching, [main]), 1);
    });

    test('the direction from the centre, none near it', () {
      const centre = LatLng(41.7, 44.8);
      expect(
        directionFromCentre(
          _street('n', line: const [LatLng(41.75, 44.8), LatLng(41.751, 44.8)]),
          centre,
        ),
        CompassPoint.n,
      );
      expect(directionFromCentre(_street('c'), centre), isNull);
    });
  });

  group('resume', () {
    List<LessonStep> plan(int seed) => planLesson(
      kind: LessonKind.lesson,
      streets: streets,
      unitStreets: unit,
      random: Random(seed),
    );

    LessonRun pastCards(int seed) {
      var run = LessonRun(LessonKind.lesson, plan(seed));
      while (run.step is CardStep) {
        run = run.next();
      }
      return run;
    }

    LessonRun answer(LessonRun run, Tier tier) => switch (run.step) {
      PinStep() => run.answerPin(
        (tier: tier, xp: tier == Tier.miss ? 0 : 90),
        40,
        _at,
      ),
      NameStep() => run.answerName(right: tier != Tier.miss, at: _at),
      TripStep() => run.answerTrip((tier: tier, xp: 0), _at),
      CardStep() => run,
    };

    String ids(List<LessonStep> steps) =>
        steps.map((s) => '${s.runtimeType}:${s.street.id}').join(' ');

    test('the same seed plans the same steps', () {
      expect(ids(plan(7)), ids(plan(7)));
    });

    test(
      'restore replays answers mid-test, through the fixes and finished',
      () {
        var run = pastCards(1);
        for (final tier in [
          Tier.great,
          Tier.miss,
          Tier.great,
          Tier.close,
          Tier.great,
          Tier.great,
        ]) {
          run = answer(run, tier).next();
        }
        expect(run.startsFixes, isTrue);
        final fixed = answer(run, Tier.great);
        var done = fixed.next();
        done = answer(done, Tier.great).next();
        expect(done.finished, isTrue);
        for (final at in [pastCards(1), run, fixed, done]) {
          final back = LessonRun.restore(at.kind, plan(1), at.saved, at.index)!;
          expect(back.index, at.index);
          expect(ids(back.steps), ids(at.steps));
          expect(back.xp, at.xp);
          expect(back.mistakes, hasLength(at.mistakes.length));
          expect(back.answered, at.answered);
          expect(back.finished, at.finished);
        }
      },
    );

    test('resumeAt skips a reveal that was showing', () {
      final fresh = pastCards(2);
      final answered = answer(fresh, Tier.great);
      expect(answered.resumeAt().index, answered.index + 1);
      expect(fresh.resumeAt().index, fresh.index);
    });

    test('a plan that no longer fits restores to null', () {
      final run = answer(pastCards(3), Tier.great);
      final a = run.saved.single;
      final moved = [
        (
          step: a.step,
          streetId: 'other',
          tier: a.tier,
          xp: a.xp,
          distanceM: a.distanceM,
          at: a.at,
        ),
      ];
      expect(LessonRun.restore(run.kind, plan(3), moved, run.index), isNull);
      final onCard = [
        (
          step: 0,
          streetId: a.streetId,
          tier: a.tier,
          xp: a.xp,
          distanceM: a.distanceM,
          at: a.at,
        ),
      ];
      expect(LessonRun.restore(run.kind, plan(3), onCard, run.index), isNull);
    });
  });
}
