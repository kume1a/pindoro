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
    expect(await progress.firstRoundAt(), isNull);
    await round(['a']);
    final first = await progress.firstRoundAt();
    await round(['b']);
    expect(first, isNotNull);
    expect(await progress.firstRoundAt(), first);
  });

  test('welcome shows until a first round is finished or saved', () async {
    expect(await startLocation(db), Routes.welcome);
    final id = await round(['a']);
    expect(
      await startLocation(db),
      Routes.home,
      reason: 'Home offers to continue the saved first round',
    );
    await progress.finishRound(id);
    expect(await startLocation(db), Routes.home);
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
}
