import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pindoro/app/app.dart';
import 'package:pindoro/app/router.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/drive/ui/drive_screen.dart';
import 'package:pindoro/features/drive/ui/drive_tab.dart';
import 'package:pindoro/features/map/ui/area_picker_map.dart';
import 'package:pindoro/features/map/ui/explore_map.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/memory/ui/progress_screen.dart';
import 'package:pindoro/features/pack/data/app_update.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/today/ui/today_screen.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

void main() {
  late AppDatabase db;

  /// Every map the screens built, latest last.
  final maps = <PindoroMap>[];

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });
  tearDown(() => db.close());

  /// The Path's current stop floats for good; tests that show the Path
  /// settle without motion.
  void calm(WidgetTester tester) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  /// The app at [location]; [roadGraph] false plays a pack without one;
  /// [update] is a newer build's link, as the catalog would offer it.
  Widget app(String location, {bool roadGraph = true, Uri? update}) =>
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          if (!roadGraph) roadGraphProvider.overrideWith((ref) async => null),
          if (update != null) ...[
            packageInfoProvider.overrideWith(
              (ref) async => PackageInfo(
                appName: 'Pindoro',
                packageName: 'app.pindoro',
                version: '2.1.0',
                buildNumber: '2',
              ),
            ),
            appUpdateProvider.overrideWith((ref) async => update),
          ],
          exploreMapBuilderProvider.overrideWithValue(
            (_) => const SizedBox.expand(),
          ),
          pindoroMapBuilderProvider.overrideWithValue((map) {
            maps.add(map);
            return const SizedBox();
          }),
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
      );

  Future<void> pumpApp(
    WidgetTester tester,
    String location, {
    bool roadGraph = true,
    Uri? update,
  }) async {
    await tester.pumpWidget(
      app(location, roadGraph: roadGraph, update: update),
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

  testWidgets('first run: welcome -> Today, which offers placement', (
    tester,
  ) async {
    calm(tester);
    await pumpApp(tester, Routes.welcome);

    await tapAndSettle(tester, 'Start learning');
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.text('Let’s see what you already know'), findsOneWidget);
    expect(await tester.runAsync(() => startLocation(db)), Routes.welcome);

    await tapAndSettle(tester, 'Start from zero');
    for (var i = 0; i < 2; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }
    expect(find.text('Let’s see what you already know'), findsNothing);
    expect(await tester.runAsync(() => startLocation(db)), Routes.driveTab);
  });

  testWidgets('Explore: area -> difficulty -> round', (tester) async {
    await pumpApp(tester, Routes.area);
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
    expect(find.text('Tbilisi in memory'), findsOneWidget);
  });

  testWidgets("a later pick takes the narrowing toast's Undo away", (
    tester,
  ) async {
    await pumpApp(tester, Routes.areaFrom(AppConfig.fixtureDistrictId));
    await tapAndSettle(tester, 'ვაკე');
    expect(find.text('Only ვაკე now'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    final unpicked = find.byWidgetPredicate(
      (w) => w is PindoroChip && !(w.selected ?? false),
    );
    await tester.tap(unpicked.first);
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);
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

  Finder progressList() => find
      .descendant(
        of: find.byType(ProgressScreen),
        matching: find.byType(Scrollable),
      )
      .first;

  testWidgets('tabs keep their place; back goes to Drive first', (
    tester,
  ) async {
    calm(tester);
    tester.view
      ..physicalSize = const Size(1080, 1400)
      ..devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await pumpApp(tester, Routes.progress);

    await tester.drag(progressList(), const Offset(0, -200));
    await tester.pumpAndSettle();
    double offset() =>
        tester.state<ScrollableState>(progressList()).position.pixels;
    expect(offset(), greaterThan(0));

    await tapLabelled(tester, 'Me');
    // Me's numbers load from the database on real async.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pins dropped'), findsOneWidget);
    expect(find.text('Reviews, next 14 days'), findsNothing);

    await systemBack(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DriveTab).hitTestable(), findsOneWidget);

    await tapLabelled(tester, 'Progress');
    expect(offset(), greaterThan(0), reason: 'the tab kept its scroll');

    await tapLabelled(tester, 'Progress');
    expect(offset(), 0, reason: 'tapping the open tab scrolls it up');
  });

  testWidgets('a pick on the Drive tab opens the drive over the tabs', (
    tester,
  ) async {
    await pumpApp(tester, Routes.driveTab);
    expect(find.byType(DriveTab), findsOneWidget);
    await tapAndSettle(tester, 'Surprise me');
    expect(find.byType(DriveScreen), findsOneWidget);
    expect(find.byType(PindoroNavBar).hitTestable(), findsNothing);
  });

  testWidgets('settings lead to the map data credits', (tester) async {
    await pumpApp(tester, Routes.me);
    await tapLabelled(tester, 'Settings');
    await tester.scrollUntilVisible(find.text('Map data credits'), 200);
    await tapAndSettle(tester, 'Map data credits');
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
  });

  testWidgets('a newer build is offered at launch and in Settings', (
    tester,
  ) async {
    await pumpApp(
      tester,
      Routes.settings,
      update: Uri.parse('https://packs.test/app/pindoro-3.apk'),
    );
    expect(find.text('A new Pindoro is out'), findsOneWidget);
    await tapAndSettle(tester, 'Later');
    expect(find.text('A new Pindoro is out'), findsNothing);
    await tester.scrollUntilVisible(find.text('Version 2.1.0 (2)'), 300);
    expect(
      find.text('A newer version is out. Tap to download it.'),
      findsOneWidget,
    );
  });

  testWidgets('settings apply at once and persist', (tester) async {
    await pumpApp(tester, Routes.settings);
    await tester.scrollUntilVisible(find.text('Dark'), 300);
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
