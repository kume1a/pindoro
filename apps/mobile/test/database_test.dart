import 'package:drift/drift.dart';
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
}
