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
import 'package:pindoro/core/location.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/drive/ui/drive_controller.dart';
import 'package:pindoro/features/drive/ui/drive_screen.dart';
import 'package:pindoro/features/learning/data/runs.dart';
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
    location = _Track(route.lines.first.first);
    overrides = [
      databaseProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(() => now),
      locationServiceProvider.overrideWithValue(location),
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
    expect(
      (container.read(driveControllerProvider) as DriveRecording).drivenM,
      closeTo(route.lengthM, route.lengthM * 0.05),
    );
    await controller.end();
    final review = container.read(driveControllerProvider) as DriveReview;
    expect(review.match.path.edges.map((e) => e.id), [
      for (final e in route.edges) e.id,
    ]);
    expect(review.graded!.tier, Tier.perfect);
    expect(review.stoppedM, isNull);
    expect(review.match.uTurns, isEmpty);
    expect(location.cancelled, isTrue);
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
  });

  test('Lost? Show the way ends the test unrecorded', () async {
    final controller = container.read(driveControllerProvider.notifier);
    container.listen(driveControllerProvider, (_, _) {});
    await controller.start(title: 't', text: 't');
    await controller.abandon();
    expect(container.read(driveControllerProvider), isA<DriveSetup>());
    expect(location.cancelled, isTrue);
    expect(await db.select(db.implicitEvidence).get(), isEmpty);
  });

  testWidgets('the screens: setup with today\'s run, recording with no map, '
      'then the review', (tester) async {
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
    expect(find.text('GPS-free drive'), findsOneWidget);
    expect(find.textContaining(' → '), findsOneWidget);
    // The recording screen ticks every second, so it never settles.
    Future<void> pumpUntil(Finder target) async {
      for (var i = 0; i < 40 && target.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
    }

    await tester.tap(find.text('Start drive'));
    await pumpUntil(find.text('00:00'));
    expect(find.text('Recording your drive'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    await tester.runAsync(() => location.drive(route, now));
    await tester.pump();
    await tester.tap(find.text("I'm there: end drive"));
    await pumpUntil(find.text('Done'));
    await settle(tester);
    expect(find.text('Perfect!'), findsOneWidget);
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

  @override
  Future<LocationResult> locate() async => Located(here);

  @override
  Stream<DriveFix> track({required String title, required String text}) {
    notice = (title, text);
    _fixes.onCancel = () => cancelled = true;
    return _fixes.stream;
  }

  Future<void> drive(Route route, DateTime start) async {
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
          ));
          t = t.add(const Duration(seconds: 1));
          await Future<void>.delayed(Duration.zero);
        }
        carry = (carry - length) % mps;
      }
    }
    final end = route.lines.last.last;
    _fixes.add((at: end, t: t, headingDeg: null, speedMps: 0));
    await Future<void>.delayed(Duration.zero);
  }
}
