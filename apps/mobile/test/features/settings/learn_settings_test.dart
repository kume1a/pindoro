import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/app/app.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/map/ui/area_picker_map.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_design/pindoro_design.dart';

import '../../support/settle.dart';

void main() {
  late AppDatabase db;

  setUp(
    () => db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    ),
  );
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1080, 4400)
      ..devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          pindoroMapBuilderProvider.overrideWithValue((_) => const SizedBox()),
          areaPickerMapBuilderProvider.overrideWithValue(
            (_) => const SizedBox.expand(),
          ),
          packRepositoryProvider.overrideWith((ref) async {
            final repo = SqlitePackRepository.open(AppConfig.fixturePackAsset);
            ref.onDispose(repo.close);
            return repo;
          }),
        ],
        child: const PindoroApp(initialLocation: Routes.learnSettings),
      ),
    );
    await settle(tester);
  }

  testWidgets(
    'minutes a day and home: picked, saved and shown',
    timeout: const Timeout(Duration(minutes: 1)),
    (tester) async {
      await pump(tester);
      await tapThrough(tester, find.text('30 min'));
      expect((await db.select(db.userSettings).getSingle()).minutesPerDay, 30);
      expect(find.textContaining('About 14 new streets a day'), findsOneWidget);

      expect(find.text('Not set'), findsNWidgets(2));
      await tapThrough(tester, find.text('Home'));
      expect(find.text('Set as home'), findsOneWidget);
      await tapThrough(tester, find.byType(PindoroChip).first);
      await tapThrough(tester, find.text('Set as home'));

      final city = await LearningDao(db).learnCity(AppConfig.defaultCityId);
      expect(city?.homeId, isNotNull);
      expect(find.textContaining('learning starts here'), findsOneWidget);
      expect(find.text('Not set'), findsOneWidget);
    },
  );
}
