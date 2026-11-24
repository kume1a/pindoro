import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/core/database/database.dart';

import 'generated/schema.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('the current schemaVersion has a committed schema dump', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(GeneratedHelper.versions.last, db.schemaVersion);
    await db.close();
  });

  test('v31 keeps the answer log and its trigger, and takes an answer with '
      'no pin', () async {
    final schema = await verifier.schemaAt(30);
    schema.rawDatabase
      ..execute(
        'INSERT INTO round (id, city_id, area_json, difficulty, pack_version, '
        "started_at) VALUES ('r', 'tbilisi', '{}', 'easy', '1', "
        "'2026-11-24T10:00:00.000')",
      )
      ..execute(
        'INSERT INTO answer (id, round_id, street_id, pin_lat, pin_lon, '
        "distance_m, tier, pack_version, created_at) VALUES ('a', 'r', 's', "
        "41.7, 44.8, 120, 'great', '1', '2026-11-24T10:00:01.000')",
      );
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 31);
    final kept = await db.customSelect('SELECT distance_m FROM answer').get();
    expect(kept.single.read<double>('distance_m'), 120);
    await db.customStatement(
      'INSERT INTO answer (id, round_id, street_id, tier, pack_version, '
      "created_at) VALUES ('b', 'r', 's', 'miss', '1', "
      "'2026-11-24T10:00:02.000')",
    );
    await expectLater(
      db.customStatement("UPDATE answer SET tier = 'perfect' WHERE id = 'a'"),
      throwsA(anything),
    );
    await db.close();
  });

  for (final from in GeneratedHelper.versions) {
    test('migrates from v$from to the current schema', () async {
      final schema = await verifier.schemaAt(from);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, db.schemaVersion);
      await db.close();
    });
  }
}
