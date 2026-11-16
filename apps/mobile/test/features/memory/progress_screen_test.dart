import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/app/app.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

import '../../support/settle.dart';

void main() {
  late AppDatabase db;
  late List<NamedStreet> streets;
  late String raion;
  final now = DateTime(2026, 3, 2, 9);

  setUpAll(() {
    final repo = SqlitePackRepository.open(AppConfig.fixturePackAsset);
    streets = streetsByPartId(repo.streets()).values.toSet().toList()
      ..sort((a, b) => b.lengthM.compareTo(a.lengthM));
    raion = repo.districts().firstWhere((d) => d.isRaion).nameKa;
    repo.close();
  });

  setUp(
    () => db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    ),
  );
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.view
      ..physicalSize = const Size(1080, 4400)
      ..devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(() => now),
          pindoroMapBuilderProvider.overrideWithValue((_) => const SizedBox()),
          packRepositoryProvider.overrideWith((ref) async {
            final repo = SqlitePackRepository.open(AppConfig.fixturePackAsset);
            ref.onDispose(repo.close);
            return repo;
          }),
        ],
        child: const PindoroApp(initialLocation: Routes.progress),
      ),
    );
    await settle(tester);
  }

  testWidgets('overview: City memory, recall, forecast and the district; '
      'the district lists its neighbourhoods', (tester) async {
    final dao = LearningDao(db);
    final reviewed = applyReview(
      null,
      itemId: CardType.p.item(streets.first.id),
      rating: Rating.good,
      now: now.subtract(const Duration(days: 3)),
      format: ReviewFormat.placement,
      source: ReviewSource.placement,
      priorKnown: true,
    );
    await dao.saveAnswer(card: reviewed.card, log: reviewed.log);

    await pump(tester);
    expect(
      find.text('City memory · streets you’d place today'),
      findsOneWidget,
    );
    expect(find.text('Recall, 30 days'), findsOneWidget);
    expect(find.text('Reviews, next 14 days'), findsOneWidget);
    final district = find.text(raion);
    expect(district, findsOneWidget);

    await tapThrough(tester, district);
    expect(find.text('Neighbourhoods'), findsOneWidget);
    expect(find.textContaining('learning now'), findsOneWidget);
  });
}
