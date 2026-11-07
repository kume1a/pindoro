import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';

void main() {
  late AppDatabase db;
  late SettingsDao settings;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsDao(db);
  });
  tearDown(() => db.close());

  const vake = DistrictsArea({'osm:r1'});

  test(
    'settings area is unset until picked; old and bad forms read as unset',
    () async {
      expect((await settings.read()).area, isNull);
      await settings.chooseArea(vake);
      expect((await settings.read()).area, vake);
      for (final unreadable in [
        '[]',
        '{"kind":"planet"}',
        '{"kind":"city"}',
        'not json',
      ]) {
        await db
            .into(db.userSettings)
            .insertOnConflictUpdate(
              UserSettingsCompanion(
                id: const Value(1),
                lastAreaJson: Value(unreadable),
              ),
            );
        expect((await settings.read()).area, isNull, reason: unreadable);
      }
    },
  );

  test('a new city clears the area; the same city keeps it', () async {
    await settings.chooseArea(vake, cityId: 'tbilisi');
    await settings.chooseCity('tbilisi');
    expect((await settings.read()).area, vake);
    await settings.chooseCity('batumi');
    final now = await settings.read();
    expect(now.lastCity, 'batumi');
    expect(now.area, isNull);
  });

  test('each write changes only its own column', () async {
    await settings.chooseDifficulty(Difficulty.hard);
    await settings.setTheme(ThemePreference.dark);
    await settings.setHaptics(on: false);
    await settings.markHomeCoachSeen();
    final now = await settings.read();
    expect(now.lastDifficulty, Difficulty.hard);
    expect(now.theme, ThemePreference.dark);
    expect(now.haptics, isFalse);
    expect(now.sound, isTrue);
    expect(now.homeCoachSeen, isTrue);
  });
}
