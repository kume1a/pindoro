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
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/drive_device.dart';
import 'package:pindoro/core/location.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/drive/ui/drive_controller.dart';
import 'package:pindoro/features/drive/ui/drive_screen.dart';
import 'package:pindoro/features/drive/ui/past_drives_screen.dart';
import 'package:pindoro/features/learning/data/drive_log.dart';
import 'package:pindoro/features/learning/data/runs.dart';
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
    location = _Track(route.lines.first.first);
    device = _Device();
    overrides = [
      databaseProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(() => clockNow),
      locationServiceProvider.overrideWithValue(location),
      driveDeviceProvider.overrideWithValue(device),
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
      pindoroMapBuilderProvider.overrideWithValue(
        (_) => const SizedBox.expand(),
      ),
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
  });

  test('a drive of today\'s run records in the background, then replays as '
      'its matched path graded against the best route', () async {
    final controller = container.read(driveControllerProvider.notifier);
    container.listen(driveControllerProvider, (_, _) {});
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

  test('a drive that loses GPS logs its gaps and says so', () async {
    final controller = container.read(driveControllerProvider.notifier);
    container.listen(driveControllerProvider, (_, _) {});
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
    final controller = container.read(driveControllerProvider.notifier);
    container.listen(driveControllerProvider, (_, _) {});
    // The fake's track allows one listener: a second start would throw.
    await Future.wait([
      controller.start(title: 't', text: 't'),
      controller.start(title: 't', text: 't'),
    ]);
    await location.drive(route, now);
    await Future.wait([controller.end(), controller.end()]);
    final review = container.read(driveControllerProvider) as DriveReview;
    final saved = review.credited + review.failed;
    expect(saved, greaterThan(0));
    expect(await db.select(db.implicitEvidence).get(), hasLength(saved));
    expect(await container.read(driveLogDaoProvider).all(), hasLength(1));
  });

  test(
    'setup finds the destination and suggests a level; today\'s run offers '
    'every level, Off first, another destination one step less at most',
    () async {
      container.listen(driveControllerProvider, (_, _) {});
      Future<DriveSetup> settled() async {
        for (var i = 0; i < 50; i++) {
          final s = container.read(driveControllerProvider) as DriveSetup;
          if (s.target != null || s.noTarget) return s;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        return container.read(driveControllerProvider) as DriveSetup;
      }

      final run = await settled();
      expect(run.target!.junction, route.junctions.last);
      // A new player: few J cards in the raion, so Guided.
      expect(run.suggestion!.level, DriveLevel.guided);
      expect(run.suggestion!.turns, greaterThan(0));
      expect(run.chosen, DriveLevel.off);
      expect(run.choices, DriveLevel.values);

      final controller = container.read(driveControllerProvider.notifier);
      controller.pickOwn(streets[route.edges.last.streetId]!);
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
    final controller = container.read(driveControllerProvider.notifier);
    container.listen(driveControllerProvider, (_, _) {});
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
    final controller = container.read(driveControllerProvider.notifier);
    container.listen(driveControllerProvider, (_, _) {});
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
    final controller = container.read(driveControllerProvider.notifier);
    container.listen(driveControllerProvider, (_, _) {});
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

  test('a level picked while stopped applies at once; leaving Off ends the '
      'GPS-free test, so no card changes', () async {
    final controller = container.read(driveControllerProvider.notifier);
    container.listen(driveControllerProvider, (_, _) {});
    await controller.start(title: 't', text: 't');
    controller.pickDriveLevel(DriveLevel.quiet);
    final quiet = container.read(driveControllerProvider) as DriveRecording;
    expect(quiet.level, DriveLevel.quiet);
    expect(device.screenOn, isTrue);
    await location.drive(route, now);
    await controller.end();
    expect(await db.select(db.implicitEvidence).get(), isEmpty);
    final drive = (await container.read(driveLogDaoProvider).all()).single;
    expect(drive.level, DriveLevel.off, reason: 'the level it started at');
  });

  Future<void> pumpDrive(WidgetTester tester) async {
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
            initialLocation: Routes.drive,
            routes: [
              GoRoute(
                path: Routes.drive,
                builder: (_, _) => const DriveScreen(),
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

  testWidgets('the screens: setup with today\'s run at Off, the black '
      'recording screen, then the review', (tester) async {
    await pumpDrive(tester);
    expect(find.text('Drive'), findsOneWidget);
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
    await pumpUntil(tester, find.text('Done'));
    await settle(tester);
    expect(find.text('Perfect!'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('Guided: the map and the turn plate while moving; stopped, the '
      'bar rises, and a level picked there applies at once', (tester) async {
    await pumpDrive(tester);
    await tester.tap(find.text('Guided'));
    await tester.pump();
    await tester.tap(find.text('Start drive'));
    await pumpUntil(tester, find.byType(TurnPlate));
    // The first stretch of the run, then a stop short of the destination.
    final first = Route(route.junctions.take(2).toList(), [
      route.edges.first,
    ], route.edges.first.lengthM);
    final last = await tester.runAsync(() => location.drive(first, now));
    await tester.pump();
    await tester.pump(PindoroMotion.durationSlow);
    expect(maps.last.route, isNotEmpty);
    expect(maps.last.at, isNotNull);
    expect(find.byType(TurnPlate), findsOneWidget);
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
    await pumpUntil(tester, find.text('Done'));
    expect(find.text('Done'), findsOneWidget);
  });
}

/// A location service that is at [here] and plays a drive as fixes once a
/// second at 8 m/s, with the device's heading and speed.
class _Track extends LocationService {
  _Track(this.here);

  final LatLng here;
  final _fixes = StreamController<DriveFix>();
  (String, String)? notice;
  bool cancelled = false;

  /// How many fixes [drive] sent.
  int sent = 0;

  @override
  Future<LocationResult> locate() async => Located(here);

  @override
  Stream<DriveFix> track({required String title, required String text}) {
    notice = (title, text);
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
