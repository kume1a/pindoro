import 'package:drift/drift.dart' show DatabaseConnection, Value;
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
import 'package:pindoro/features/course/data/course_data.dart';
import 'package:pindoro/features/course/ui/path_screen.dart';
import 'package:pindoro/features/course/ui/unit_guide_screen.dart';
import 'package:pindoro/features/home/ui/home_screen.dart';
import 'package:pindoro/features/lesson/ui/drive_controller.dart';
import 'package:pindoro/features/lesson/ui/drive_screen.dart';
import 'package:pindoro/features/lesson/ui/lesson_screen.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/pack/data/app_update.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro/features/progress/ui/level_up_screen.dart';
import 'package:pindoro/features/setup/ui/area_map.dart';
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

  testWidgets('first run: welcome -> city -> first district -> the Path', (
    tester,
  ) async {
    calm(tester);
    await pumpApp(tester, Routes.welcome);
    expect(find.text('No recent cities yet'), findsOneWidget);

    await tapAndSettle(tester, 'Choose a city');
    await tapAndSettle(tester, 'Tbilisi');
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }
    expect(find.text('Where do you want to start?'), findsOneWidget);
    expect(find.text('ვაკის რაიონი'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^\d+ streets · \S')), findsOneWidget);
    expect(find.text('1 district · from OpenStreetMap'), findsOneWidget);
    expect(
      await tester.runAsync(() => ProgressDao(db).hasCourse()),
      isFalse,
      reason: 'nothing is saved before Start in',
    );

    await tapAndSettle(tester, 'Start in ვაკის რაიონი');
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }
    expect(find.byType(PathScreen), findsOneWidget);
    expect(find.text('0 of 6 lessons'), findsOneWidget);
    expect(
      await tester.runAsync(() => ProgressDao(db).courseStart('tbilisi')),
      'osm:r11300449',
    );
    expect(await tester.runAsync(() => startLocation(db)), Routes.path);
  });

  testWidgets('Free play: city -> area -> difficulty -> round', (tester) async {
    await pumpApp(tester, Routes.city);
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

  testWidgets('tabs keep their place; back goes to the Path first', (
    tester,
  ) async {
    calm(tester);
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
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Signpost).hitTestable(), findsWidgets);

    await tapLabelled(tester, 'Free play');
    expect(find.text('Streets you know'), findsOneWidget);
    expect(offset(), greaterThan(0), reason: 'the tab kept its scroll');

    await tapLabelled(tester, 'Free play');
    expect(offset(), 0, reason: 'tapping the open tab scrolls it up');
  });

  group('the Path', () {
    /// The Path, after waiting for its course to load on real async.
    Future<void> pumpPath(
      WidgetTester tester, {
      String location = Routes.path,
      bool roadGraph = true,
    }) async {
      calm(tester);
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await pumpApp(tester, location, roadGraph: roadGraph);
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      }
    }

    testWidgets('a played player opens on the Path', (tester) async {
      await tester.runAsync(() async {
        await ProgressDao(db).saveCourseStart('tbilisi', 'osm:r11300449');
        await db
            .into(db.lessonResults)
            .insert(
              LessonResultsCompanion.insert(
                cityId: 'tbilisi',
                unitId: 'osm:r11300449',
                kind: LessonKind.lesson,
                lesson: const Value(1),
                difficulty: Difficulty.medium,
                xp: 0,
                perfect: true,
                rightFirst: 6,
                tests: 6,
                durationMs: 1000,
              ),
            );
      });
      expect(await tester.runAsync(() => startLocation(db)), Routes.path);
    });

    testWidgets('unit 1 starts at lesson 1; its sheet offers to start', (
      tester,
    ) async {
      await pumpPath(tester);
      expect(find.text('ვაკის რაიონი'), findsOneWidget);
      expect(find.text('0 of 6 lessons'), findsOneWidget);
      final first = find.bySemanticsLabel(
        RegExp(r'^Lesson 1, .+ and 3 more\. Current\. Double-tap to start\.$'),
      );
      expect(first, findsOneWidget);
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(find.text('Start lesson'), findsOneWidget);
      expect(find.text('up to 670 XP'), findsOneWidget);
      expect(
        (await tester.runAsync(() => ProgressDao(db).courseStart('tbilisi'))),
        'osm:r11300449',
      );
    });

    testWidgets('a new course says Start here until a tap', (tester) async {
      await pumpPath(tester);
      expect(find.text('Start here'), findsOneWidget);
      expect(
        find.text(
          'Your first lesson: 4 streets in ვაკის რაიონი, then a short test.',
        ),
        findsOneWidget,
      );
      expect(find.text('Start'), findsNothing, reason: 'the coach replaces it');
      await tester.tapAt(const Offset(8, 600));
      await tester.pumpAndSettle();
      expect(find.text('Start here'), findsNothing);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('a placed lesson says its streets were known', (tester) async {
      await tester.runAsync(() async {
        final dao = ProgressDao(db);
        await dao.saveCourseStart('tbilisi', 'osm:r11300449');
        await dao.place('tbilisi', [('osm:r11300449', 1)]);
      });
      await pumpPath(tester);
      expect(find.text('Start here'), findsNothing);
      expect(find.text('1 of 6 lessons'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(RegExp(r'^Lesson 1, .+ Done\. ')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'You already knew these streets when the course started.',
        ),
        findsOneWidget,
      );
      expect(find.text('Practise again'), findsOneWidget);
    });

    testWidgets('a locked stop says what opens it', (tester) async {
      await pumpPath(tester);
      await tester.tap(
        find.bySemanticsLabel(RegExp(r'^Lesson 2, .+ Locked\.$')),
      );
      await tester.pump();
      expect(find.text('Lesson 2 is locked'), findsOneWidget);
      expect(find.text('Finish lesson 1 first.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Lesson 2 is locked'), findsNothing);
    });

    testWidgets('a done lesson offers Practise again', (tester) async {
      await tester.runAsync(() async {
        await ProgressDao(db).saveCourseStart('tbilisi', 'osm:r11300449');
        await db
            .into(db.lessonResults)
            .insert(
              LessonResultsCompanion.insert(
                cityId: 'tbilisi',
                unitId: 'osm:r11300449',
                kind: LessonKind.lesson,
                lesson: const Value(1),
                difficulty: Difficulty.medium,
                xp: 507,
                perfect: false,
                rightFirst: 4,
                tests: 6,
                durationMs: 192000,
              ),
            );
      });
      await pumpPath(tester);
      expect(find.text('1 of 6 lessons'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(RegExp(r'^Lesson 1, .+ Done\. ')));
      await tester.pumpAndSettle();
      expect(find.text('Practise again'), findsOneWidget);
      expect(
        find.textContaining('67 % accuracy · 507 XP · 3 min 12 s'),
        findsOneWidget,
      );
    });

    /// Lesson 1 of the fixture's unit done.
    Future<void> lessonOneDone(WidgetTester tester) =>
        tester.runAsync(() async {
          await ProgressDao(db).saveCourseStart('tbilisi', 'osm:r11300449');
          await db
              .into(db.lessonResults)
              .insert(
                LessonResultsCompanion.insert(
                  cityId: 'tbilisi',
                  unitId: 'osm:r11300449',
                  kind: LessonKind.lesson,
                  lesson: const Value(1),
                  difficulty: Difficulty.medium,
                  xp: 570,
                  perfect: true,
                  rightFirst: 6,
                  tests: 6,
                  durationMs: 1000,
                ),
              );
        });

    void playUnlock(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(PathScreen)))
            .read(pathUnlockProvider.notifier)
            .play((unitId: 'osm:r11300449', kind: StopKind.lesson, lesson: 1));

    PathStop lessonTwo(WidgetTester tester) => tester.widget<PathStop>(
      find.byWidgetPredicate(
        (w) => w is PathStop && w.semanticLabel.startsWith('Lesson 2,'),
      ),
    );

    double road(WidgetTester tester) =>
        tester.widget<LessonRoad>(find.byType(LessonRoad).first).driven;

    testWidgets(
      'the Unit guide: the book opens it, a done lesson narrows the map',
      (tester) async {
        await lessonOneDone(tester);
        await pumpPath(tester);
        await tapLabelled(tester, 'Unit guide');
        expect(find.byType(UnitGuideScreen), findsOneWidget);
        expect(find.text('Perfect · 4 streets'), findsOneWidget);
        expect(find.textContaining('Next · '), findsOneWidget);
        expect(find.text('Opens after lesson 3'), findsOneWidget);
        expect(find.text('Opens after lesson 6'), findsOneWidget);
        final whole = maps.last.truth!.length;
        expect(maps.last.frame, isNull, reason: 'framed on the district');

        await tapAndSettle(tester, 'Perfect · 4 streets');
        expect(maps.last.truth!.length, lessThan(whole));
        expect(maps.last.frame, isNotEmpty);
        expect(find.bySemanticsLabel(RegExp('On the map')), findsOneWidget);
        await tapAndSettle(tester, 'Perfect · 4 streets');
        expect(maps.last.truth!.length, whole);

        await tester.runAsync(() async {
          await tester.tap(find.textContaining('Next · '));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
        expect(find.byType(LessonScreen), findsOneWidget);
      },
    );

    testWidgets('See the streets opens the guide at that lesson', (
      tester,
    ) async {
      await lessonOneDone(tester);
      await pumpPath(tester);
      await tester.tap(find.bySemanticsLabel(RegExp(r'^Lesson 1, .+ Perfect')));
      await tester.pumpAndSettle();
      await tapAndSettle(tester, 'See the streets');
      expect(find.byType(UnitGuideScreen), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('On the map')), findsOneWidget);
    });

    testWidgets('the unlock paves the road and grows the next stop', (
      tester,
    ) async {
      await lessonOneDone(tester);
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(Routes.path));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(lessonTwo(tester).look, PathStopLook.current);

      playUnlock(tester);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(lessonTwo(tester).look, PathStopLook.locked);
      expect(road(tester), inExclusiveRange(1, 2));

      await tester.pump(const Duration(milliseconds: 600));
      expect(lessonTwo(tester).look, PathStopLook.current);
      expect(lessonTwo(tester).tip, 'Start');
      expect(road(tester), 2);
    });

    testWidgets('with reduce motion the unlock shows the final state', (
      tester,
    ) async {
      await lessonOneDone(tester);
      await pumpPath(tester);
      playUnlock(tester);
      await tester.pump();
      await tester.pump();
      expect(lessonTwo(tester).look, PathStopLook.current);
      expect(road(tester), 2);
    });

    /// The fixture unit's lessons and Pit stop done: its Final drive is
    /// current.
    Future<void> driveCurrent(WidgetTester tester) => tester.runAsync(() async {
      await ProgressDao(db).saveCourseStart('tbilisi', 'osm:r11300449');
      for (final lesson in [1, 2, 3, 4, 5, 6, null]) {
        await db
            .into(db.lessonResults)
            .insert(
              LessonResultsCompanion.insert(
                cityId: 'tbilisi',
                unitId: 'osm:r11300449',
                kind: lesson == null ? LessonKind.pitStop : LessonKind.lesson,
                lesson: Value(lesson),
                difficulty: Difficulty.medium,
                xp: 100,
                perfect: false,
                rightFirst: 6,
                tests: 6,
                durationMs: 1000,
              ),
            );
      }
    });

    Finder finalDrive() => find.bySemanticsLabel(
      RegExp(r'^Final drive\. Current\. .* 0 of 3 road trips passed\.$'),
    );

    testWidgets('without a road graph the Final drive sheet says so', (
      tester,
    ) async {
      await driveCurrent(tester);
      await pumpPath(tester, roadGraph: false);
      await tester.ensureVisible(finalDrive());
      await tester.pumpAndSettle();
      await tester.tap(finalDrive());
      await tester.pumpAndSettle();
      expect(find.textContaining('Road trips need the newest'), findsOneWidget);
      expect(find.text('Start the drive'), findsNothing);
    });

    testWidgets(
      'a drive with no trip to plan goes back to the Path, saying so',
      (tester) async {
        await driveCurrent(tester);
        await pumpPath(
          tester,
          location: Routes.driveOf('osm:r11300449'),
          roadGraph: false,
        );
        expect(find.byType(PathScreen), findsOneWidget);
        expect(
          find.text('There’s no road trip to drive here right now.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('the Final drive: 3 trips, Unit complete, level up, back on '
        'the Path', (tester) async {
      await driveCurrent(tester);
      await pumpPath(tester);
      await tester.ensureVisible(finalDrive());
      await tester.pumpAndSettle();
      await tester.tap(finalDrive());
      await tester.pumpAndSettle();
      expect(find.text('Drive across ვაკის რაიონი'), findsOneWidget);
      expect(find.text('3 road trips'), findsOneWidget);
      await tapAndSettle(tester, 'Start the drive');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(DriveScreen)),
      );
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Final drive ${i + 1} of 3: draw the shortest drive to'),
          findsOneWidget,
        );
        final play = container.read(driveControllerProvider) as DrivePlaying;
        var route = play.draft;
        for (final e in play.trip.best.edges) {
          route = route.take(e);
        }
        container.read(driveControllerProvider.notifier).drawTo(route);
        await tester.pumpAndSettle();
        await tapAndSettle(tester, 'Check route');
        expect(find.text('Best route!'), findsOneWidget);
        await tapAndSettle(tester, i < 2 ? 'Next' : 'Continue');
      }
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('ვაკის რაიონი complete!'), findsOneWidget);
      expect(find.bySemanticsLabel('Road trips, 3'), findsOneWidget);

      // 700 XP of lessons + 3 Perfect trips and the unit bonus cross level 2.
      await tester.pump(PindoroMotion.celebrateMedium);
      await tester.pumpAndSettle();
      expect(find.byType(LevelUpScreen), findsOneWidget);
      await tapAndSettle(tester, 'Continue');
      expect(find.byType(LevelUpScreen), findsNothing);

      await tapAndSettle(tester, 'Continue');
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      }
      expect(
        find.bySemanticsLabel(RegExp(r'^Final drive\. Passed\.$')),
        findsOneWidget,
      );
      expect(find.text('6 of 6 lessons'), findsOneWidget);
    });
  });

  group("What's new", () {
    const raion = 'osm:r11300449';

    /// A finished Free play round with a Great on [known] streets of each of
    /// the fixture unit's [lessons].
    Future<void> knowLessons(
      WidgetTester tester,
      List<int> lessons, {
      int known = 3,
    }) => tester.runAsync(() async {
      final pack = SqlitePackRepository.open(AppConfig.fixturePackAsset);
      final streets = streetsByPartId(pack.streets());
      final unit = buildCourse(
        districts: pack.districts(),
        streets: {...streets.values},
        lengthsByDistrict: pack.lengthsByDistrict(),
        startDistrictId: raion,
      ).first;
      pack.close();
      final ids = [
        for (final n in lessons)
          for (final s in unit.lessons[n - 1].streets.take(known)) s.id,
      ];
      final dao = ProgressDao(db);
      final roundId = await dao.startRound(
        cityId: 'tbilisi',
        area: const DistrictsArea({raion}),
        difficulty: Difficulty.medium,
        packVersion: 'v1',
        streetIds: ids,
      );
      for (final id in ids) {
        await dao.recordAnswer(
          roundId: roundId,
          streetId: id,
          pin: const LatLng(41.7, 44.75),
          distanceM: 10,
          tier: Tier.great,
          xp: 80,
          packVersion: 'v1',
        );
      }
      await dao.finishRound(roundId);
    });

    Future<void> pumpWhatsNew(WidgetTester tester) async {
      calm(tester);
      expect(await tester.runAsync(() => startLocation(db)), Routes.whatsNew);
      await pumpApp(tester, Routes.whatsNew);
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      }
    }

    Future<List<LessonResult>> placed(WidgetTester tester) async =>
        (await tester.runAsync(
          () => ProgressDao(db).lessonResultsIn('tbilisi'),
        ))!.where((r) => r.kind == LessonKind.placed).toList();

    testWidgets('placement offers the next lesson and opens it', (
      tester,
    ) async {
      await knowLessons(tester, [1, 2]);
      await pumpWhatsNew(tester);
      expect(find.text('Tbilisi is now a course'), findsOneWidget);
      await tapAndSettle(tester, 'Show me my path');
      await settle(tester);
      expect(find.text('You start in Unit 1'), findsOneWidget);
      expect(
        find.text('2 of 6 lessons done · lesson 3 is next'),
        findsOneWidget,
      );
      await tapAndSettle(tester, 'Start lesson 3');
      await settle(tester);
      expect(find.byType(LessonScreen), findsOneWidget);
      expect([for (final r in await placed(tester)) r.lesson], [1, 2]);
      expect(await tester.runAsync(() => startLocation(db)), Routes.path);
    });

    testWidgets('Start from Unit 1 instead places nothing', (tester) async {
      await knowLessons(tester, [1, 2]);
      await pumpWhatsNew(tester);
      await tapAndSettle(tester, 'Show me my path');
      await settle(tester);
      await tapAndSettle(tester, 'Start from Unit 1 instead');
      await settle(tester);
      expect(find.byType(PathScreen), findsOneWidget);
      expect(await placed(tester), isEmpty);
      expect(
        await tester.runAsync(() => ProgressDao(db).courseStart('tbilisi')),
        raion,
      );
    });

    testWidgets('too few known streets go straight to the Path', (
      tester,
    ) async {
      await knowLessons(tester, [1, 2], known: 2);
      await pumpWhatsNew(tester);
      await tapAndSettle(tester, 'Show me my path');
      await settle(tester);
      expect(find.byType(PathScreen), findsOneWidget);
      expect(find.text('0 of 6 lessons'), findsOneWidget);
      expect(await placed(tester), isEmpty);
    });
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
    await tester.scrollUntilVisible(find.text('Choose turns from a list'), 300);
    await tapAndSettle(tester, 'Choose turns from a list');
    await tapAndSettle(tester, 'Dark');
    // Back to the top, where the language control is.
    await tester.drag(find.byType(ListView), const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tapAndSettle(tester, 'ქართული');
    final settings = (await tester.runAsync(SettingsDao(db).read))!;
    expect(settings.theme, ThemePreference.dark);
    expect(settings.appLanguage, AppLanguage.ka);
    expect(settings.turnList, isTrue);
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.dark,
    );
  });
}
