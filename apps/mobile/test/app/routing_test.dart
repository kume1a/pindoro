import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/app/app.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/home/ui/home_screen.dart';
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
    await tester.ensureVisible(find.text(label));
    await tester.pump();
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
    expect(chips.where((c) => c.selected ?? false), hasLength(1));
    expect(find.text('Pick an area first'), findsNothing);
    expect((await tester.runAsync(SettingsDao(db).read))!.area, isNull);

    // Opened as the only page, back goes Home instead of failing.
    await tapLabelled(tester, 'Back');
    expect(find.text('Streets you know'), findsOneWidget);
  });

  /// The system back button (Android back, the iOS edge swipe's pop).
  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  Finder freePlayList() => find
      .descendant(
        of: find.byType(HomeScreen),
        matching: find.byType(Scrollable),
      )
      .first;

  testWidgets('tabs keep their place; back goes to Free play first', (
    tester,
  ) async {
    await tester.runAsync(() => SettingsDao(db).markHomeCoachSeen());
    tester.view
      ..physicalSize = const Size(1080, 1400)
      ..devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await pumpApp(tester, Routes.home);
    expect(find.bySemanticsLabel('Settings'), findsNothing);

    await tester.drag(freePlayList(), const Offset(0, -200));
    await tester.pumpAndSettle();
    double offset() =>
        tester.state<ScrollableState>(freePlayList()).position.pixels;
    expect(offset(), greaterThan(0));

    await tapLabelled(tester, 'Me');
    // Me's numbers load from the database on real async.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Lessons'), findsOneWidget);
    expect(find.text('Streets you know'), findsNothing);

    await systemBack(tester);
    expect(find.text('Streets you know'), findsOneWidget);
    expect(offset(), greaterThan(0), reason: 'the tab kept its scroll');

    await tapLabelled(tester, 'Free play');
    expect(offset(), 0, reason: 'tapping the open tab scrolls it up');
  });

  testWidgets('settings lead to the map data credits', (tester) async {
    await pumpApp(tester, Routes.me);
    await tapLabelled(tester, 'Settings');
    await tester.scrollUntilVisible(find.text('Map data credits'), 200);
    await tapAndSettle(tester, 'Map data credits');
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
  });

  testWidgets('settings apply at once and persist', (tester) async {
    await pumpApp(tester, Routes.settings);
    await tapAndSettle(tester, 'Dark');
    // Back to the top, where the language control is.
    await tester.drag(find.byType(ListView), const Offset(0, 2000));
    await tester.pumpAndSettle();
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
