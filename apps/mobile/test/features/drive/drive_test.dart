import 'dart:async';

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
import 'package:pindoro/features/drive/ui/drive_controller.dart';
import 'package:pindoro/features/drive/ui/drive_map_screen.dart';
import 'package:pindoro/features/drive/ui/drive_preview_screen.dart';
import 'package:pindoro/features/drive/ui/drive_recording_view.dart';
import 'package:pindoro/features/drive/ui/drive_route_screen.dart';
import 'package:pindoro/features/drive/ui/drive_screen.dart';
import 'package:pindoro/features/drive/ui/drive_tab.dart';
import 'package:pindoro/features/drive/ui/past_drives_screen.dart';
import 'package:pindoro/features/drive/ui/plan_map.dart';
import 'package:pindoro/features/learning/data/drive_log.dart';
import 'package:pindoro/features/learning/data/drive_places.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/runs.dart';
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

  setUpAll(() {
    final repo = SqlitePackRepository.open(AppConfig.fixturePackAsset);
    final graph = repo.roadGraph()!;
    streets = streetsByPartId(repo.streets());
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
    homeBearing = bearingDegrees(graph.at(route.junctions.last), graph.at(route.junctions.first));
    repo.close();
  });

  setUp(() {
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
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
          run: (id: 'n1:n2', fromNode: 1, toNode: 2, random: false, items: const <String>[], createdAt: now),
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
    return container.read(driveControllerProvider.notifier)..choose(DriveTo.run);
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
    expect(review.match.path.edges.map((e) => e.id), [for (final e in route.edges) e.id]);
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
    expect(decisions.every((d) => d.driveId == drive.id && d.ok == true), isTrue);
    expect(decisions.map((d) => d.seq), [for (var i = 0; i < decisions.length; i++) i]);
    expect(() => db.customStatement('DELETE FROM drive_decision'), throwsA(anything));
    final replay = await container.read(pastDriveProvider(drive.id).future);
    expect(replay!.match.path.edges.map((e) => e.id), [for (final e in route.edges) e.id]);
    expect(replay.graded!.tier, Tier.perfect);
    expect(replay.credited, review.credited);
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
    await Future.wait([controller.start(title: 't', text: 't'), controller.start(title: 't', text: 't')]);
    await location.drive(route, now);
    await Future.wait([controller.end(), controller.end()]);
    expect(await db.select(db.implicitEvidence).get(), isNotEmpty);
    expect(await container.read(driveLogDaoProvider).all(), hasLength(1));
  });

  test('setup finds the destination and suggests a level; today\'s run offers '
      'every level, Off first, another destination one step less at most', () async {
    final controller = runController();

    final run = await settled();
    expect(run.target!.junction, route.junctions.last);
    // A new player: few J cards in the raion, so Guided.
    expect(run.suggestion!.level, DriveLevel.guided);
    expect(run.suggestion!.turns, greaterThan(0));
    expect(run.chosen, DriveLevel.off);
    expect(run.choices, DriveLevel.values);

    expect(run.suggestion!.keys, isNotEmpty);
    controller.pickOwn((street: streets[route.edges.last.streetId]!, place: null, junction: null));
    final own = await settled();
    expect(own.chosen, DriveLevel.guided);
    expect(own.choices, [DriveLevel.guided, DriveLevel.coached]);
    controller.pickLevel(DriveLevel.off);
    expect((container.read(driveControllerProvider) as DriveSetup).chosen, DriveLevel.guided);
  });

  test('Rescue at Off, while stopped: Guided from there, said once; the '
      'drive logs it, rescued, changing no card and at most Close', () async {
    final controller = runController();
    await controller.start(title: 't', text: 't');
    expect((container.read(driveControllerProvider) as DriveRecording).level, DriveLevel.off);
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
    await log.save(drive('new', now.add(const Duration(days: LearningConfig.driveTrackKeepDays + 1))), '');
    expect(await log.all(), hasLength(3));
    expect(await log.track('old'), isNull);
    expect(await log.track('kept'), isEmpty);
    expect(() => db.customStatement("UPDATE drive SET goal = 'own'"), throwsA(anything));
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
    expect(decisions.every((d) => d.level == DriveLevel.quiet && d.help == NavHelp.none), isTrue);
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
    final keys = {for (final d in await db.select(db.driveDecisions).get()) ?d.itemKey};
    expect(keys, isNotEmpty);
    // Cards for them, a stability ago: recall 0.9, near due.
    await container.read(learningDaoProvider).putCards([
      for (final key in keys)
        CardState(
          itemId: key,
          phase: CardPhase.review,
          memory: Memory(stability: 10, difficulty: 5, lastReview: now.subtract(const Duration(days: 10))),
          dueAt: now,
          reps: 3,
          lastRating: Rating.good,
          introAt: now.subtract(const Duration(days: 20)),
        ),
    ]);
    Future<List<ReviewLogRow>> reviews() =>
        (db.select(db.reviewLogs)..where((r) => r.source.equalsValue(ReviewSource.drive))).get();
    Rating rating(ReviewLogRow r) => Rating.values.firstWhere((x) => x.grade == r.rating);

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

  Future<void> pumpDrive(WidgetTester tester, {String at = Routes.driveRun}) async {
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
              GoRoute(path: Routes.driveTab, builder: (_, _) => const DriveTab()),
              GoRoute(path: Routes.drive, builder: (_, state) => DriveScreen.route(state)),
              GoRoute(path: Routes.drivePreview, builder: (_, _) => const DrivePreviewScreen()),
              GoRoute(path: Routes.driveMap, builder: (_, _) => const DriveMapScreen()),
              GoRoute(
                path: Routes.pastDrives,
                builder: (_, state) => PastDrivesScreen(route: state.uri.queryParameters['route']),
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
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the screens: setup with today\'s run at Off, the black '
      'recording screen, then the debrief: each turn recalled, then shown, '
      'the marks, the tier and the streets', (tester) async {
    await SettingsDao(db).setDrivePlace(
      encodeDrivePlace((node: homeNode, street: route.edges.first.streetId!, place: null)),
      home: true,
    );
    await pumpDrive(tester);
    expect(find.byType(PlanMapLayout), findsOneWidget);
    expect(find.textContaining(' → '), findsOneWidget);
    expect(find.textContaining('starts at Off'), findsOneWidget);
    expect(find.byType(LevelPicker<DriveLevel>), findsOneWidget);
    await tester.tap(find.text('Start drive'));
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
      await tester.tap(next.evaluate().isNotEmpty ? next : find.text('See the whole drive'));
      await tester.pump();
    }
    await pumpUntil(tester, find.text('Yellow is the way, blue is yours'));
    expect(recalled, greaterThan(0));
    final dao = DriveLogDao(db);
    final recalls = await tester.runAsync(() => dao.events(DriveEventKind.recall));
    expect(recalls, hasLength(recalled));
    expect(recalls!.every((e) => e.value == null), isTrue);
    expect(await tester.runAsync(() => dao.events(DriveEventKind.debrief)), hasLength(1));
    await tester.tap(find.text('Next'));
    await tester.pump();
    await settle(tester);
    expect(find.text('Perfect!'), findsOneWidget);
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
    final pointed = await tester.runAsync(() => dao.events(DriveEventKind.point));
    expect(pointed!.single.value, closeTo(8, 0.5));
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('Guided: the map and the turn plate while moving; stopped, the '
      'bar rises, and a level picked there applies at once', (tester) async {
    await pumpDrive(tester);
    await tester.ensureVisible(find.text('Guided'));
    await tester.pump();
    await tester.tap(find.text('Guided'));
    await tester.pump();
    await tester.tap(find.text('Start drive'));
    await pumpUntil(tester, find.byType(TurnPlate));
    // The first stretch of the run, then a stop short of the destination.
    final first = Route(route.junctions.take(2).toList(), [route.edges.first], route.edges.first.lengthM);
    final last = await tester.runAsync(() => location.drive(first, now));
    await tester.pump();
    await tester.pump(PindoroMotion.durationSlow);
    expect(maps.last.route, isNotEmpty);
    expect(maps.last.at, isNotNull);
    expect(find.byType(TurnPlate), findsOneWidget);
    // The next turn's card: its arrow beside the distance, and the arrow on the map.
    final card = tester.widget<TurnPlate>(find.byType(TurnPlate));
    expect(card.glyph, isNotNull);
    expect(card.headline, matches(RegExp(r'^\d')));
    expect(maps.last.turn, isNotEmpty);
    expect(find.byType(StoppedBar), findsNothing);
    await tester.runAsync(() => location.park(first.lines.last.last, last!, 3));
    await pumpUntil(tester, find.byType(StoppedBar));
    await tester.pump(PindoroMotion.durationSlow);
    await tester.tap(find.bySemanticsLabel('Mute the voice'));
    await tester.pump();
    expect(find.bySemanticsLabel('Unmute the voice'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Level: Guided. Change.'));
    await tester.pump();
    expect(find.text('Level for the rest of this drive'), findsOneWidget);
    await tester.tap(find.text('Quiet'));
    await pumpUntil(tester, find.byType(HeadingDial));
    expect(find.byType(HeadingDial), findsOneWidget);
    await tester.tap(find.text('End drive'));
    // Stopped short of the destination: the debrief, on its offer or (with
    // no turn to go through) the tier.
    final debrief = find.byWidgetPredicate((w) => (w is Text && w.data == 'Drive done') || w is RevealSheet);
    await pumpUntil(tester, debrief);
    expect(debrief, findsOneWidget);
  });

  testWidgets('Guided: the map moves at any speed, Recentre or 10 s bring it '
      'back to the car; back can\'t end the drive; the Route screen closes '
      'once when the car moves', (tester) async {
    await pumpDrive(tester);
    await tester.ensureVisible(find.text('Guided'));
    await tester.pump();
    await tester.tap(find.text('Guided'));
    await tester.pump();
    await tester.tap(find.text('Start drive'));
    await pumpUntil(tester, find.byType(DriveRecordingView));
    final scope = tester.widget<PopScope>(
      find.descendant(
        of: find.byType(DriveRecordingView),
        matching: find.byWidgetPredicate((w) => w is PopScope),
      ),
    );
    expect(scope.canPop, isFalse, reason: 'back would throw the drive away');
    expect(maps.last.at, isNotNull, reason: 'opens where the phone is');
    expect(maps.last.route, isNotEmpty, reason: 'the route picked at setup, before the first fix');

    final first = Route(route.junctions.take(2).toList(), [route.edges.first], route.edges.first.lengthM);
    final last = await tester.runAsync(() => location.drive(first, now));
    await tester.pump();
    await tester.pump(PindoroMotion.durationSlow);
    expect(find.byType(StoppedBar), findsNothing, reason: 'moving');
    final recentre = find.bySemanticsLabel('Recentre');
    expect(recentre, findsNothing);
    expect(maps.last.follow, isTrue);
    maps.last.onMoved!();
    await tester.pump();
    expect(maps.last.follow, isFalse);
    await tester.tap(recentre);
    await tester.pump();
    expect(maps.last.follow, isTrue, reason: 'Recentre works while moving');
    expect(recentre, findsNothing);
    maps.last.onMoved!();
    await tester.pump(const Duration(seconds: 9));
    expect(maps.last.follow, isFalse);
    await tester.pump(const Duration(seconds: 2));
    expect(maps.last.follow, isTrue, reason: 'back on the car after 10 s');

    await tester.runAsync(() => location.park(first.lines.last.last, last!, 3));
    await pumpUntil(tester, find.byType(StoppedBar));
    await tester.pump(PindoroMotion.durationSlow);
    await tester.tap(find.bySemanticsLabel('Route and destination'));
    await tester.pump();
    await tester.pump(PindoroMotion.durationSlow);
    expect(find.byType(DriveRouteScreen), findsOneWidget);
    // Driving off: every fix and prompt is a state change while the screen leaves.
    await tester.runAsync(() => location.drive(first, last!.add(const Duration(seconds: 10))));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(DriveRouteScreen), findsNothing);
    expect(find.byType(DriveRecordingView), findsOneWidget);
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
    final result = find.descendant(of: find.byType(ListRow), matching: find.text(street.name));
    await pumpUntil(tester, result);
    expect(find.text('Set your home'), findsNothing, reason: 'only results');
    await tester.tap(result.first);
    await pumpUntil(tester, find.byType(LevelSuggestion));
    expect(find.byType(LevelPicker<DriveLevel>), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is PindoroIconButton && w.semanticLabel == 'Change destination'),
      findsOneWidget,
    );
  });

  testWidgets('the Drive tab: Home set shows the minutes there, and one tap '
      'sets the drive up on Home', (tester) async {
    await SettingsDao(db).setDrivePlace(
      encodeDrivePlace((node: endNode, street: route.edges.last.streetId!, place: null)),
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
    await pumpUntil(tester, find.byType(LevelSuggestion));
    expect(find.byType(LevelPicker<DriveLevel>), findsOneWidget);
    expect(find.text('Start drive'), findsOneWidget);
  });

  testWidgets('Surprise me with no turns known yet says why there is no '
      'surprise', (tester) async {
    await pumpDrive(tester, at: Routes.driveTo('surprise'));
    await pumpUntil(tester, find.text('No surprise yet'));
    expect(find.text('No surprise yet'), findsOneWidget);
    expect(find.textContaining('7 of every 10 turns'), findsOneWidget);
    expect(find.text('Start drive'), findsOneWidget);
  });

  testWidgets('choose on the map: a tap snaps the pin to the nearest junction '
      'on a named street, and Drive here sets the drive up on it', (tester) async {
    await pumpDrive(tester, at: Routes.driveTab);
    await tester.tap(find.text('Choose on the map'));
    await settle(tester);
    expect(find.text('Tap the map where you’re going.'), findsOneWidget);
    final drive = find.text('Drive here');
    expect(
      tester.widget<PindoroButton>(find.ancestor(of: drive, matching: find.byType(PindoroButton))).onPressed,
      isNull,
      reason: 'nothing picked yet',
    );
    final end = route.lines.last.last;
    plans.last.onTap!(end);
    await tester.pump();
    expect(distanceBetween(plans.last.pin!, end), lessThan(1), reason: 'snapped to the junction');
    expect(find.text('Tap the map where you’re going.'), findsNothing);
    await tester.tap(drive);
    await pumpUntil(tester, find.byType(LevelSuggestion));
    expect(find.byType(LevelPicker<DriveLevel>), findsOneWidget);
    expect(
      find.text(streets[route.edges.last.streetId]!.name),
      findsWidgets,
      reason: 'the destination is the junction’s street',
    );
  });

  testWidgets('the Drive tab’s drives: the one waiting to be gone through, '
      'the week’s goal, the two drives to pick and Past drives', (tester) async {
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
      'picked in yellow, the others grey; another picked takes the yellow', (tester) async {
    await pumpDrive(tester);
    await pumpUntil(tester, find.text('Fastest'));
    expect(plans.last.traces, isNotEmpty, reason: 'the other routes');
    final fastest = plans.last.route!.best;
    final other = find.descendant(of: find.byType(ListRow), matching: find.textContaining(' min · ')).at(1);
    await tester.ensureVisible(other);
    await tester.pump();
    await tester.tap(other);
    await tester.pump();
    expect(plans.last.route!.best, isNot(equals(fastest)));
    expect(find.byType(LevelSuggestion), findsOneWidget);
  });

  testWidgets('the preview: the route, then its key turns stepped through '
      'with Back and Next, then Recite: a way tapped at each, right or wrong '
      'at once, cards untouched', (tester) async {
    await pumpDrive(tester);
    await pumpUntil(tester, find.byType(LevelSuggestion));
    await tester.tap(find.text('Preview'));
    await pumpUntil(tester, find.text('Your route'));
    // North-up, the route in yellow with no track yet.
    expect(plans.last.route!.best, isNotEmpty);
    expect(plans.last.route!.track, isEmpty);
    expect(plans.last.bearing, 0);
    await tester.tap(find.text('Show the turns'));
    await tester.pump();
    final first = tester.widget<Text>(find.textContaining('Key turn 1 of '));
    final turns = int.parse(first.data!.split(' of ').last);
    await tester.tap(find.text('Back'));
    await tester.pump();
    expect(find.text('Show the turns'), findsOneWidget, reason: 'the route');
    await tester.tap(find.text('Show the turns'));
    await tester.pump();
    for (var i = 0; i < turns; i++) {
      expect(find.text('Key turn ${i + 1} of $turns'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pump();
    }
    expect(find.text('Recite the turns'), findsOneWidget);
    final dao = DriveLogDao(db);
    expect(await tester.runAsync(() => dao.events(DriveEventKind.preview)), hasLength(1));
    await tester.tap(find.text('Recite the turns'));
    await tester.pump();
    expect(plans.last.names.streets, isEmpty, reason: 'a street name on the map would give the way away');
    await tester.tap(find.byType(ExitButton).first);
    await tester.pump();
    expect(find.byType(RevealSheet), findsOneWidget);
    expect(plans.last.names, MapNames.all);
    final recited = await tester.runAsync(() => dao.events(DriveEventKind.recite));
    expect(recited, hasLength(1));
    expect(recited!.single.value, anyOf(0, 1));
    expect(await tester.runAsync(() => LearningDao(db).log()), isEmpty, reason: 'reciting reviews no card');
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
class _Track extends LocationService {
  _Track(this.here);

  final LatLng here;
  var _fixes = StreamController<DriveFix>();
  (String, String)? notice;
  bool cancelled = false;

  /// How many fixes [drive] sent.
  int sent = 0;

  @override
  Future<LocationResult> locate({bool ask = true}) async => Located(here);

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
            at: LatLng(a.lat + (b.lat - a.lat) * f, a.lon + (b.lon - a.lon) * f),
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
      _fixes.add((at: at, t: after.add(Duration(seconds: s)), headingDeg: null, speedMps: 0, accuracyM: 5));
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
