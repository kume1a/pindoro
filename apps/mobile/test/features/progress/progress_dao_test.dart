import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/app/router.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';

void main() {
  late AppDatabase db;
  late ProgressDao progress;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    progress = ProgressDao(db);
  });
  tearDown(() => db.close());

  const vake = DistrictsArea({'osm:r1'});

  Street part(String id) => Street(
    id: id,
    nameKa: 'name $id',
    nameEn: null,
    roadClass: 'residential',
    difficulty: Difficulty.expert,
    lengthM: 500,
    midpoint: const LatLng(41.7, 44.75),
    bbox: const Bbox(41.7, 44.75, 41.7, 44.75),
    geometry: const [
      [LatLng(41.7, 44.75)],
    ],
  );

  Future<String> round(
    List<String> streets, {
    String cityId = 'tbilisi',
    String? retryOf,
    bool pitStop = false,
  }) => progress.startRound(
    cityId: cityId,
    area: vake,
    difficulty: Difficulty.expert,
    packVersion: 'v1',
    streetIds: streets,
    retryOf: retryOf,
    pitStop: pitStop,
  );

  Future<Answer> answer(
    String roundId,
    String streetId,
    Tier tier, {
    double distanceM = 10,
  }) => progress.recordAnswer(
    roundId: roundId,
    streetId: streetId,
    pin: const LatLng(41.7, 44.75),
    distanceM: distanceM,
    tier: tier,
    xp: 100,
    packVersion: 'v1',
  );

  test('play began with the first round', () async {
    expect(await progress.firstPlayedAt(), isNull);
    await round(['a']);
    final first = await progress.firstPlayedAt();
    await round(['b']);
    expect(first, isNotNull);
    expect(await progress.firstPlayedAt(), first);
  });

  test(
    "welcome until a round or a course; What's new before the first course",
    () async {
      expect(await startLocation(db), Routes.welcome);
      final id = await round(['a']);
      expect(
        await startLocation(db),
        Routes.home,
        reason: 'Home offers to continue the saved first round',
      );
      await progress.finishRound(id);
      expect(await startLocation(db), Routes.whatsNew);
      expect(await progress.hasCourse(), isFalse);
      await progress.saveCourseStart('tbilisi', 'osm:r1');
      expect(await progress.hasCourse(), isTrue);
      expect(await startLocation(db), Routes.path);
    },
  );

  test('a new player who picked a district opens on the Path', () async {
    await progress.saveCourseStart('tbilisi', 'osm:r1');
    expect(await startLocation(db), Routes.path);
  });

  test('a finished round keeps its first finish time', () async {
    final id = await round(['a']);
    await progress.finishRound(id);
    final first = (await progress.roundProgress(id)).round.finishedAt;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await progress.finishRound(id);
    expect((await progress.roundProgress(id)).round.finishedAt, first);
  });

  test('startRound stores the planned streets, area and retry link', () async {
    final first = await round(['b', 'a', 'c']);
    final planned = await progress.roundProgress(first);
    expect(planned.planned, ['b', 'a', 'c']);
    expect(planned.answers, isEmpty);
    expect(parseArea(planned.round.areaJson), vake);
    expect(planned.round.retryOf, isNull);
    final retry = await round(['a'], retryOf: first);
    expect((await progress.roundProgress(retry)).round.retryOf, first);
  });

  test('recordAnswer logs the pin, tier and xp', () async {
    final id = await round(['a']);
    final logged = await answer(id, 'a', Tier.great);
    expect((logged.pinLat, logged.pinLon), (41.7, 44.75));
    expect(logged.tier, Tier.great);
    expect(await progress.totalXp(), 100);
    expect(await progress.hasAnswered(), isTrue);
  });

  group('saved round', () {
    final now = DateTime.now();

    test('only the most recent unfinished round is resumable', () async {
      final older = await round(['a']);
      final newer = await round(['b']);
      expect((await progress.resumableRound(now))?.id, newer);
      await progress.finishRound(newer);
      expect(
        await progress.resumableRound(now),
        isNull,
        reason: 'the older unfinished round ($older) was abandoned',
      );
    });

    test('expires 7 days after its last activity', () async {
      final id = await round(['a', 'b']);
      final day = now.add(const Duration(days: 6, hours: 23));
      expect((await progress.resumableRound(day))?.id, id);
      expect(
        await progress.resumableRound(now.add(const Duration(days: 8))),
        isNull,
      );
    });

    test('is only offered for the current city and area', () async {
      final settings = SettingsDao(db);
      await settings.chooseArea(vake, cityId: 'tbilisi');
      final id = await round(['a']);
      Future<Round?> saved() async {
        final s = await settings.read();
        return progress.savedRound(now, cityId: s.lastCity, area: s.area);
      }

      expect((await saved())?.id, id);
      await settings.chooseArea(const DistrictsArea({'osm:r2'}));
      expect(await saved(), isNull);

      // A Pit stop round's area is wherever its streets were.
      final pitStop = await round(['b'], pitStop: true);
      expect((await saved())?.id, pitStop);
    });
  });

  test('answers come back in the order they were given', () async {
    final id = await round(['a', 'b']);
    await answer(id, 'b', Tier.close);
    await answer(id, 'a', Tier.great);
    expect((await progress.answersForRound(id)).map((a) => a.streetId), [
      'b',
      'a',
    ]);
  });

  test('bestTierByPart keeps the best tier per part, per city', () async {
    final id = await round(['a', 'b']);
    await answer(id, 'a', Tier.great);
    await answer(id, 'b', Tier.close);
    await answer(id, 'a', Tier.miss);
    final elsewhere = await round(['c'], cityId: 'batumi');
    await answer(elsewhere, 'c', Tier.perfect);
    expect(await progress.bestTierByPart('tbilisi'), {
      'a': Tier.great,
      'b': Tier.close,
    });
    expect(
      await progress.bestTierByPart(
        'tbilisi',
        before: DateTime.now().subtract(const Duration(days: 1)),
      ),
      isEmpty,
    );
  });

  test('askedInLastRounds returns the streets of the latest rounds', () async {
    await round(['a']);
    await round(['b']);
    await round(['x'], cityId: 'batumi');
    await round(['c', 'd']);
    expect(await progress.askedInLastRounds('tbilisi', count: 2), {
      'b',
      'c',
      'd',
    });
  });

  test('retryIds are the Close and Miss streets in round order', () async {
    final id = await round(['a', 'b', 'c', 'd']);
    await answer(id, 'd', Tier.miss);
    await answer(id, 'a', Tier.close);
    await answer(id, 'b', Tier.perfect);
    await answer(id, 'c', Tier.great);
    expect((await progress.roundProgress(id)).retryIds, ['a', 'd']);
  });

  test('recent cities and districts list the latest first', () async {
    await progress.startRound(
      cityId: 'tbilisi',
      area: const DistrictsArea({'osm:r1', 'osm:r2'}),
      difficulty: Difficulty.easy,
      packVersion: 'v1',
      streetIds: const ['a'],
    );
    await round(['b'], cityId: 'batumi');
    await round(['c']);
    expect(await progress.recentCityIds(), ['tbilisi', 'batumi']);
    expect(await progress.recentDistrictIds('tbilisi'), ['osm:r1', 'osm:r2']);
  });

  group('daily goal', () {
    final today = calendarDay(DateTime.now());

    /// [count] answers of 100 XP each.
    Future<void> earn(String roundId, int count) async {
      for (var i = 0; i < count; i++) {
        await answer(roundId, 's$i', Tier.perfect);
      }
    }

    test('marks today once, by the round that reached the goal', () async {
      final first = await round(['a']);
      await earn(first, 4);
      expect(await progress.goalDayRounds(), isEmpty);
      await earn(first, 1);
      final second = await round(['b']);
      await earn(second, 5);
      expect(await progress.goalDayRounds(), {today: first});
      expect(await progress.xpOn(today), 1000);
    });

    test('lowering the goal below today\'s XP marks today, no round', () async {
      await earn(await round(['a']), 3);
      await SettingsDao(db).setDailyGoal(250);
      await progress.markGoalIfMet(DateTime.now());
      expect(await progress.goalDayRounds(), {today: null});
    });

    test('xpOn counts only that local day', () async {
      final id = await round(['a']);
      await earn(id, 1);
      await db
          .into(db.answers)
          .insert(
            AnswersCompanion.insert(
              roundId: id,
              streetId: 'b',
              pinLat: 0,
              pinLon: 0,
              distanceM: 0,
              tier: Tier.great,
              xp: 70,
              packVersion: 'v1',
              createdAt: Value(
                DateTime.now().subtract(const Duration(days: 1)),
              ),
            ),
          );
      expect(await progress.xpOn(today), 100);
      expect(await progress.xpOn(today.subtract(const Duration(days: 1))), 70);
    });
  });

  group('Pit stop', () {
    final today = calendarDay(DateTime.now());
    final tomorrow = today.add(const Duration(days: 1));

    test('Close and Miss enter at step 1, due tomorrow', () async {
      final id = await round(['a', 'b', 'c']);
      await answer(id, 'a', Tier.close);
      await answer(id, 'b', Tier.miss);
      await answer(id, 'c', Tier.great);
      final pit = await progress.pitStop('tbilisi');
      expect(
        [for (final i in pit) (i.streetId, i.step, i.lastTier)],
        [('a', 1, Tier.close), ('b', 1, Tier.miss)],
      );
      expect(pit.first.dueBy(today), isFalse);
      expect(pit.first.dueBy(tomorrow), isTrue);
    });

    test('two Greats in a row graduate; a Miss resets', () async {
      final id = await round(['a']);
      await answer(id, 'a', Tier.miss);
      await answer(id, 'a', Tier.great);
      expect((await progress.pitStop('tbilisi')).single.step, 2);
      await answer(id, 'a', Tier.miss);
      expect((await progress.pitStop('tbilisi')).single.step, 1);
      await answer(id, 'a', Tier.great);
      await answer(id, 'a', Tier.perfect);
      expect(await progress.pitStop('tbilisi'), isEmpty);
    });

    test(
      'lists a street once, whichever of its parts it was filed under',
      () async {
        final id = await round(['a', 'a2']);
        await answer(id, 'a', Tier.miss);
        await answer(id, 'a2', Tier.close);
        final street = NamedStreet([part('a'), part('a2')]);
        final due = (await progress.pitStop(
          'tbilisi',
        )).dueIn({'a': street, 'a2': street}, tomorrow);
        expect(due, hasLength(1));
      },
    );

    test('each city keeps its own Pit stop', () async {
      await answer(await round(['a'], cityId: 'batumi'), 'a', Tier.miss);
      expect(await progress.pitStop('tbilisi'), isEmpty);
      expect((await progress.pitStop('batumi')).single.streetId, 'a');
    });

    test('the last Pit stop is the latest finished Pit stop round', () async {
      final done = await round(['a', 'b'], pitStop: true);
      await answer(done, 'a', Tier.great);
      await answer(done, 'b', Tier.close);
      await progress.finishRound(done);
      await answer(await round(['c'], pitStop: true), 'c', Tier.miss);
      final normal = await round(['d']);
      await answer(normal, 'd', Tier.miss);
      await progress.finishRound(normal);
      final last = await progress.lastPitStopAnswers('tbilisi');
      expect([for (final a in last) a.streetId], ['a', 'b']);
      expect(await progress.lastPitStopAnswers('batumi'), isEmpty);
    });

    test('previous distances come from the latest other answer', () async {
      final first = await round(['a', 'b']);
      await answer(first, 'a', Tier.miss, distanceM: 900);
      await answer(first, 'b', Tier.close, distanceM: 300);
      final second = await round(['a']);
      await answer(second, 'a', Tier.close, distanceM: 250);
      final pit = await round(['a', 'b'], pitStop: true);
      await answer(pit, 'a', Tier.great, distanceM: 40);
      expect(await progress.previousDistances(pit), {'a': 250, 'b': 300});
    });
  });

  group('lessons', () {
    NamedStreet street(String id) => NamedStreet([part(id)]);
    final a = street('a'), b = street('b'), c = street('c');
    final at = DateTime.now();

    /// Pin a (as [pinA]), name b ([nameB]), then their fixes when wrong.
    LessonRun played({
      LessonKind kind = LessonKind.lesson,
      Tier pinA = Tier.perfect,
      bool nameB = true,
      Tier fixA = Tier.perfect,
      bool fixB = true,
    }) {
      var run = LessonRun(kind, [
        PinStep(a),
        NameStep(b, [b, a, c]),
      ]);
      run = run
          .answerPin((tier: pinA, xp: pinA == Tier.perfect ? 100 : 0), 900, at)
          .next()
          .answerName(right: nameB, at: at)
          .next();
      while (!run.finished) {
        run = switch (run.step) {
          PinStep() => run.answerPin(
            (tier: fixA, xp: fixA == Tier.perfect ? 100 : 0),
            300,
            at,
          ),
          _ => run.answerName(right: fixB, at: at),
        };
        run = run.next();
      }
      return run;
    }

    Future<String> finish(
      LessonRun run, {
      int? lesson = 1,
      String unitId = 'osm:r1',
      String cityId = 'tbilisi',
      List<({String streetId, Tier tier})> reviews = const [],
    }) => progress.finishLesson(
      cityId: cityId,
      unitId: unitId,
      kind: run.kind,
      lesson: lesson,
      difficulty: Difficulty.medium,
      run: run,
      startedAt: at.subtract(const Duration(minutes: 3)),
      reviews: reviews,
    );

    Future<void> save({
      LessonKind kind = LessonKind.lesson,
      int? lesson = 2,
      required DateTime savedAt,
    }) => progress.saveLesson(
      cityId: 'tbilisi',
      unitId: 'osm:r1',
      kind: kind,
      lesson: lesson,
      difficulty: Difficulty.medium,
      packVersion: 'v1',
      seed: 7,
      startedAt: savedAt.subtract(const Duration(minutes: 2)),
      savedAt: savedAt,
      progress: '{"index":5,"answers":[]}',
    );

    test('a saved lesson keeps for 24 h after its last save', () async {
      final now = DateTime.now();
      await save(savedAt: now);
      expect((await progress.savedLesson(now))?.seed, 7);
      await save(lesson: 3, savedAt: now);
      expect((await progress.savedLesson(now))?.lesson, 3, reason: 'one row');
      expect(
        await progress.savedLesson(now.add(const Duration(hours: 25))),
        isNull,
      );
      expect(await progress.savedLesson(now), isNull, reason: 'dropped');
    });

    test('finishing a lesson drops its save', () async {
      await save(savedAt: DateTime.now());
      await finish(played());
      expect(await progress.savedLesson(DateTime.now()), isNull);
    });

    test('a course with a saved lesson starts in it', () async {
      await progress.saveCourseStart('tbilisi', 'osm:r1');
      final now = DateTime.now();
      await save(savedAt: now);
      expect(await startLocation(db), Routes.lessonOf('osm:r1', 2));
      await save(kind: LessonKind.practice, savedAt: now);
      expect(
        await startLocation(db),
        Routes.lessonOf('osm:r1', 2, practice: true),
      );
      await save(kind: LessonKind.pitStop, lesson: null, savedAt: now);
      expect(await startLocation(db), Routes.unitPitStop('osm:r1'));
      await progress.dropSavedLesson();
      expect(await startLocation(db), Routes.path);
    });

    test(
      'a finished lesson writes its result and answers, and counts',
      () async {
        expect(await progress.hasPlayed(), isFalse);
        expect(await startLocation(db), Routes.welcome);
        final id = await finish(played());
        final result = await progress.lessonResult(id);
        expect(result.xp, 100 + 50 + 20 + 50);
        expect(result.perfect, isTrue);
        expect((result.rightFirst, result.tests), (2, 2));
        expect(result.durationMs, greaterThanOrEqualTo(180000));
        expect(await progress.totalXp(), 220);
        expect(await progress.xpOn(calendarDay(DateTime.now())), 220);
        expect(await progress.hasPlayed(), isTrue);
        final since = await progress.firstPlayedAt();
        expect(since!.difference(result.finishedAt).inSeconds, 0);
        expect(await progress.recentCityIds(), ['tbilisi']);
        expect(await progress.lessonResultsIn('tbilisi'), [result]);
        await progress.saveCourseStart('tbilisi', 'osm:r1');
        expect(await startLocation(db), Routes.path);
      },
    );

    test('placed lessons earn nothing and count as no lesson', () async {
      await progress.place('tbilisi', [('osm:r1', 1), ('osm:r1', 2)]);
      final rows = await progress.lessonResultsIn('tbilisi');
      expect(
        [for (final r in rows) (r.kind, r.lesson, r.xp)],
        [(LessonKind.placed, 1, 0), (LessonKind.placed, 2, 0)],
      );
      expect(await progress.totalXp(), 0);
      expect(await progress.lessonsDone(), 0);
      expect(await progress.bestTierByPart('tbilisi'), isEmpty);
    });

    test('lessons done counts each lesson once, not practice', () async {
      await finish(played());
      await finish(played());
      await finish(played(), lesson: 2);
      await finish(played(kind: LessonKind.practice));
      await finish(played(), cityId: 'batumi');
      expect(await progress.lessonsDone(), 3);
    });

    test(
      'known: a Great pin and a right name first time, not a name fix',
      () async {
        await finish(played(pinA: Tier.miss, nameB: false));
        final best = await progress.bestTierByPart('tbilisi');
        expect(best, {'a': Tier.perfect, 'b': Tier.miss});
        await finish(played());
        expect(await progress.bestTierByPart('tbilisi'), {
          'a': Tier.perfect,
          'b': Tier.great,
        });
        expect(
          await progress.bestTierByPart(
            'tbilisi',
            before: DateTime.now().subtract(const Duration(days: 1)),
          ),
          isEmpty,
        );
      },
    );

    test('only the given reviews reach the Pit stop', () async {
      await finish(
        played(pinA: Tier.miss, fixA: Tier.close),
        reviews: const [(streetId: 'a', tier: Tier.close)],
      );
      final items = await progress.pitStop('tbilisi');
      expect([for (final i in items) (i.streetId, i.step)], [('a', 1)]);
    });

    test('a lesson that reaches the daily goal marks today', () async {
      final run = LessonRun(LessonKind.lesson, [
        for (final s in [a, b, c, street('d'), street('e')]) PinStep(s),
      ]);
      var done = run;
      while (!done.finished) {
        done = done.answerPin((tier: Tier.perfect, xp: 100), 0, at).next();
      }
      await finish(done);
      expect((await progress.goalDayRounds()).keys, [calendarDay(at)]);
    });

    test(
      'unit mistakes: first tries through lesson 3, in order, once',
      () async {
        await finish(played(pinA: Tier.close, fixA: Tier.close), lesson: 1);
        await finish(played(nameB: false), lesson: 2);
        await finish(played(pinA: Tier.miss), lesson: 4);
        await finish(
          played(kind: LessonKind.practice, nameB: false),
          lesson: 1,
        );
        await finish(played(pinA: Tier.miss), lesson: 3, unitId: 'osm:r2');
        expect(
          await progress.unitMistakes('tbilisi', 'osm:r1', throughLesson: 3),
          ['a', 'b'],
        );
      },
    );

    test('last distances: the latest pin of Free play or a lesson', () async {
      final r = await round(['a', 'b']);
      await answer(r, 'a', Tier.miss, distanceM: 900);
      await answer(r, 'b', Tier.close, distanceM: 200);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await finish(played(pinA: Tier.close));
      expect(await progress.lastDistances('tbilisi', ['a', 'b', 'c']), {
        'a': 300,
        'b': 200,
      });
    });

    group('road trips', () {
      final trip = (
        from: 0,
        to: 1,
        destination: c,
        best: const Route([0, 1], [], 800),
      );

      /// A lesson whose road trip to c scored [tier] (a Miss comes back).
      LessonRun withTrip(Tier tier) {
        var run = LessonRun(LessonKind.lesson, [PinStep(a), TripStep(trip)]);
        run = run
            .answerPin((tier: Tier.perfect, xp: 100), 0, at)
            .next()
            .answerTrip((tier: tier, xp: tier == Tier.miss ? 0 : 100), at)
            .next();
        while (!run.finished) {
          run = run.answerTrip((tier: Tier.miss, xp: 0), at).next();
        }
        return run;
      }

      test('a lesson saves its trip without a distance', () async {
        final id = await finish(withTrip(Tier.great));
        final answers = await progress.lessonAnswersOf(id);
        expect(answers.last.kind, LessonAnswerKind.trip);
        expect(answers.last.streetId, 'c');
        expect(answers.last.distanceM, isNull);
        expect(await progress.roadTrips(), 1);
      });

      test(
        'a trip is no unit mistake, knows no street, keeps last distances',
        () async {
          await finish(withTrip(Tier.miss));
          expect(
            await progress.unitMistakes('tbilisi', 'osm:r1', throughLesson: 3),
            isEmpty,
          );
          await finish(withTrip(Tier.perfect));
          expect(await progress.bestTierByPart('tbilisi'), {'a': Tier.perfect});
          expect(await progress.lastDistances('tbilisi', ['a', 'c']), {'a': 0});
        },
      );

      test('a Final drive trip saves its own result and the bonus', () async {
        Future<String> drive(Tier tier, {bool completes = false}) =>
            progress.finishTrip(
              cityId: 'tbilisi',
              unitId: 'osm:r1',
              difficulty: Difficulty.medium,
              trip: trip,
              score: (tier: tier, xp: tier == Tier.miss ? 0 : 64),
              completesUnit: completes,
              startedAt: at,
            );
        final missed = await progress.lessonResult(await drive(Tier.miss));
        expect(missed.kind, LessonKind.finalDrive);
        expect((missed.rightFirst, missed.tests, missed.xp), (0, 1, 0));
        final last = await progress.lessonResult(
          await drive(Tier.great, completes: true),
        );
        expect((last.rightFirst, last.xp), (1, 64 + CourseRules.unitBonusXp));
        expect(await progress.totalXp(), 164);
        expect(await progress.roadTrips(), 2);
        await finish(withTrip(Tier.great));
        expect(await progress.unitSummary('tbilisi', 'osm:r1'), (
          xp: 164 + 100 + 100 + 20 + 50,
          trips: 3,
        ));
        expect(await progress.unitSummary('tbilisi', 'osm:r2'), (
          xp: 0,
          trips: 0,
        ));
        expect(await progress.lessonsDone(), 1);
      });
    });

    test('the course start and the last round area', () async {
      expect(await progress.courseStart('tbilisi'), isNull);
      await progress.saveCourseStart('tbilisi', 'osm:r2');
      await progress.saveCourseStart('tbilisi', 'osm:r1');
      expect(await progress.courseStart('tbilisi'), 'osm:r1');
      expect(await progress.lastRoundArea('tbilisi'), isNull);
      await round(['a']);
      expect(await progress.lastRoundArea('tbilisi'), vake);
    });
  });

  group('badges', () {
    test(
      'a street cleared from the Pit stop is counted, a new Great is not',
      () async {
        final id = await round(['a', 'b']);
        await answer(id, 'b', Tier.great);
        await answer(id, 'a', Tier.miss);
        await answer(id, 'a', Tier.great);
        expect((await progress.badgeCounts()).pitStopCleared, 0);
        await answer(id, 'a', Tier.perfect);
        expect((await progress.badgeCounts()).pitStopCleared, 1);
        expect(await db.select(db.reviewClearings).get(), [
          isA<ReviewClearing>()
              .having((c) => c.cityId, 'city', 'tbilisi')
              .having((c) => c.streetId, 'street', 'a'),
        ]);
      },
    );

    test('pins and Perfects count rounds and lesson pins, not names', () async {
      final id = await round(['a', 'b']);
      await answer(id, 'a', Tier.perfect);
      await answer(id, 'b', Tier.close);
      final result = await db
          .into(db.lessonResults)
          .insertReturning(
            LessonResultsCompanion.insert(
              cityId: 'tbilisi',
              unitId: 'osm:r1',
              kind: LessonKind.lesson,
              difficulty: Difficulty.medium,
              xp: 0,
              perfect: false,
              rightFirst: 0,
              tests: 2,
              durationMs: 1000,
              finishedAt: Value(DateTime(2026, 11, 11, 12)),
            ),
          );
      for (final (i, kind) in [
        LessonAnswerKind.pin,
        LessonAnswerKind.name,
      ].indexed) {
        await db
            .into(db.lessonAnswers)
            .insert(
              LessonAnswersCompanion.insert(
                resultId: result.id,
                position: i,
                streetId: 'c',
                kind: kind,
                tier: Tier.perfect,
                xp: 0,
                fix: false,
              ),
            );
      }
      final counts = await progress.badgeCounts();
      expect((counts.pins, counts.perfects), (3, 2));
    });

    test('a late answer is one before 04:00 local time', () async {
      final id = await round(['a']);
      Future<void> answerAt(DateTime at) => db
          .into(db.answers)
          .insert(
            AnswersCompanion.insert(
              roundId: id,
              streetId: 'a',
              pinLat: 41.7,
              pinLon: 44.75,
              distanceM: 10,
              tier: Tier.great,
              xp: 60,
              packVersion: 'v1',
              createdAt: Value(at),
            ),
          );
      await answerAt(DateTime(2026, 11, 11, 4));
      await answerAt(DateTime(2026, 11, 11, 23, 59));
      expect((await progress.badgeCounts()).lateAnswer, isFalse);
      await answerAt(DateTime(2026, 11, 12, 1, 30));
      expect((await progress.badgeCounts()).lateAnswer, isTrue);
    });

    test('earn saves each badge once and returns only the new ones', () async {
      final now = DateTime(2026, 11, 11);
      expect(await progress.hasBadges(), isFalse);
      expect(await progress.earn([BadgeId.firstPin, BadgeId.bullseye], now), [
        BadgeId.firstPin,
        BadgeId.bullseye,
      ]);
      expect(await progress.earn([BadgeId.firstPin, BadgeId.onFire], now), [
        BadgeId.onFire,
      ]);
      expect(await progress.hasBadges(), isTrue);
      expect((await progress.earnedBadges()).keys, {
        BadgeId.firstPin,
        BadgeId.bullseye,
        BadgeId.onFire,
      });
    });

    test('unseen badges are taken once; a seen one never is', () async {
      final now = DateTime(2026, 11, 11);
      await progress.earn([BadgeId.firstPin, BadgeId.bullseye], now);
      await progress.seeBadges([BadgeId.bullseye], now);
      expect(await progress.takeUnseenBadges(now), {BadgeId.firstPin});
      expect(await progress.takeUnseenBadges(now), isEmpty);
    });
  });
}
