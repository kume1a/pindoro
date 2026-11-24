import 'dart:async';
import 'dart:math' show cos, pi, sin;

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/compass.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/drive_device.dart';
import 'package:pindoro/core/location.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/drive/ui/debrief_data.dart';
import 'package:pindoro/features/drive/ui/drive_controller.dart';
import 'package:pindoro/features/drive/ui/drive_map_screen.dart';
import 'package:pindoro/features/drive/ui/drive_preview_screen.dart';
import 'package:pindoro/features/drive/ui/drive_recording_view.dart';
import 'package:pindoro/features/drive/ui/drive_route_screen.dart';
import 'package:pindoro/features/drive/ui/drive_screen.dart';
import 'package:pindoro/features/drive/ui/drive_tab.dart';
import 'package:pindoro/features/drive/ui/past_drives_screen.dart';
import 'package:pindoro/features/drive/ui/plan_map.dart';
import 'package:pindoro/features/drive/ui/route_place_screen.dart';
import 'package:pindoro/features/learning/data/drive_log.dart';
import 'package:pindoro/features/learning/data/drive_places.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/nav_data.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/learning/ui/drive_week_card.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/ui/drive_map.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

import '../../support/settle.dart';

void main() {
  late AppDatabase db;
  late List<Override> overrides;
  late ProviderContainer container;
  late _Track location;
  late Route route;
  late Map<String, NamedStreet> streets;
  late List<District> districts;
  final now = DateTime(2026, 11, 16, 9);
  late DateTime clockNow;
  late _Device device;
  final maps = <DriveMap>[];
  final plans = <PindoroMap>[];
  late StreamController<double> compass;

  /// The run's start as Home (its OSM node), and its bearing from the end.
  late int homeNode;
  late double homeBearing;

  /// The run's end (its OSM node), a drive away from where the phone starts.
  late int endNode;

  /// A spot 20 m beside the middle of a two-way named road (two stops, item 132), and a pack
  /// landmark.
  late LatLng beside;
  late Landmark landmark;

  setUpAll(() {
    final repo = SqlitePackRepository.open(AppConfig.fixturePackAsset);
    final graph = repo.roadGraph()!;
    streets = streetsByPartId(repo.streets());
    districts = repo.districts();
    final ids = graph.junctions.keys.toList()..sort();
    route =
        [
          for (var i = 0; i < ids.length; i += 37)
            graph.shortestRoute(ids[i], {ids[(i * 7 + 11) % ids.length]}),
        ].nonNulls.firstWhere(
          (r) =>
              r.lengthM > 1000 &&
              r.lengthM < 2500 &&
              r.edges.first.streetId != null &&
              r.edges.last.streetId != null,
        );
    homeNode = repo.junctionNodes()[route.junctions.first]!;
    endNode = repo.junctionNodes()[route.junctions.last]!;
    homeBearing = bearingDegrees(
      graph.at(route.junctions.last),
      graph.at(route.junctions.first),
    );
    beside = graph.edges
        .where((e) => e.streetId != null && e.oneway == Oneway.both)
        .map(_beside)
        .firstWhere((spot) => stopsNear(graph, spot).length == 2);
    landmark = repo.landmarks().first;
    repo.close();
  });

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    clockNow = now;
    maps.clear();
    plans.clear();
    compass = StreamController<double>.broadcast();
    location = _Track(route.lines.first.first);
    device = _Device();
    overrides = [
      databaseProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(() => clockNow),
      locationServiceProvider.overrideWithValue(location),
      driveDeviceProvider.overrideWithValue(device),
      compassProvider.overrideWithValue(compass.stream),
      packRepositoryProvider.overrideWith((ref) async {
        final repo = SqlitePackRepository.open(AppConfig.fixturePackAsset);
        ref.onDispose(repo.close);
        return repo;
      }),
      todayRunProvider.overrideWith(
        (ref) async => (
          run: (
            id: 'n1:n2',
            fromNode: 1,
            toNode: 2,
            random: false,
            items: const <String>[],
            createdAt: now,
          ),
          ends: (
            from: route.junctions.first,
            to: route.junctions.last,
            best: route,
            fromStreet: streets[route.edges.first.streetId]!,
            toStreet: streets[route.edges.last.streetId]!,
          ),
          dueTurns: 0,
        ),
      ),
      pindoroMapBuilderProvider.overrideWithValue((map) {
        plans.add(map);
        return const SizedBox.expand();
      }),
      driveMapBuilderProvider.overrideWithValue((map) {
        maps.add(map);
        return const SizedBox.expand();
      }),
    ];
    container = ProviderContainer(overrides: overrides);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    await compass.close();
  });

  /// The setup once its destination is found (or not).
  Future<DriveSetup> settled() async {
    for (var i = 0; i < 50; i++) {
      final s = container.read(driveControllerProvider) as DriveSetup;
      if (s.target != null || s.noTarget) return s;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return container.read(driveControllerProvider) as DriveSetup;
  }

  /// The drive controller with today's run chosen.
  DriveController runController() {
    container.listen(driveControllerProvider, (_, _) {});
    return container.read(driveControllerProvider.notifier)
      ..choose(DriveTo.run);
  }

  test('a drive of today\'s run records in the background, then replays as '
      'its matched path graded against the best route', () async {
    final controller = runController();
    await controller.start(title: 'Recording', text: 'End it in Pindoro');
    final recording = container.read(driveControllerProvider);
    expect(recording, isA<DriveRecording>());
    expect((recording as DriveRecording).target.junction, route.junctions.last);
    expect(location.notice, ('Recording', 'End it in Pindoro'));
    await location.drive(route, now);
    await controller.end();
    final review = container.read(driveControllerProvider) as DriveReview;
    expect(review.match.path.edges.map((e) => e.id), [
      for (final e in route.edges) e.id,
    ]);
    expect(review.graded!.tier, Tier.perfect);
    expect(review.stoppedM, isNull);
    expect(review.match.uTurns, isEmpty);
    expect(review.gaps.count, 0);
    expect(location.cancelled, isTrue);

    final log = container.read(driveLogDaoProvider);
    final drive = (await log.all()).single;
    expect(drive.level, DriveLevel.off);
    expect(drive.goal, DriveTo.run.name);
    expect(drive.outcome, DriveOutcome.arrived);
    expect(drive.tier, Tier.perfect);
    expect(drive.fixes, location.sent);
    expect(drive.gpsGaps, 0);
    expect(await log.track(drive.id), hasLength(location.sent));
    final decisions = await db.select(db.driveDecisions).get();
    expect(decisions, isNotEmpty);
    expect(
      decisions.every((d) => d.driveId == drive.id && d.ok == true),
      isTrue,
    );
    expect(decisions.map((d) => d.seq), [
      for (var i = 0; i < decisions.length; i++) i,
    ]);
    expect(
      () => db.customStatement('DELETE FROM drive_decision'),
      throwsA(anything),
    );
    final replay = await container.read(pastDriveProvider(drive.id).future);
    expect(replay!.match.path.edges.map((e) => e.id), [
      for (final e in route.edges) e.id,
    ]);
    expect(replay.graded!.tier, Tier.perfect);
    expect(replay.credited, review.credited);
  });

  test('a destination changed on the way is graded from where it changed: '
      'the way before it is no detour', () async {
    final controller = runController();
    await settled();
    controller.pickLevel(DriveLevel.quiet);
    await controller.start(title: 't', text: 't');
    final half = route.edges.length ~/ 2;
    final before = route.edges.take(half).toList();
    final after = route.edges.skip(half).toList();
    final first = Route(route.junctions.take(half + 1).toList(), before, 0);
    final stoppedAt = await location.drive(first, now);
    await location.park(first.lines.last.last, stoppedAt, 3);
    await controller.changeDestination((
      street: streets[route.edges.last.streetId]!,
      place: null,
      junction: route.junctions.last,
      at: null,
    ));
    await location.drive(
      Route(route.junctions.skip(half).toList(), after, 0),
      stoppedAt.add(const Duration(seconds: 4)),
    );
    await controller.end();
    final review = container.read(driveControllerProvider) as DriveReview;
    expect(
      route.junctions.skip(half - 1),
      contains(review.graded!.path!.junctions.first),
    );
    expect(review.match.path.junctions.first, route.junctions.first);
  });

  test('a drive that loses GPS logs its gaps and says so', () async {
    final controller = runController();
    await controller.start(title: 't', text: 't');
    final lastFix = await location.drive(route, now);
    clockNow = lastFix.add(const Duration(seconds: 130));
    await controller.end();
    final review = container.read(driveControllerProvider) as DriveReview;
    expect(review.gaps, (count: 1, longest: const Duration(seconds: 130)));
    final drive = (await container.read(driveLogDaoProvider).all()).single;
    expect(drive.gpsGaps, 1);
    expect(drive.longestGapS, 130);
  });

  test('a double tap on Start or I’m there records and saves once', () async {
    final controller = runController();
    // The fake's track allows one listener: a second start would throw.
    await Future.wait([
      controller.start(title: 't', text: 't'),
      controller.start(title: 't', text: 't'),
    ]);
    await location.drive(route, now);
    await Future.wait([controller.end(), controller.end()]);
    expect(await db.select(db.implicitEvidence).get(), isNotEmpty);
    expect(await container.read(driveLogDaoProvider).all(), hasLength(1));
  });

  test(
    'setup finds the destination and suggests a level; today\'s run offers '
    'every level, Off first, another destination one step less at most',
    () async {
      final controller = runController();

      final run = await settled();
      expect(run.target!.junction, route.junctions.last);
      // A new player: few J cards in the raion, so Guided.
      expect(run.suggestion!.level, DriveLevel.guided);
      expect(run.suggestion!.turns, greaterThan(0));
      expect(run.chosen, DriveLevel.off);
      expect(run.choices, DriveLevel.values);

      expect(run.suggestion!.keys, isNotEmpty);
      controller.pickOwn((
        street: streets[route.edges.last.streetId]!,
        place: null,
        junction: null,
        at: null,
      ));
      final own = await settled();
      expect(own.chosen, DriveLevel.guided);
      expect(own.choices, [DriveLevel.guided, DriveLevel.coached]);
      controller.pickLevel(DriveLevel.off);
      expect(
        (container.read(driveControllerProvider) as DriveSetup).chosen,
        DriveLevel.guided,
      );
    },
  );

  test('Rescue at Off, while stopped: Guided from there, said once; the '
      'drive logs it, rescued, changing no card and at most Close', () async {
    final controller = runController();
    await controller.start(title: 't', text: 't');
    expect(
      (container.read(driveControllerProvider) as DriveRecording).level,
      DriveLevel.off,
    );
    controller.rescue();
    final rescued = container.read(driveControllerProvider) as DriveRecording;
    expect(rescued.level, DriveLevel.guided);
    expect(rescued.rescued, isTrue);
    expect(device.said, ['Guiding you from here.']);
    expect(device.screenOn, isTrue);
    await location.drive(route, now);
    await controller.end();
    final review = container.read(driveControllerProvider) as DriveReview;
    expect(review.tier!.index, greaterThanOrEqualTo(Tier.close.index));
    expect(await db.select(db.implicitEvidence).get(), isEmpty);
    final drive = (await container.read(driveLogDaoProvider).all()).single;
    expect(drive.rescued, isTrue);
    expect(drive.level, DriveLevel.off);
    expect(device.screenOn, isFalse);
  });

  test('a Guided drive speaks its turns, logs them as guided and changes no '
      'card', () async {
    final controller = runController();
    controller.pickLevel(DriveLevel.guided);
    await controller.start(title: 't', text: 't');
    expect(device.screenOn, isTrue);
    await location.drive(route, now);
    await controller.end();
    expect(device.said, isNotEmpty);
    expect(await db.select(db.implicitEvidence).get(), isEmpty);
    final drive = (await container.read(driveLogDaoProvider).all()).single;
    expect(drive.level, DriveLevel.guided);
    final decisions = await db.select(db.driveDecisions).get();
    expect(decisions, isNotEmpty);
    expect(decisions.every((d) => d.help == NavHelp.guided), isTrue);
  });

  test('a drive logs what it said, the screens it showed, the names heard and '
      'shown once each, and touches while moving only', () async {
    final controller = runController();
    controller.pickLevel(DriveLevel.guided);
    await controller.start(title: 't', text: 't');
    // Before the first fix the car counts as stopped: no touch logged.
    controller.noteTouch();
    var updates = 0;
    container.listen(driveControllerProvider, (_, s) {
      if (s is DriveRecording && ++updates == 20) controller.noteTouch();
    });
    final last = await location.drive(route, now);
    await location.park(route.lines.last.last, last, 4);
    await controller.end();
    final dao = container.read(driveLogDaoProvider);
    final id = (await dao.all()).single.id;
    final prompts = await dao.events(DriveEventKind.prompt);
    expect(prompts, isNotEmpty);
    expect(prompts.every((e) => e.driveId == id && e.value == 1), isTrue);
    expect(
      prompts.map((e) => e.detail).toSet(),
      containsAll([PromptKind.prepare.name, PromptKind.action.name]),
    );
    expect(
      prompts.where((e) => e.detail == PromptKind.action.name),
      everyElement(predicate<DriveEventRow>((e) => e.itemKey != null)),
    );
    final screens = [
      for (final e in await dao.events(DriveEventKind.screen)) e.detail,
    ];
    expect(screens.first, 'guided');
    expect(screens.last, 'guided stopped');
    final names = await dao.events(DriveEventKind.name);
    final shown = names.where((e) => e.detail == 'shown');
    expect(shown.map((e) => e.itemKey), contains(route.edges.last.streetId));
    expect(names.where((e) => e.detail == 'heard'), isNotEmpty);
    expect(
      names.map((e) => (e.itemKey, e.detail)).toSet(),
      hasLength(names.length),
    );
    final touches = await dao.events(DriveEventKind.touch);
    expect(touches.single.detail, 'guided');
    expect(touches.single.value, closeTo(8 * 3.6, 0.5));
  });

  test('muted, nothing is said', () async {
    final controller = runController();
    controller.pickLevel(DriveLevel.guided);
    await controller.start(title: 't', text: 't');
    controller.toggleMute();
    await location.drive(route, now);
    await controller.end();
    expect(device.said, isEmpty);
  });

  test('the log keeps every drive but drops tracks after '
      '${LearningConfig.driveTrackKeepDays} days, and never rewrites a '
      'drive', () async {
    final log = container.read(driveLogDaoProvider);
    DriveRow drive(String id, DateTime endedAt) => DriveRow(
      id: id,
      startedAt: endedAt,
      endedAt: endedAt,
      level: DriveLevel.off,
      goal: DriveTo.run.name,
      targetNode: 1,
      targetStreet: 's',
      outcome: DriveOutcome.arrived,
      drivenM: 100,
      credited: 0,
      failed: 0,
      fixes: 0,
      gpsGaps: 0,
      longestGapS: 0,
      recoveries: 0,
      rescued: false,
    );
    await log.save(drive('old', now), '');
    await log.save(drive('kept', now.add(const Duration(days: 1))), '');
    await log.save(
      drive(
        'new',
        now.add(const Duration(days: LearningConfig.driveTrackKeepDays + 1)),
      ),
      '',
    );
    expect(await log.all(), hasLength(3));
    expect(await log.track('old'), isNull);
    expect(await log.track('kept'), isEmpty);
    expect(
      () => db.customStatement("UPDATE drive SET goal = 'own'"),
      throwsA(anything),
    );
    expect(() => db.customStatement('DELETE FROM drive'), throwsA(anything));
  });

  test('a level picked while stopped applies at once; Quiet’s turns are '
      'the player’s own', () async {
    final controller = runController();
    await controller.start(title: 't', text: 't');
    controller.pickDriveLevel(DriveLevel.quiet);
    final quiet = container.read(driveControllerProvider) as DriveRecording;
    expect(quiet.level, DriveLevel.quiet);
    expect(device.screenOn, isTrue);
    await location.drive(route, now);
    await controller.end();
    final decisions = await db.select(db.driveDecisions).get();
    expect(decisions, isNotEmpty);
    expect(
      decisions.every(
        (d) => d.level == DriveLevel.quiet && d.help == NavHelp.none,
      ),
      isTrue,
    );
    final drive = (await container.read(driveLogDaoProvider).all()).single;
    expect(drive.level, DriveLevel.off, reason: 'the level it started at');
    expect(drive.mostHelp, DriveLevel.quiet);
  });

  test('turns taken on your own review their J cards Good near due; a '
      'Guided drive reviews none', () async {
    var controller = runController();
    await controller.start(title: 't', text: 't');
    var last = await location.drive(route, now);
    await controller.end();
    final keys = {
      for (final d in await db.select(db.driveDecisions).get()) ?d.itemKey,
    };
    expect(keys, isNotEmpty);
    // Cards for them, a stability ago: recall 0.9, near due.
    await container.read(learningDaoProvider).putCards([
      for (final key in keys)
        CardState(
          itemId: key,
          phase: CardPhase.review,
          memory: Memory(
            stability: 10,
            difficulty: 5,
            lastReview: now.subtract(const Duration(days: 10)),
          ),
          dueAt: now,
          reps: 3,
          lastRating: Rating.good,
          introAt: now.subtract(const Duration(days: 20)),
        ),
    ]);
    Future<List<ReviewLogRow>> reviews() => (db.select(
      db.reviewLogs,
    )..where((r) => r.source.equalsValue(ReviewSource.drive))).get();
    Rating rating(ReviewLogRow r) =>
        Rating.values.firstWhere((x) => x.grade == r.rating);

    container.invalidate(driveControllerProvider);
    controller = runController()..pickLevel(DriveLevel.guided);
    clockNow = last.add(const Duration(minutes: 5));
    await controller.start(title: 't', text: 't');
    last = await location.drive(route, clockNow);
    await controller.end();
    expect(await reviews(), isEmpty);

    container.invalidate(driveControllerProvider);
    controller = runController()..pickLevel(DriveLevel.quiet);
    clockNow = last.add(const Duration(minutes: 5));
    await settled();
    await controller.start(title: 't', text: 't');
    await location.drive(route, clockNow);
    await controller.end();
    final review = container.read(driveControllerProvider) as DriveReview;
    final rows = await reviews();
    expect(rows, isNotEmpty);
    expect(rows.every((r) => rating(r) == Rating.good), isTrue);
    expect(review.credited, rows.length);
    final logged = await db.select(db.driveDecisions).get();
    expect(logged.where((d) => d.keyTurn), isNotEmpty);
    expect(logged.where((d) => d.effect == 'good'), hasLength(rows.length));
    expect(logged.where((d) => d.effect == 'helped'), isNotEmpty);
  });

  Future<void> pumpDrive(
    WidgetTester tester, {
    String at = Routes.driveRun,
  }) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp.router(
          theme: buildPindoroTheme(Brightness.light),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          routerConfig: GoRouter(
            initialLocation: at,
            routes: [
              GoRoute(
                path: Routes.driveTab,
                builder: (_, _) => const DriveTab(),
              ),
              GoRoute(
                path: Routes.drive,
                builder: (_, state) => DriveScreen.route(state),
              ),
              GoRoute(
                path: Routes.drivePreview,
                builder: (_, _) => const DrivePreviewScreen(),
              ),
              GoRoute(
                path: Routes.driveMap,
                builder: (_, _) => const DriveMapScreen(),
              ),
              GoRoute(
                path: Routes.pastDrives,
                builder: (_, state) =>
                    PastDrivesScreen(route: state.uri.queryParameters['route']),
              ),
            ],
          ),
        ),
      ),
    );
    await settle(tester);
  }

  // The drive screens tick every second, so they never settle.
  Future<void> pumpUntil(WidgetTester tester, Finder target) async {
    for (var i = 0; i < 40 && target.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The setup once its route is found: the level picker marks the suggested level.
  final suggested = find.byWidgetPredicate(
    (w) => w is LevelPicker<DriveLevel> && w.suggested != null,
  );

  /// Pulls the setup's sheet up: the suggestion, the level note, the rules and the week.
  Future<void> showMore(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Show more'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a Guided drive\'s result says the voice led the way, not that it was found '
    'without GPS',
    (tester) async {
      await pumpDrive(tester);
      await tester.tap(find.text('Guided'));
      await tester.pump();
      await tester.tap(find.text("Let's go"));
      await pumpUntil(tester, find.byType(StoppedBar));
      final last = await tester.runAsync(() => location.drive(route, now));
      await tester.runAsync(
        () => location.park(route.lines.last.last, last!, 3),
      );
      await pumpUntil(tester, find.text('Later'));
      await tester.tap(find.text('Go through your drive'));
      await tester.pump();
      for (var i = 0; i < 20 && find.text('Next').evaluate().isEmpty; i++) {
        for (final label in [
          'I don’t remember',
          'Show me',
          'Next turn',
          'See the whole drive',
        ]) {
          if (find.text(label).evaluate().isNotEmpty) {
            await tester.tap(find.text(label));
            await tester.pump();
          }
        }
        await pumpUntil(tester, find.text('Next'));
      }
      await tester.tap(find.text('Next'));
      await tester.pump();
      await settle(tester);
      expect(
        find.textContaining('The voice led you all the way.'),
        findsOneWidget,
      );
      expect(find.textContaining('without GPS'), findsNothing);
    },
  );

  testWidgets('the screens: setup with today\'s run at Off, the black '
      'recording screen, then the debrief: each turn recalled, then shown, '
      'the marks, the tier and the streets', (tester) async {
    await SettingsDao(db).setDrivePlace(
      encodeDrivePlace((
        node: homeNode,
        street: route.edges.first.streetId!,
        place: null,
        at: null,
      )),
      home: true,
    );
    await pumpDrive(tester);
    expect(find.byType(PlanMapLayout), findsOneWidget);
    expect(find.textContaining(' → '), findsOneWidget);
    expect(find.textContaining('starts at Off'), findsNothing, reason: 'short');
    await showMore(tester);
    expect(find.textContaining('starts at Off'), findsOneWidget);
    expect(find.byType(LevelPicker<DriveLevel>), findsOneWidget);
    await tester.tap(find.text("Let's go"));
    await pumpUntil(tester, find.byType(RecordingDot));
    expect(find.bySemanticsLabel('Recording your drive'), findsOneWidget);
    final last = await tester.runAsync(() => location.drive(route, now));
    // Past the bar's exit: it showed while parked before the first fix.
    await tester.pump();
    await tester.pump(PindoroMotion.durationSlow);
    // Moving: no controls. Stopped at the destination, the drive ends by itself.
    expect(find.byType(StoppedBar), findsNothing);
    expect(maps, isEmpty, reason: 'Off shows no map');
    await tester.runAsync(() => location.park(route.lines.last.last, last!, 3));
    await pumpUntil(tester, find.text('Later'));
    final to = streets[route.edges.last.streetId]!.name;
    expect(find.text('You’re at $to'), findsOneWidget);
    await tester.tap(find.text('Go through your drive'));
    await tester.pump();
    final forgot = find.text('I don’t remember');
    final show = find.text('Show me');
    var recalled = 0;
    while (forgot.evaluate().isNotEmpty || show.evaluate().isNotEmpty) {
      await tester.tap(forgot.evaluate().isNotEmpty ? forgot : show);
      await tester.pump();
      recalled++;
      expect(find.byType(ReviewMark), findsOneWidget);
      final next = find.text('Next turn');
      await tester.tap(
        next.evaluate().isNotEmpty ? next : find.text('See the whole drive'),
      );
      await tester.pump();
    }
    await pumpUntil(tester, find.text('Yellow is the way, blue is yours'));
    expect(recalled, greaterThan(0));
    final dao = DriveLogDao(db);
    final recalls = await tester.runAsync(
      () => dao.events(DriveEventKind.recall),
    );
    expect(recalls, hasLength(recalled));
    expect(recalls!.every((e) => e.value == null), isTrue);
    expect(
      await tester.runAsync(() => dao.events(DriveEventKind.debrief)),
      hasLength(1),
    );
    await tester.tap(find.text('Next'));
    await tester.pump();
    await settle(tester);
    expect(find.text('Perfect!'), findsOneWidget);
    expect(find.textContaining('You found it without GPS.'), findsOneWidget);
    await tester.tap(find.text('Next: streets you drove'));
    await tester.pump();
    expect(find.text('Streets you drove'), findsOneWidget);
    // A new destination: once, Point to home with the phone's compass.
    await tester.tap(find.text('Next: point to home'));
    await tester.pump();
    expect(find.text('Point to home'), findsOneWidget);
    compass.add((homeBearing + 8) % 360);
    await tester.pump();
    await tester.tap(find.text('Point here'));
    await tester.pump();
    expect(find.byType(DialResultChip), findsOneWidget);
    expect(find.text('Perfect! · 8° off'), findsOneWidget);
    final pointed = await tester.runAsync(
      () => dao.events(DriveEventKind.point),
    );
    expect(pointed!.single.value, closeTo(8, 0.5));
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('Guided: the map and the turn card while moving, no buttons; '
      'stopped, End drive, the rest at a touch, and a level picked there '
      'applies at once', (tester) async {
    await pumpDrive(tester);
    await tester.ensureVisible(find.text('Guided'));
    await tester.pump();
    await tester.tap(find.text('Guided'));
    await tester.pump();
    await tester.tap(find.text("Let's go"));
    await pumpUntil(tester, find.byType(TurnPlate));
    // The first stretch of the run, then a stop short of the destination.
    final first = Route(route.junctions.take(2).toList(), [
      route.edges.first,
    ], route.edges.first.lengthM);
    final reached = await tester.runAsync(() => location.drive(first, now));
    await tester.pump();
    // On down the plan's first road.
    final plan =
        (ProviderScope.containerOf(
                  tester.element(find.byType(DriveRecordingView)),
                ).read(driveControllerProvider)
                as DriveRecording)
            .view!
            .plan!;
    final onPlan = Route(plan.route.junctions.take(2).toList(), [
      plan.route.edges.first,
    ], plan.route.edges.first.lengthM);
    final last = await tester.runAsync(
      () => location.drive(onPlan, reached!.add(const Duration(seconds: 1))),
    );
    await tester.pump();
    await tester.pump(PindoroMotion.durationSlow);
    expect(maps.last.route, isNotEmpty);
    expect(maps.last.at, isNotNull);
    expect(
      distanceBetween(maps.last.route.first.first, maps.last.at!),
      lessThan(1),
      reason: 'the route starts at the car: the road driven is gone',
    );
    expect(find.byType(TurnPlate), findsOneWidget);
    // The next turn's card: its arrow beside the distance, and the arrow on the map.
    final card = tester.widget<TurnPlate>(find.byType(TurnPlate));
    expect(card.glyph, isNotNull);
    expect(card.headline, matches(RegExp(r'^\d')));
    expect(maps.last.turn, isNotEmpty);
    // Moving: the bar's numbers, no buttons over the map (item 130).
    expect(find.bySemanticsLabel('North up'), findsNothing);
    expect(find.bySemanticsLabel('Routes'), findsNothing);
    expect(find.byType(DriveBarButton), findsNothing);
    expect(find.byType(SpeedNow), findsOneWidget);
    await tester.runAsync(
      () => location.park(onPlan.lines.last.last, last!, 3),
    );
    await pumpUntil(tester, find.bySemanticsLabel('End drive'));
    // Stopped: End drive at the bar's end; the other buttons at a touch.
    expect(find.byType(DriveBarButton), findsOneWidget);
    expect(find.bySemanticsLabel('Mute the voice'), findsNothing);
    await tester.tapAt(tester.getCenter(find.byType(DriveRecordingView)));
    await tester.pump();
    await tester.pump(PindoroMotion.durationBase);
    await tester.tap(find.bySemanticsLabel('Mute the voice'));
    await tester.pump();
    expect(find.bySemanticsLabel('Unmute the voice'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Level: Guided. Change.'));
    await tester.pump();
    expect(find.text('Level for the rest of this drive'), findsOneWidget);
    await tester.tap(find.text('Quiet'));
    await pumpUntil(tester, find.byType(HeadingDial));
    expect(find.byType(HeadingDial), findsOneWidget);
    // The district in the street names' script (Georgian here), the voice's English aside.
    final district = raionAt(districts, onPlan.lines.last.last);
    expect(district, isNotNull);
    expect(
      tester.widget<DistrictLine>(find.byType(DistrictLine)).name,
      district!.nameKa,
    );
    await tester.tap(find.text('End drive'));
    // Stopped short of the destination: the debrief, on its offer or (with
    // no turn to go through) the tier.
    final debrief = find.byWidgetPredicate(
      (w) => (w is Text && w.data == 'Drive done') || w is RevealSheet,
    );
    await pumpUntil(tester, debrief);
    expect(debrief, findsOneWidget);
  });

  testWidgets('Guided: the map moves at any speed, Recentre or 10 s bring it '
      'back to the car, the compass turns it north up; back can\'t end the '
      'drive; the routes overview, and its search for a new destination stays '
      'open while moving (a passenger picks)', (tester) async {
    await pumpDrive(tester);
    await tester.ensureVisible(find.text('Guided'));
    await tester.pump();
    await tester.tap(find.text('Guided'));
    await tester.pump();
    await tester.tap(find.text("Let's go"));
    await pumpUntil(tester, find.byType(DriveRecordingView));
    final scope = tester.widget<PopScope>(
      find.descendant(
        of: find.byType(DriveRecordingView),
        matching: find.byWidgetPredicate((w) => w is PopScope),
      ),
    );
    expect(scope.canPop, isFalse, reason: 'back would throw the drive away');
    expect(maps.last.at, isNotNull, reason: 'opens where the phone is');
    expect(
      maps.last.route,
      isNotEmpty,
      reason: 'the route picked at setup, before the first fix',
    );

    final first = Route(route.junctions.take(2).toList(), [
      route.edges.first,
    ], route.edges.first.lengthM);
    final last = await tester.runAsync(() => location.drive(first, now));
    await tester.pump();
    await tester.pump(PindoroMotion.durationSlow);
    final street = streets[route.edges.first.streetId]!;
    expect(
      find.bySemanticsLabel('On ${street.name}'),
      findsOneWidget,
      reason: 'the street driven, above the bar',
    );
    final recentre = find.bySemanticsLabel('Recentre');
    final northUp = find.bySemanticsLabel('North up');
    expect(northUp, findsNothing, reason: 'no buttons while driving');
    expect(maps.last.follow, isTrue);
    expect(
      maps.last.places,
      isNotNull,
      reason: 'following, only the places near the route',
    );
    // A drag: the map stays put, and Recentre pops in where the compass goes.
    maps.last.onMoved!();
    await tester.pump();
    await tester.pump(PindoroMotion.durationBase);
    expect(maps.last.follow, isFalse);
    expect(northUp, findsNothing);
    await tester.tap(recentre);
    await tester.pump();
    await tester.pump(PindoroMotion.durationBase);
    expect(maps.last.follow, isTrue, reason: 'Recentre works while moving');
    expect(recentre, findsNothing);
    // On the car, the compass: north up, then the road ahead up again.
    await tester.tap(northUp);
    await tester.pump();
    expect(maps.last.northUp, isTrue);
    await tester.tap(find.bySemanticsLabel('Heading up'));
    await tester.pump();
    expect(maps.last.northUp, isFalse);
    // 10 s after the last touch the buttons go and the map is back on the car.
    maps.last.onMoved!();
    await tester.pump(const Duration(seconds: 9));
    expect(maps.last.follow, isFalse);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(PindoroMotion.durationBase);
    expect(maps.last.follow, isTrue, reason: 'back on the car after 10 s');
    expect(
      find.bySemanticsLabel('Routes').hitTestable(),
      findsNothing,
      reason: 'the buttons go too',
    );

    await tester.runAsync(() => location.park(first.lines.last.last, last!, 3));
    await pumpUntil(tester, find.bySemanticsLabel('End drive'));
    await tester.tapAt(tester.getCenter(find.byType(DriveRecordingView)));
    await tester.pump();
    await tester.pump(PindoroMotion.durationBase);
    await tester.tap(find.bySemanticsLabel('Routes'));
    await tester.pump();
    expect(maps.last.overview, isTrue);
    expect(maps.last.follow, isFalse);
    expect(find.text('Now'), findsOneWidget, reason: 'the route driven now');
    await tester.tap(find.bySemanticsLabel(RegExp('^To ')));
    await tester.pump();
    await tester.pump(PindoroMotion.durationSlow);
    expect(find.byType(RoutePlaceScreen), findsOneWidget);
    // Driving off: every fix and prompt is a state change; the search stays.
    await tester.runAsync(
      () => location.drive(first, last!.add(const Duration(seconds: 10))),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(RoutePlaceScreen), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(PindoroMotion.durationSlow);
    expect(find.byType(RoutePlaceScreen), findsNothing);
    expect(find.byType(DriveRecordingView), findsOneWidget);

    // A new destination picked after the overview closed behind the search (10 s after the
    // last touch) still takes.
    await tester.tap(find.bySemanticsLabel(RegExp('^To ')));
    await tester.pump();
    await tester.pump(PindoroMotion.durationSlow);
    await tester.pump(const Duration(seconds: 11));
    expect(
      find.text('Now', skipOffstage: false),
      findsNothing,
      reason: 'the overview closed under the search',
    );
    final drive = ProviderScope.containerOf(
      tester.element(find.byType(DriveRecordingView, skipOffstage: false)),
    );
    final newEnd = route.junctions[1];
    await tester.runAsync(() async {
      tester
          .element(find.byType(RoutePlaceScreen))
          .findAncestorStateOfType<NavigatorState>()!
          .pop((
            street: streets[route.edges.first.streetId],
            place: null,
            junction: newEnd,
            at: null,
          ));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    final recording = drive.read(driveControllerProvider) as DriveRecording;
    expect(recording.target.junction, newEnd);
  });

  testWidgets('Coached while moving: a touch shows Route, which opens the '
      'route with Add stop', (tester) async {
    await pumpDrive(tester);
    await tester.ensureVisible(find.text('Coached'));
    await tester.pump();
    await tester.tap(find.text('Coached'));
    await tester.pump();
    await tester.tap(find.text("Let's go"));
    await pumpUntil(tester, find.byType(DriveRecordingView));
    final first = Route(route.junctions.take(2).toList(), [
      route.edges.first,
    ], route.edges.first.lengthM);
    await tester.runAsync(() => location.drive(first, now));
    await tester.pump();
    final button = find.bySemanticsLabel('Route and destination');
    expect(button.hitTestable(), findsNothing, reason: 'none until a touch');
    await tester.tapAt(tester.getCenter(find.byType(DriveRecordingView)));
    await tester.pump();
    await tester.pump(PindoroMotion.durationBase);
    await tester.tap(button);
    await tester.pump();
    await tester.pump(PindoroMotion.durationSlow);
    expect(find.byType(DriveRouteScreen), findsOneWidget);
    expect(find.text('Add stop'), findsOneWidget);
  });

  testWidgets('the Drive tab: Home and Work to set, today’s run, Surprise '
      'me; a street found by name opens the drive on it', (tester) async {
    await pumpDrive(tester, at: Routes.driveTab);
    expect(find.text('Set your home'), findsOneWidget);
    expect(find.text('Set your work'), findsOneWidget);
    expect(find.text("Today's run"), findsOneWidget);
    expect(find.text('Surprise me'), findsOneWidget);
    final street = streets[route.edges.last.streetId]!;
    await tester.enterText(find.byType(TextField), street.name);
    final result = find.descendant(
      of: find.byType(ListRow),
      matching: find.text(street.name),
    );
    await pumpUntil(tester, result);
    expect(find.text('Set your home'), findsNothing, reason: 'only results');
    await tester.tap(result.first);
    await pumpUntil(tester, suggested);
    expect(find.byType(LevelPicker<DriveLevel>), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^To ')), findsOneWidget);
  });

  testWidgets('the Drive tab: Home set shows the minutes there, and one tap '
      'sets the drive up on Home', (tester) async {
    await SettingsDao(db).setDrivePlace(
      encodeDrivePlace((
        node: endNode,
        street: route.edges.last.streetId!,
        place: null,
        at: null,
      )),
      home: true,
    );
    await pumpDrive(tester, at: Routes.driveTab);
    final minutes = find.descendant(
      of: find.byType(StatTile),
      matching: find.textContaining(RegExp(r'^\d+ min$')),
    );
    await pumpUntil(tester, minutes);
    expect(minutes, findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(StatTile),
        matching: find.text(streets[route.edges.last.streetId]!.name),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Home'));
    await pumpUntil(tester, suggested);
    expect(find.byType(LevelPicker<DriveLevel>), findsOneWidget);
    expect(find.text("Let's go"), findsOneWidget);
  });

  testWidgets('Surprise me with no turns known yet says why there is no '
      'surprise', (tester) async {
    await pumpDrive(tester, at: Routes.driveTo('surprise'));
    await pumpUntil(tester, find.text('No surprise yet'));
    expect(find.text('No surprise yet'), findsOneWidget);
    expect(find.textContaining('7 of every 10 turns'), findsOneWidget);
    expect(find.text("Let's go"), findsOneWidget);
  });

  test('a spot beside a two-way road: the drive offers either side, the right '
      'first; the left picked is driven to, and the spot is logged and comes back '
      'as recent', () async {
    container.listen(driveControllerProvider, (_, _) {});
    final controller = container.read(driveControllerProvider.notifier)
      ..pickOwn((street: null, place: null, junction: null, at: beside));
    final setup = await settled();
    expect(setup.target!.at, beside);
    final sides = [for (final o in setup.options) o.plan.stop?.side];
    expect(sides.first, NavSide.right);
    expect(sides, contains(NavSide.left));
    expect(setup.suggestion!.plan.stop!.side, NavSide.right);
    controller.pickRoute(
      setup.options.firstWhere((o) => o.plan.stop?.side == NavSide.left),
    );
    await controller.start(title: 't', text: 't');
    final recording = container.read(driveControllerProvider) as DriveRecording;
    expect(recording.suggestion!.plan.stop!.side, NavSide.left);
    expect(recording.destination, beside);
    await controller.end();
    final drive = (await container.read(driveLogDaoProvider).all()).single;
    expect((drive.targetLat, drive.targetLon), (beside.lat, beside.lon));
    final recent = await container.read(recentDestinationsProvider.future);
    expect(recent.single.at, beside);
  });

  test('a stop on the way: added at setup, every route goes through it; on the '
      'drive it is said as reached, the drive goes on to its end and is '
      'graded from the stop', () async {
    final controller = runController();
    await settled();
    controller.pickLevel(DriveLevel.guided);
    final k = [
      for (var i = 1; i < route.edges.length - 1; i++)
        if (route.edges[i].streetId != null) i,
    ][1];
    final stop = route.junctions[k];
    await controller.addStop((
      street: streets[route.edges[k].streetId],
      place: null,
      junction: stop,
      at: null,
    ));
    final setup = await settled();
    expect(setup.via.single.junction, stop);
    expect(setup.options, isNotEmpty);
    for (final o in setup.options) {
      expect(o.plan.route.junctions, contains(stop));
      expect(o.plan.via, hasLength(1));
    }
    await controller.start(title: 't', text: 't');
    expect(
      (container.read(driveControllerProvider) as DriveRecording).via,
      hasLength(1),
    );
    final last = await location.drive(route, now);
    expect(
      device.said.where((s) => s.startsWith("You've reached your stop")),
      hasLength(1),
    );
    expect(
      (container.read(driveControllerProvider) as DriveRecording).via,
      isEmpty,
    );
    await location.park(route.lines.last.last, last, 3);
    for (var i = 0; i < 50; i++) {
      if (container.read(driveControllerProvider) is DriveReview) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final review = container.read(driveControllerProvider) as DriveReview;
    expect(review.stoppedM, isNull, reason: 'arrived after the stop');
    final drive = (await container.read(driveLogDaoProvider).all()).single;
    expect(drive.gradedFrom, greaterThan(0));
  });

  test('while moving: a stop added and the destination changed take at once, '
      'the stop kept', () async {
    final controller = runController();
    await settled();
    await controller.start(title: 't', text: 't');
    final first = Route(route.junctions.take(2).toList(), [
      route.edges.first,
    ], route.edges.first.lengthM);
    await location.drive(first, now);
    final moving = container.read(driveControllerProvider) as DriveRecording;
    expect(moving.stopped, isFalse);
    final street = streets[route.edges.last.streetId]!;
    await controller.addStop((
      street: street,
      place: null,
      junction: null,
      at: null,
    ));
    expect(
      (container.read(driveControllerProvider) as DriveRecording).via,
      hasLength(1),
    );
    await controller.changeDestination((
      street: null,
      place: null,
      junction: null,
      at: beside,
    ));
    final changed = container.read(driveControllerProvider) as DriveRecording;
    expect(changed.target.at, beside);
    expect(changed.via.single.street, street);
    expect(
      changed.suggestion,
      allOf(isNotNull, isNot(moving.suggestion)),
      reason: 'the new route, its key turns logged as such',
    );
  });

  test('Home or Work keeps its spot; one set before spots has none', () {
    const home = (
      node: 1,
      street: 's',
      place: 'osm:n1',
      at: LatLng(41.7, 44.77),
    );
    expect(decodeDrivePlace(encodeDrivePlace(home)), home);
    expect(decodeDrivePlace('{"node":1,"street":"s"}')?.at, isNull);
  });

  testWidgets('choose on the map: every place shows; a tap anywhere drops the '
      'pin right there, and Drive here offers either side of its road', (
    tester,
  ) async {
    await pumpDrive(tester, at: Routes.driveTab);
    await tester.tap(find.text('Choose on the map'));
    await settle(tester);
    expect(plans.last.names, MapNames.everything);
    expect(find.text('Tap the map where you’re going.'), findsOneWidget);
    final drive = find.text('Drive here');
    PindoroButton button() => tester.widget<PindoroButton>(
      find.ancestor(of: drive, matching: find.byType(PindoroButton)),
    );
    expect(button().onPressed, isNull, reason: 'nothing picked yet');
    plans.last.onTap!(beside);
    await tester.pump();
    expect(plans.last.pin, beside, reason: 'the pin stays where tapped');
    expect(find.text('Dropped pin'), findsOneWidget);
    expect(button().onPressed, isNotNull);
    await tester.tap(drive);
    await pumpUntil(tester, find.textContaining('On your left'));
    expect(find.textContaining('On your right'), findsWidgets);
    expect(
      distanceBetween(plans.last.route!.best.last.last, beside),
      closeTo(20, 5),
      reason: 'the route ends on the road beside the spot',
    );
  });

  testWidgets('choose on the map: a place tapped is picked, lit, with its '
      'kind, address, hours, Call and Website, and Drive here goes there', (
    tester,
  ) async {
    final poi = Poi(
      id: 'osm:n9001',
      osmKey: 'amenity',
      kind: 'restaurant',
      nameKa: 'Test Kitchen',
      nameEn: null,
      brand: null,
      at: beside,
      outline: [
        [
          [beside, beside, beside, beside],
        ],
      ],
      street: 'Test Street',
      housenumber: '12',
      hours: 'Mo-Su 10:00-22:00',
      phone: '+995 32 200 00 00',
      website: 'kitchen.example',
    );
    overrides.add(
      packPlacesProvider.overrideWith((ref) async {
        final pack = await ref.watch(packRepositoryProvider.future);
        return {for (final l in pack.landmarks()) l.id: l, poi.id: poi};
      }),
    );
    await pumpDrive(tester, at: Routes.driveTab);
    await tester.tap(find.text('Choose on the map'));
    await settle(tester);
    plans.last.onPlaceTap!((
      id: poi.id,
      name: poi.nameKa,
      kind: poi.kind,
      at: poi.at,
    ));
    await tester.pump();
    expect(plans.last.pin, poi.at);
    expect(plans.last.placeOutline, poi.outline);
    expect(find.text('Test Kitchen'), findsOneWidget);
    expect(find.textContaining('Restaurant'), findsOneWidget);
    expect(find.text('Test Street 12'), findsOneWidget);
    expect(find.text('Mo-Su 10:00-22:00'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Website'), findsOneWidget);
    // A place tapped on the tiles only, named as a pack place close by, is that place.
    plans.last.onPlaceTap!((
      id: null,
      name: landmark.nameKa,
      kind: 'other',
      at: landmark.at,
    ));
    await tester.pump();
    expect(find.text('Call'), findsNothing);
    plans.last.onPlaceTap!((
      id: poi.id,
      name: poi.nameKa,
      kind: poi.kind,
      at: poi.at,
    ));
    await tester.pump();
    await tester.tap(find.text('Drive here'));
    await pumpUntil(tester, suggested);
    expect(find.text('Test Kitchen'), findsWidgets);
  });

  testWidgets('the Drive tab’s drives: the one waiting to be gone through, '
      'the week’s goal, the two drives to pick and Past drives', (
    tester,
  ) async {
    final pack = SqlitePackRepository.open(AppConfig.fixturePackAsset);
    final nodes = pack.junctionNodes().values.toList();
    final street = pack.roadGraph()!.edges.first.streetId!;
    pack.close();
    final log = DriveLogDao(db);
    for (var i = 0; i < 3; i++) {
      final at = now.subtract(Duration(hours: 3 - i));
      await log.save(
        DriveRow(
          id: 'd$i',
          startedAt: at.subtract(const Duration(minutes: 20)),
          endedAt: at,
          level: DriveLevel.quiet,
          goal: 'own',
          startNode: nodes.first,
          targetNode: nodes.last,
          targetStreet: street,
          outcome: DriveOutcome.arrived,
          drivenM: 2000,
          credited: 0,
          failed: 0,
          fixes: 0,
          gpsGaps: 0,
          longestGapS: 0,
          recoveries: 0,
          rescued: false,
          mostHelp: DriveLevel.quiet,
        ),
        '',
        decisions: [
          DriveDecisionRow(
            driveId: 'd$i',
            seq: 0,
            at: at,
            itemKey: 'J:n1:n2:n3',
            planned: true,
            ok: true,
            level: DriveLevel.quiet,
            help: NavHelp.none,
            recentHelp: false,
            hesitated: false,
            keyTurn: true,
          ),
        ],
      );
    }
    await pumpDrive(tester, at: Routes.driveTab);
    await pumpUntil(tester, find.text('Pick your two drives'));
    expect(find.text('Drives'), findsOneWidget);
    expect(find.text('Your drive is waiting'), findsOneWidget);
    expect(find.text('This week’s goal is done.'), findsOneWidget);
    expect(find.text('Past drives'), findsOneWidget);
    expect(find.text('3 drives'), findsOneWidget);
    await tester.ensureVisible(find.text('Not this week'));
    await tester.pump();
    await tapThrough(tester, find.text('Not this week'));
    expect(find.text('Pick your two drives'), findsNothing);
  });

  testWidgets('the setup offers the routes there over its map: the fastest '
      'picked in yellow, the others grey; another picked takes the yellow', (
    tester,
  ) async {
    await pumpDrive(tester);
    await pumpUntil(tester, find.text('Fastest'));
    expect(plans.last.traces, isNotEmpty, reason: 'the other routes');
    final fastest = plans.last.route!.best;
    final other = find
        .descendant(
          of: find.byType(RouteCards),
          matching: find.textContaining(RegExp(r'^\d+ min$')),
        )
        .at(1);
    await tester.ensureVisible(other);
    await tester.pump();
    await tester.tap(other);
    await tester.pump();
    expect(plans.last.route!.best, isNot(equals(fastest)));
    // The sheet opens short; pulled up, the rest; pulled down, short again.
    expect(find.byType(LevelSuggestion), findsNothing);
    expect(find.byType(DriveWeekCard), findsNothing);
    await showMore(tester);
    expect(find.byType(LevelSuggestion), findsOneWidget);
    expect(find.byType(DriveWeekCard), findsOneWidget);
    await tester.drag(find.bySemanticsLabel('Show less'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.byType(LevelSuggestion), findsNothing);
  });

  testWidgets(
    'the setup plans from the last known fix at once, then again from a fresh '
    'one that lies more than 50 m away',
    (tester) async {
      // The fresh fix: a few junctions along the drive's route.
      final along = route.lines[route.lines.length ~/ 2].first;
      location.fresh = along;
      await pumpDrive(tester);
      await pumpUntil(tester, find.text('Fastest'));
      for (var i = 0; i < 20; i++) {
        final start = plans.last.route?.best.firstOrNull?.firstOrNull;
        if (start != null && distanceBetween(start, along) < 60) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        distanceBetween(plans.last.route!.best.first.first, along),
        lessThan(60),
      );
    },
  );

  testWidgets('approximate location: the setup says so, and a tap asks for '
      'precise', (tester) async {
    location.approximate = true;
    await pumpDrive(tester);
    final off = find.text('Precise location is off');
    await pumpUntil(tester, off);
    await tester.ensureVisible(off);
    await tester.pump();
    await tester.tap(off);
    for (var i = 0; i < 10 && off.evaluate().isNotEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(location.askedPrecise, 1);
    expect(off, findsNothing);
  });

  testWidgets('the preview: the route, then every turn stepped through '
      'heading-up with its arrow, with Back and Next, then Recite: a way '
      'tapped at each, right or wrong at once, cards untouched', (
    tester,
  ) async {
    await pumpDrive(tester);
    await pumpUntil(tester, suggested);
    await tester.tap(find.text('Preview'));
    await pumpUntil(tester, find.text('Your route'));
    // North-up, the route in yellow with no track yet.
    expect(plans.last.route!.best, isNotEmpty);
    expect(plans.last.route!.track, isEmpty);
    expect(plans.last.bearing, 0);
    final setup =
        ProviderScope.containerOf(
              tester.element(find.byType(DrivePreviewScreen)),
            ).read(driveControllerProvider)
            as DriveSetup;
    final plan = setup.suggestion!.plan;
    final turns = plan.decisions.length;
    await tester.tap(find.text('Show the turns'));
    await tester.pump();
    expect(find.text('Turn 1 of $turns'), findsOneWidget, reason: 'every turn');
    expect(plans.last.bearing, turnBearing(plan, plan.decisions.first));
    expect(plans.last.route!.turn, isNotEmpty);
    await tester.tap(find.text('Back'));
    await tester.pump();
    expect(find.text('Show the turns'), findsOneWidget, reason: 'the route');
    expect(plans.last.bearing, 0);
    expect(plans.last.route!.turn, isEmpty);
    await tester.tap(find.text('Show the turns'));
    await tester.pump();
    for (var i = 0; i < turns; i++) {
      expect(find.text('Turn ${i + 1} of $turns'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pump();
    }
    expect(find.text('Recite the turns'), findsOneWidget);
    final dao = DriveLogDao(db);
    expect(
      await tester.runAsync(() => dao.events(DriveEventKind.preview)),
      hasLength(1),
    );
    await tester.tap(find.text('Recite the turns'));
    await tester.pump();
    expect(
      plans.last.names.streets,
      isEmpty,
      reason: 'a street name on the map would give the way away',
    );
    expect(plans.last.route!.turn, isEmpty, reason: 'so would the arrow');
    await tester.tap(find.byType(ExitButton).first);
    await tester.pump();
    expect(find.byType(RevealSheet), findsOneWidget);
    expect(plans.last.names, MapNames.all);
    expect(plans.last.route!.turn, isNotEmpty);
    final recited = await tester.runAsync(
      () => dao.events(DriveEventKind.recite),
    );
    expect(recited, hasLength(1));
    expect(recited!.single.value, anyOf(0, 1));
    expect(
      await tester.runAsync(() => LearningDao(db).log()),
      isEmpty,
      reason: 'reciting reviews no card',
    );
  });

  testWidgets('Past drives by week: the route, the level, the turns on your '
      'own and the tier', (tester) async {
    await tester.runAsync(() async {
      final controller = runController();
      await controller.start(title: 't', text: 't');
      await location.drive(route, now);
      await controller.end();
    });
    await pumpDrive(tester, at: Routes.pastDrives);
    await pumpUntil(tester, find.text('This week'));
    expect(find.text('This week'), findsOneWidget);
    expect(find.byType(TierChip), findsOneWidget);
    expect(find.textContaining('on your own'), findsOneWidget);
    expect(find.textContaining('Off'), findsWidgets);
  });
}

/// A location service that is at [here] and plays a drive as fixes once a
/// second at 8 m/s, with the device's heading and speed.
/// 20 m to the right of [e]'s middle, driving from its `from` end.
LatLng _beside(RoadEdge e) {
  final n = e.line.length ~/ 2;
  final a = e.line[n - 1 < 0 ? 0 : n - 1], b = e.line[n];
  final mid = LatLng((a.lat + b.lat) / 2, (a.lon + b.lon) / 2);
  final right = (bearingDegrees(a, b) + 90) * pi / 180;
  return LocalProjection(mid).unproject((20 * sin(right), 20 * cos(right)));
}

class _Track extends LocationService {
  _Track(this.here);

  final LatLng here;
  var _fixes = StreamController<DriveFix>();
  (String, String)? notice;
  bool cancelled = false;

  /// How many fixes [drive] sent.
  int sent = 0;

  /// Approximate location until asked for precise.
  bool approximate = false;
  int askedPrecise = 0;

  /// What a fresh fix finds; none by default.
  LatLng? fresh;

  @override
  Future<LocationResult> locate({bool ask = true}) async => Located(here);

  @override
  Future<LatLng?> freshFix() async => fresh;

  @override
  Future<bool> precise() async => !approximate;

  @override
  Future<void> askPrecise() async {
    askedPrecise++;
    approximate = false;
  }

  @override
  Stream<DriveFix> track({required String title, required String text}) {
    notice = (title, text);
    _fixes = StreamController<DriveFix>();
    _fixes.onCancel = () => cancelled = true;
    return _fixes.stream;
  }

  /// Plays [route] from [start] and returns the last fix's time.
  Future<DateTime> drive(Route route, DateTime start) async {
    const mps = 8.0;
    var t = start;
    var carry = 0.0;
    for (final line in route.lines) {
      for (var i = 0; i + 1 < line.length; i++) {
        final a = line[i], b = line[i + 1];
        final length = distanceBetween(a, b);
        final heading = bearingDegrees(a, b);
        for (var d = carry; d < length; d += mps) {
          final f = d / length;
          _fixes.add((
            at: LatLng(
              a.lat + (b.lat - a.lat) * f,
              a.lon + (b.lon - a.lon) * f,
            ),
            t: t,
            headingDeg: heading,
            speedMps: mps,
            accuracyM: 5,
          ));
          sent++;
          t = t.add(const Duration(seconds: 1));
          await Future<void>.delayed(Duration.zero);
        }
        carry = (carry - length) % mps;
      }
    }
    final end = route.lines.last.last;
    _fixes.add((at: end, t: t, headingDeg: null, speedMps: 0, accuracyM: 5));
    sent++;
    await Future<void>.delayed(Duration.zero);
    return t;
  }

  /// Stays at [at] for [seconds] fixes after [after], once a second.
  Future<void> park(LatLng at, DateTime after, int seconds) async {
    for (var s = 1; s <= seconds; s++) {
      _fixes.add((
        at: at,
        t: after.add(Duration(seconds: s)),
        headingDeg: null,
        speedMps: 0,
        accuracyM: 5,
      ));
      sent++;
      await Future<void>.delayed(Duration.zero);
    }
  }
}

/// The phone during a drive: what was said, chimes and the screen.
class _Device implements DriveDevice {
  final List<String> said = [];
  int chimes = 0;
  bool screenOn = false;

  @override
  Future<bool> canSpeak(String languageTag) async => languageTag == 'en-US';

  @override
  Future<void> start() async {}

  @override
  Future<void> say(String text, String languageTag) async => said.add(text);

  @override
  Future<void> chime() async => chimes++;

  @override
  Future<void> keepScreenOn({required bool on}) async => screenOn = on;

  @override
  Future<void> stop() async => screenOn = false;
}
