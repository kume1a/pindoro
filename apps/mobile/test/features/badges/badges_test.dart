import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pindoro/app/app.dart';
import 'package:pindoro/core/api_client.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/badges/data/badge_data.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/pack/data/pack_store.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

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
        packVersion: 'v1',
      );
    }
    return round;
  }

  group('stats', () {
    test('nothing played: no stats, no pack opened', () async {
      final stats = await readBadgeStats(dao, LearningDao(db), store);
      expect((stats.pins, stats.knownDistricts), (0, 0));
    });

    test('raions and neighbourhoods Mastered come from the cards, in the '
        'installed pack', () async {
      install();
      await LearningDao(db).markPlaced('tbilisi', DateTime(2026));
      final pack = SqlitePackRepository.open(AppConfig.fixturePackAsset);
      final raionOf = {for (final d in pack.districts()) d.id: ?d.parentId};
      final inRaion = streetsByPartId(pack.streets()).values
          .toSet()
          .where(
            (s) =>
                Curriculum.isCore(s) &&
                raionOf[s.parts.first.chunkId] == AppConfig.fixtureDistrictId,
          )
          .toList();
      pack.close();
      final now = DateTime.now();
      CardState mastered(NamedStreet s, [CardType type = CardType.p]) =>
          CardState(
            itemId: type.item(s.id),
            phase: CardPhase.review,
            memory: Memory(
              stability: 120,
              difficulty: 5,
              lastReview: now.subtract(const Duration(days: 1)),
            ),
            dueAt: now.add(const Duration(days: 100)),
            lastRating: Rating.good,
            priorKnown: true,
          );
      await LearningDao(db).putCards([mastered(inRaion.first)]);
      var stats = await readBadgeStats(dao, LearningDao(db), store);
      expect((stats.knownDistricts, stats.masteredDistricts), (1, 0));
      await LearningDao(db).putCards([
        for (final type in [CardType.p, CardType.n, CardType.e])
          for (final s in inRaion) mastered(s, type),
      ]);
      stats = await readBadgeStats(dao, LearningDao(db), store);
      expect((stats.knownDistricts, stats.masteredDistricts), (1, 1));
      expect(stats.masteredNeighbourhoods, greaterThan(0));
    });

    test('a city whose pack isn\'t installed counts no raions', () async {
      await know(['a']);
      final stats = await readBadgeStats(dao, LearningDao(db), store);
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
            apiClientProvider.overrideWithValue(
              ApiClient(
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
          await dao.earn(['firstPin', 'pitCrew'], DateTime.now());
        });
        await pump(tester, Routes.me);
        await tester.scrollUntilVisible(find.text('Badges · 2 of 11'), 300);
        expect(find.bySemanticsLabel('First pin, earned.'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Keeper, locked, 0 of 100.'),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel('Navigator, locked.'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Pit crew, retired, earned.'),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel(RegExp('^Road trip')), findsNothing);
        expect(
          find.bySemanticsLabel('City memory 500, locked, 0 of 500.'),
          findsOneWidget,
        );
        expect(find.text('New'), findsNWidgets(2));

        await tapThrough(tester, find.bySemanticsLabel('Today').first);
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
        await dao.earn(['onFire'], DateTime.now());
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
        () async => (await dao.earnedBadges())['firstPin']?.seenAt,
      );
      expect(seen, isNotNull);
    });

    testWidgets('launch awards past play quietly while there are no badges', (
      tester,
    ) async {
      await tester.runAsync(() => know([streets.first.id]));
      await pump(tester, Routes.home);
      final saved = await tester.runAsync(dao.earnedBadges);
      expect(saved!['firstPin']?.seenAt, isNull);
      expect(saved.keys, contains('firstPin'));
      expect(find.text('Badge unlocked'), findsNothing);
    });

    testWidgets('launch awards nothing once a badge exists', (tester) async {
      await tester.runAsync(() async {
        await dao.earn(['onFire'], DateTime.now());
        await know([streets.first.id]);
      });
      await pump(tester, Routes.home);
      final saved = await tester.runAsync(dao.earnedBadges);
      expect(saved!.keys, {'onFire'});
    });
  });
}
