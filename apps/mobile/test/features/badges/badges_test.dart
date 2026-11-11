import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pindoro/app/app.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/badges/data/badge_data.dart';
import 'package:pindoro/features/league/data/league_api.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/pack/data/pack_store.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';

void main() {
  late AppDatabase db;
  late ProgressDao dao;
  late Directory root;
  late PackStore store;
  late List<Street> streets;

  setUpAll(() {
    final pack = SqlitePackRepository.open(AppConfig.fixturePackAsset);
    streets = pack.streets(districtId: AppConfig.fixtureDistrictId);
    pack.close();
  });

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    dao = ProgressDao(db);
    root = Directory.systemTemp.createTempSync('badges');
    store = PackStore(
      root: root,
      apiBaseUrl: 'http://api.test',
      client: MockClient((_) async => http.Response('', 404)),
    );
  });
  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  /// The fixture pack installed as Tbilisi's.
  void install() {
    Directory('${root.path}/tbilisi').createSync();
    File(AppConfig.fixturePackAsset).copySync('${root.path}/tbilisi/v1.sqlite');
  }

  /// A Tbilisi round answering [streetIds] Perfect; its id.
  Future<String> know(Iterable<String> streetIds) async {
    final ids = streetIds.toList();
    final round = await dao.startRound(
      cityId: 'tbilisi',
      area: const DistrictsArea({AppConfig.fixtureDistrictId}),
      difficulty: Difficulty.expert,
      packVersion: 'v1',
      streetIds: ids,
    );
    for (final id in ids) {
      await dao.recordAnswer(
        roundId: round,
        streetId: id,
        pin: const LatLng(41.7, 44.75),
        distanceM: 0,
        tier: Tier.perfect,
        xp: 100,
        packVersion: 'v1',
      );
    }
    return round;
  }

  group('stats', () {
    test('nothing played: no stats, no pack opened', () async {
      final stats = await readBadgeStats(dao, store);
      expect((stats.pins, stats.knownDistricts), (0, 0));
    });

    test('raions known and mastered come from the installed pack', () async {
      install();
      final pack = SqlitePackRepository.open(AppConfig.fixturePackAsset);
      final raion = pack.partsByDistrict()[AppConfig.fixtureDistrictId]!;
      pack.close();
      await know([raion.first]);
      var stats = await readBadgeStats(dao, store);
      expect((stats.knownDistricts, stats.masteredDistricts), (1, 0));
      await know(raion);
      stats = await readBadgeStats(dao, store);
      expect((stats.knownDistricts, stats.masteredDistricts), (1, 1));
      expect(stats.pins, raion.length + 1);
    });

    test('a city whose pack isn\'t installed counts no raions', () async {
      await know(['a']);
      final stats = await readBadgeStats(dao, store);
      expect((stats.pins, stats.knownDistricts), (1, 0));
    });
  });

  group('screens', () {
    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> pump(WidgetTester tester, String location) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            pindoroMapBuilderProvider.overrideWithValue(
              (_) => const SizedBox(),
            ),
            packRepositoryProvider.overrideWith((ref) async {
              final repo = SqlitePackRepository.open(
                AppConfig.fixturePackAsset,
              );
              ref.onDispose(repo.close);
              return repo;
            }),
            packStoreProvider.overrideWithValue(store),
            leagueApiProvider.overrideWithValue(
              LeagueApi(
                'https://api.example',
                client: MockClient((_) async => http.Response('', 503)),
              ),
            ),
          ],
          child: PindoroApp(initialLocation: location),
        ),
      );
      await settle(tester);
    }

    Future<void> tapThrough(WidgetTester tester, Finder target) async {
      await tester.runAsync(() async {
        await tester.tap(target);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await settle(tester);
    }

    testWidgets(
      'Me shows the shelf, and a New pill until the tab opens again',
      (tester) async {
        await tester.runAsync(() async {
          await know([streets.first.id]);
          await dao.earn([BadgeId.firstPin], DateTime.now());
        });
        await pump(tester, Routes.me);
        await tester.scrollUntilVisible(find.text('Badges · 1 of 8'), 300);
        expect(find.bySemanticsLabel('First pin, earned.'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Road trip, locked, 0 of 5.'),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel('Navigator, locked.'), findsOneWidget);
        expect(find.text('New'), findsOneWidget);

        await tapThrough(tester, find.bySemanticsLabel('Leagues').first);
        await tapThrough(tester, find.bySemanticsLabel('Me').first);
        expect(find.text('New'), findsNothing);
      },
    );

    testWidgets('Results shows the First pin sheet for a first round', (
      tester,
    ) async {
      late String round;
      await tester.runAsync(() async {
        // Any saved badge keeps the quiet launch award out of the way.
        await dao.earn([BadgeId.onFire], DateTime.now());
        round = await know([streets.first.id]);
        await dao.finishRound(round);
      });
      await pump(tester, Routes.resultsOf(round));
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(find.text('Badge unlocked'), findsOneWidget);
      expect(find.text('First pin · Drop your first pin.'), findsOneWidget);

      await tapThrough(tester, find.text('Nice!'));
      expect(find.text('Badge unlocked'), findsNothing);
      final seen = await tester.runAsync(
        () async => (await dao.earnedBadges())[BadgeId.firstPin]?.seenAt,
      );
      expect(seen, isNotNull);
    });

    testWidgets('launch awards past play quietly while there are no badges', (
      tester,
    ) async {
      await tester.runAsync(() => know([streets.first.id]));
      await pump(tester, Routes.home);
      final saved = await tester.runAsync(dao.earnedBadges);
      expect(saved![BadgeId.firstPin]?.seenAt, isNull);
      expect(saved.keys, contains(BadgeId.firstPin));
      expect(find.text('Badge unlocked'), findsNothing);
    });

    testWidgets('launch awards nothing once a badge exists', (tester) async {
      await tester.runAsync(() async {
        await dao.earn([BadgeId.onFire], DateTime.now());
        await know([streets.first.id]);
      });
      await pump(tester, Routes.home);
      final saved = await tester.runAsync(dao.earnedBadges);
      expect(saved!.keys, {BadgeId.onFire});
    });
  });
}
