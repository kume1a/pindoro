import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/app/router.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

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

  test('welcome until a round is saved or finished or a city placed, then '
      'the Drive tab', () async {
    expect(await startLocation(db), Routes.welcome);
    final id = await round(['a']);
    expect(
      await startLocation(db),
      Routes.driveTab,
      reason: 'Explore offers to continue the saved round once opened',
    );
    await progress.finishRound(id);
    expect(await startLocation(db), Routes.driveTab);
  });

  test('a new player who placed a city opens on the Drive tab', () async {
    await LearningDao(db).markPlaced('tbilisi', DateTime(2026));
    expect(await progress.hasPlayed(), isTrue);
    expect(await startLocation(db), Routes.driveTab);
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

  test('recordAnswer logs the pin and tier', () async {
    final id = await round(['a']);
    final logged = await answer(id, 'a', Tier.great);
    expect((logged.pinLat, logged.pinLon), (41.7, 44.75));
    expect(logged.tier, Tier.great);
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
    await db
        .into(db.legacyKnown)
        .insert(LegacyKnownCompanion.insert(cityId: 'tbilisi', streetId: 'b'));
    expect(
      (await progress.bestTierByPart('tbilisi'))['b'],
      Tier.great,
      reason: "the old game's lesson knowledge counts as Great",
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
    await LearningDao(db).markPlaced('kutaisi', DateTime(2026));
    expect(await progress.recentCityIds(), ['tbilisi', 'batumi', 'kutaisi']);
    expect(await progress.recentDistrictIds('tbilisi'), ['osm:r1', 'osm:r2']);
  });

  test(
    'a counted day is marked once, by the first answer to get there',
    () async {
      final today = calendarDay(DateTime.now());
      final id = await round(['a']);
      await progress.markDay(DateTime.now(), roundId: id);
      await progress.markDay(DateTime.now());
      expect(await progress.goalDayRounds(), {today: id});
    },
  );

  test('previous distances come from the latest other answer', () async {
    final first = await round(['a', 'b']);
    await answer(first, 'a', Tier.miss, distanceM: 900);
    await answer(first, 'b', Tier.close, distanceM: 300);
    final second = await round(['a']);
    await answer(second, 'a', Tier.close, distanceM: 250);
    final retry = await round(['a', 'b'], retryOf: second);
    await answer(retry, 'a', Tier.great, distanceM: 40);
    expect(await progress.previousDistances(retry), {'a': 250, 'b': 300});
  });

  group('badges', () {
    test('pins count Explore answers and session and placement pins, '
        'Perfects the Explore ones; counted days too', () async {
      final id = await round(['a', 'b']);
      await answer(id, 'a', Tier.perfect);
      await answer(id, 'b', Tier.close);
      final learning = LearningDao(db);
      LogEntry pin(ReviewSource source, {double? distanceM = 30}) => LogEntry(
        ts: DateTime(2026, 11, 11, 12),
        itemId: 'P:c',
        format: ReviewFormat.review,
        rating: Rating.good,
        source: source,
        distanceM: distanceM,
      );
      await learning.saveAnswer(log: pin(ReviewSource.session));
      await learning.saveAnswer(log: pin(ReviewSource.placement));
      await learning.saveAnswer(log: pin(ReviewSource.explore));
      await learning.saveAnswer(
        log: pin(ReviewSource.session, distanceM: null),
      );
      await progress.markDay(DateTime(2026, 11, 11));
      final counts = await progress.badgeCounts();
      expect((counts.pins, counts.perfects, counts.goalDays), (4, 1, 1));
    });

    test('a late answer is one before 04:00 local time', () async {
      final id = await round(['a']);
      Future<void> answerAt(DateTime at) => db
          .into(db.answers)
          .insert(
            AnswersCompanion.insert(
              roundId: id,
              streetId: 'a',
              pinLat: Value(41.7),
              pinLon: Value(44.75),
              distanceM: Value(10),
              tier: Tier.great,
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
      expect(await progress.earn(['firstPin', 'cityMemory500'], now), [
        'firstPin',
        'cityMemory500',
      ]);
      expect(await progress.earn(['firstPin', 'onFire'], now), ['onFire']);
      expect(await progress.hasBadges(), isTrue);
      expect((await progress.earnedBadges()).keys, {
        'firstPin',
        'cityMemory500',
        'onFire',
      });
    });

    test('unseen badges are taken once; a seen one never is', () async {
      final now = DateTime(2026, 11, 11);
      await progress.earn(['firstPin', 'bullseye'], now);
      await progress.seeBadges(['bullseye'], now);
      expect(await progress.takeUnseenBadges(now), {'firstPin'});
      expect(await progress.takeUnseenBadges(now), isEmpty);
    });
  });
}
