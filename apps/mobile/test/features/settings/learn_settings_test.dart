import 'dart:convert';

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
import 'package:pindoro_learning/pindoro_learning.dart';

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

  Future<void> pump(
    WidgetTester tester, {
    String at = Routes.learnSettings,
  }) async {
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
        child: PindoroApp(initialLocation: at),
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

  testWidgets('memory model: calibration by predicted recall, and fitted '
      'weights pasted, checked and saved', (tester) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 20; i++) {
        await LearningDao(db).saveAnswer(
          log: LogEntry(
            ts: DateTime(2026, 3, 2, 9, i),
            itemId: 'P:s$i',
            format: ReviewFormat.review,
            rating: i < 18 ? Rating.good : Rating.again,
            source: ReviewSource.session,
            elapsedDays: 4,
            rBefore: 0.92,
          ),
        );
      }
    });
    await pump(tester, at: Routes.memoryModel);
    expect(find.text('90–100 % predicted'), findsOneWidget);
    expect(find.text('Recalled 90 % · 20 reviews'), findsOneWidget);
    expect(find.text('The default weights'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '[1, 2, 3]');
    await tapThrough(tester, find.text('Use these weights'));
    expect(find.text('That isn’t a set of 21 FSRS weights.'), findsOneWidget);
    Future<String?> stored() async => (await tester.runAsync(
      () => db.select(db.userSettings).getSingleOrNull(),
    ))?.fsrsWeights;
    expect(await stored(), isNull);

    final fitted = [...LearningConfig.fsrsWeights]..[0] = 0.4;
    await tester.enterText(
      find.byType(TextField),
      jsonEncode({'weights': fitted}),
    );
    await tapThrough(tester, find.text('Use these weights'));
    expect(jsonDecode((await stored())!), fitted);
    await tapThrough(tester, find.text('Back to the default weights'));
    expect(await stored(), isNull);
  });
}
