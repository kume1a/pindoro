import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/app/app.dart';
import 'package:pindoro/app/config.dart';
import 'package:pindoro/app/database.dart';
import 'package:pindoro/app/router.dart';
import 'package:pindoro/features/map/pindoro_map.dart';
import 'package:pindoro/features/pack/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });
  tearDown(() => db.close());

  Future<void> pumpApp(WidgetTester tester, String location) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          pindoroMapBuilderProvider.overrideWithValue(
            (map) => const SizedBox(),
          ),
          packRepositoryProvider.overrideWith((ref) async {
            final repo = SqlitePackRepository.open(AppConfig.fixturePackAsset);
            ref.onDispose(repo.close);
            return repo;
          }),
        ],
        child: PindoroApp(initialLocation: location),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, String label) async {
    await tester.runAsync(() async {
      await tester.tap(find.text(label));
      // Drift work happens on real async; give it a moment to finish.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'onboarding walks welcome -> city -> area -> difficulty -> round',
    (tester) async {
      await pumpApp(tester, Routes.welcome);
      expect(find.text('პინდორო'), findsOneWidget);

      await tapAndSettle(tester, 'Start');
      expect(find.text('City'), findsOneWidget);
      await tapAndSettle(tester, 'Tbilisi');
      expect(find.text('Area'), findsOneWidget);
      await tapAndSettle(tester, 'ვაკის რაიონი');
      expect(find.text('Difficulty'), findsOneWidget);
      await tapAndSettle(tester, 'expert');
      expect(find.text('Confirm'), findsOneWidget);

      final settings = await tester.runAsync(db.readSettings);
      expect(settings!.lastCity, 'tbilisi');
      expect(settings.lastDifficulty, Difficulty.expert);
    },
  );

  testWidgets('settings lead to the map data credits', (tester) async {
    await pumpApp(tester, Routes.home);
    expect(find.text('Play'), findsOneWidget);

    await tapAndSettle(tester, 'Settings');
    await tester.scrollUntilVisible(find.text('Map data credits'), 200);
    await tapAndSettle(tester, 'Map data credits');
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
  });

  testWidgets('settings apply at once and persist', (tester) async {
    await pumpApp(tester, Routes.settings);
    await tapAndSettle(tester, 'Dark');
    await tapAndSettle(tester, 'ქართული');
    final settings = (await tester.runAsync(db.readSettings))!;
    expect(settings.theme, ThemePreference.dark);
    expect(settings.appLanguage, AppLanguage.ka);
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.dark,
    );
  });
}
