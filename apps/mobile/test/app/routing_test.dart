import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/app/app.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/setup/ui/area_map.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

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
          areaPickerMapBuilderProvider.overrideWithValue(
            (map) => const SizedBox.expand(),
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

  Future<void> tapLabelled(WidgetTester tester, String label) async {
    await tester.runAsync(() async {
      await tester.tap(find.bySemanticsLabel(label).first);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('first run: welcome -> city -> area -> difficulty -> round', (
    tester,
  ) async {
    await pumpApp(tester, Routes.welcome);
    expect(find.text('No recent cities yet'), findsOneWidget);

    await tapAndSettle(tester, 'Choose a city');
    await tapAndSettle(tester, 'Tbilisi');
    expect(find.text('Pick an area first'), findsOneWidget);

    // Zoomed in, the chips are Vake's quarters and neighbourhoods.
    await tapAndSettle(tester, 'ვაკე');
    await tapAndSettle(tester, 'Next');
    expect(find.text('Choose a difficulty'), findsOneWidget);

    await tapAndSettle(tester, 'Expert');
    await tester.scrollUntilVisible(
      find.text('How close counts at Expert'),
      200,
    );
    expect(find.text('Within 50 m'), findsOneWidget);
    await tapAndSettle(tester, 'Start');
    expect(find.text('Confirm'), findsOneWidget);

    final settings = (await tester.runAsync(SettingsDao(db).read))!;
    expect(settings.lastCity, 'tbilisi');
    final pack = SqlitePackRepository.open(AppConfig.fixturePackAsset);
    final quarter = pack.districts().firstWhere((d) => d.nameKa == 'ვაკე');
    pack.close();
    expect(settings.area, DistrictsArea({quarter.id}));
    expect(settings.lastDifficulty, Difficulty.expert);
  });

  testWidgets('the area picker seeds a circle from the picked districts', (
    tester,
  ) async {
    await pumpApp(tester, Routes.area);
    await tapAndSettle(tester, 'ვაკე');
    await tapAndSettle(tester, 'Circle');
    expect(find.byType(Slider), findsOneWidget);
    await tapAndSettle(tester, 'Next');
    final area = (await tester.runAsync(SettingsDao(db).read))!.area;
    expect(area, isA<CircleArea>());
  });

  testWidgets('a district from Home starts the picker without saving it', (
    tester,
  ) async {
    await pumpApp(tester, Routes.areaFrom(AppConfig.fixtureDistrictId));
    final chips = tester.widgetList<PindoroChip>(find.byType(PindoroChip));
    expect(chips.where((c) => c.selected), hasLength(1));
    expect(find.text('Pick an area first'), findsNothing);
    expect((await tester.runAsync(SettingsDao(db).read))!.area, isNull);

    // Opened as the only page, back goes Home instead of failing.
    await tapLabelled(tester, 'Back');
    expect(find.text('Streets you know'), findsOneWidget);
  });

  testWidgets('settings lead to the map data credits', (tester) async {
    await tester.runAsync(() => SettingsDao(db).markHomeCoachSeen());
    await pumpApp(tester, Routes.home);
    await tapLabelled(tester, 'Settings');
    await tester.scrollUntilVisible(find.text('Map data credits'), 200);
    await tapAndSettle(tester, 'Map data credits');
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
  });

  testWidgets('settings apply at once and persist', (tester) async {
    await pumpApp(tester, Routes.settings);
    await tapAndSettle(tester, 'Dark');
    await tapAndSettle(tester, 'ქართული');
    final settings = (await tester.runAsync(SettingsDao(db).read))!;
    expect(settings.theme, ThemePreference.dark);
    expect(settings.appLanguage, AppLanguage.ka);
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.dark,
    );
  });
}
