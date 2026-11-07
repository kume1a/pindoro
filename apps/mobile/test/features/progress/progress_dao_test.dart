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
  }) => progress.startRound(
    cityId: cityId,
    area: vake,
    difficulty: Difficulty.expert,
    packVersion: 'v1',
    streetIds: streets,
    retryOf: retryOf,
  );

  Future<Answer> answer(String roundId, String streetId, Tier tier) =>
      progress.recordAnswer(
        roundId: roundId,
        streetId: streetId,
        pin: const LatLng(41.7, 44.75),
        distanceM: 10,
        tier: tier,
        xp: 100,
        packVersion: 'v1',
      );

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
}
