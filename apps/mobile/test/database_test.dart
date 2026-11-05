import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/app/database.dart';
import 'package:pindoro/app/router.dart';
import 'package:pindoro_core/pindoro_core.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('first run opens /welcome, afterwards /home', () async {
    expect(await initialLocation(db), Routes.welcome);
    await db.updateSettings(
      const UserSettingsCompanion(onboardingDone: Value(true)),
    );
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

  Future<String> round(List<String> streets) => db.startRound(
    cityId: 'tbilisi',
    area: const WholeCity(),
    difficulty: Difficulty.expert,
    packVersion: 'v1',
    streetIds: streets,
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

  test('startRound stores the planned streets in order', () async {
    final id = await round(['b', 'a', 'c']);
    final progress = await db.roundProgress(id);
    expect(progress.planned, ['b', 'a', 'c']);
    expect(progress.answers, isEmpty);
    expect(
      Area.fromJson(
        jsonDecode(progress.round.areaJson) as Map<String, Object?>,
      ),
      const WholeCity(),
    );
  });

  test('only the most recent unfinished round is resumable', () async {
    final older = await round(['a']);
    final newer = await round(['b']);
    expect((await db.resumableRound())?.id, newer);
    await db.finishRound(newer);
    expect(
      await db.resumableRound(),
      isNull,
      reason: 'the older unfinished round ($older) was abandoned',
    );
  });

  test('answers come back in the order they were given', () async {
    final id = await round(['a', 'b']);
    await answer(id, 'b', Tier.close);
    await answer(id, 'a', Tier.great);
    expect((await db.answersForRound(id)).map((a) => a.streetId), ['b', 'a']);
  });

  test('lastTierByStreet keeps the latest tier per street', () async {
    final id = await round(['a', 'b']);
    await answer(id, 'a', Tier.miss);
    await answer(id, 'b', Tier.great);
    await answer(id, 'a', Tier.perfect);
    expect(await db.lastTierByStreet(), {'a': Tier.perfect, 'b': Tier.great});
  });

  test('recentlyAnsweredStreetIds returns the latest streets', () async {
    final id = await round(['a', 'b', 'c']);
    for (final s in ['a', 'b', 'c']) {
      await answer(id, s, Tier.close);
    }
    expect(await db.recentlyAnsweredStreetIds(limit: 2), {'b', 'c'});
  });

  test('settings area defaults to the whole city', () async {
    expect((await db.readSettings()).area, const WholeCity());
    await db.updateSettings(
      UserSettingsCompanion(
        lastAreaJson: Value(jsonEncode(const DistrictArea('osm:r1').toJson())),
      ),
    );
    expect((await db.readSettings()).area, const DistrictArea('osm:r1'));
    for (final unreadable in ['[]', '{"kind":"planet"}', 'not json']) {
      await db.updateSettings(
        UserSettingsCompanion(lastAreaJson: Value(unreadable)),
      );
      expect(
        (await db.readSettings()).area,
        const WholeCity(),
        reason: unreadable,
      );
    }
  });
}
