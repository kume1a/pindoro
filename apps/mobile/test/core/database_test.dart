import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/app/router.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro_core/pindoro_core.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('welcome shows until the first round is finished', () async {
    expect(await initialLocation(db), Routes.welcome);
    final id = await db.startRound(
      cityId: 'tbilisi',
      area: const DistrictsArea({'osm:r1'}),
      difficulty: Difficulty.expert,
      packVersion: 'v1',
      streetIds: const ['a'],
    );
    expect(await initialLocation(db), Routes.welcome);
    await db.finishRound(id);
    expect(await initialLocation(db), Routes.home);
  });

  test('answers get UUIDv7 ids and cannot be updated', () async {
    final round = await db
        .into(db.rounds)
        .insertReturning(
          RoundsCompanion.insert(
            cityId: 'tbilisi',
            areaJson: '{}',
            difficulty: Difficulty.expert,
            packVersion: 'v1',
          ),
        );
    final answer = await db
        .into(db.answers)
        .insertReturning(
          AnswersCompanion.insert(
            roundId: round.id,
            streetId: 'street',
            pinLat: 41.7,
            pinLon: 44.75,
            distanceM: 42,
            tier: Tier.great,
            xp: 117,
            packVersion: 'v1',
          ),
        );
    expect(answer.id[14], '7', reason: 'UUID version nibble');
    expect(await db.totalXp(), 117);
    await expectLater(
      db.update(db.answers).write(const AnswersCompanion(xp: Value(1))),
      throwsA(isA<SqliteException>()),
    );
  });

  const vake = DistrictsArea({'osm:r1'});

  Future<String> round(
    List<String> streets, {
    String cityId = 'tbilisi',
    String? retryOf,
  }) => db.startRound(
    cityId: cityId,
    area: vake,
    difficulty: Difficulty.expert,
    packVersion: 'v1',
    streetIds: streets,
    retryOf: retryOf,
  );

  Future<void> answer(String roundId, String streetId, Tier tier) => db
      .into(db.answers)
      .insert(
        AnswersCompanion.insert(
          roundId: roundId,
          streetId: streetId,
          pinLat: 41.7,
          pinLon: 44.75,
          distanceM: 10,
          tier: tier,
          xp: 100,
          packVersion: 'v1',
        ),
      );

  test('startRound stores the planned streets, area and retry link', () async {
    final first = await round(['b', 'a', 'c']);
    final progress = await db.roundProgress(first);
    expect(progress.planned, ['b', 'a', 'c']);
    expect(progress.answers, isEmpty);
    expect(parseArea(progress.round.areaJson), vake);
    expect(progress.round.retryOf, isNull);
    final retry = await round(['a'], retryOf: first);
    expect((await db.roundProgress(retry)).round.retryOf, first);
  });

  group('saved round', () {
    final now = DateTime.now();

    test('only the most recent unfinished round is resumable', () async {
      final older = await round(['a']);
      final newer = await round(['b']);
      expect((await db.resumableRound(now))?.id, newer);
      await db.finishRound(newer);
      expect(
        await db.resumableRound(now),
        isNull,
        reason: 'the older unfinished round ($older) was abandoned',
      );
    });

    test('expires 7 days after its last activity', () async {
      final id = await round(['a', 'b']);
      final day = now.add(const Duration(days: 6, hours: 23));
      expect((await db.resumableRound(day))?.id, id);
      expect(await db.resumableRound(now.add(const Duration(days: 8))), isNull);
    });

    test('is only offered for the current city and area', () async {
      await db.updateSettings(
        UserSettingsCompanion(
          lastCity: const Value('tbilisi'),
          lastAreaJson: Value(jsonEncode(vake.toJson())),
        ),
      );
      final id = await round(['a']);
      expect((await db.savedRound(now))?.id, id);
      await db.updateSettings(
        UserSettingsCompanion(
          lastAreaJson: Value(
            jsonEncode(const DistrictsArea({'osm:r2'}).toJson()),
          ),
        ),
      );
      expect(await db.savedRound(now), isNull);
    });
  });

  test('answers come back in the order they were given', () async {
    final id = await round(['a', 'b']);
    await answer(id, 'b', Tier.close);
    await answer(id, 'a', Tier.great);
    expect((await db.answersForRound(id)).map((a) => a.streetId), ['b', 'a']);
  });

  test('bestTierByPart keeps the best tier per part, per city', () async {
    final id = await round(['a', 'b']);
    await answer(id, 'a', Tier.great);
    await answer(id, 'b', Tier.close);
    await answer(id, 'a', Tier.miss);
    final elsewhere = await round(['c'], cityId: 'batumi');
    await answer(elsewhere, 'c', Tier.perfect);
    expect(await db.bestTierByPart('tbilisi'), {
      'a': Tier.great,
      'b': Tier.close,
    });
    expect(
      await db.bestTierByPart(
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
    expect(await db.askedInLastRounds('tbilisi', count: 2), {'b', 'c', 'd'});
  });

  test('retrySet is the Close and Miss streets in round order', () async {
    final id = await round(['a', 'b', 'c', 'd']);
    await answer(id, 'd', Tier.miss);
    await answer(id, 'a', Tier.close);
    await answer(id, 'b', Tier.perfect);
    await answer(id, 'c', Tier.great);
    expect(await db.retrySet(id), ['a', 'd']);
  });

  test(
    'settings area is unset until picked; old and bad forms read as unset',
    () async {
      expect((await db.readSettings()).area, isNull);
      await db.updateSettings(
        UserSettingsCompanion(lastAreaJson: Value(jsonEncode(vake.toJson()))),
      );
      expect((await db.readSettings()).area, vake);
      for (final unreadable in [
        '[]',
        '{"kind":"planet"}',
        '{"kind":"city"}',
        'not json',
      ]) {
        await db.updateSettings(
          UserSettingsCompanion(lastAreaJson: Value(unreadable)),
        );
        expect((await db.readSettings()).area, isNull, reason: unreadable);
      }
    },
  );
}
