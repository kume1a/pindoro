import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/app/app.dart';
import 'package:pindoro/app/config.dart';
import 'package:pindoro/app/database.dart';
import 'package:pindoro/app/router.dart';
import 'package:pindoro/features/pack/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

void main() {
  late AppDatabase db;
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
  });
  tearDown(() => db.close());

  Future<void> pumpApp(WidgetTester tester, String location) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
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

  Future<String> roundWithAnswers(int answered) async {
    final id = await db.startRound(
      cityId: 'tbilisi',
      area: const DistrictArea(AppConfig.fixtureDistrictId),
      difficulty: Difficulty.expert,
      packVersion: 'v1',
      streetIds: [for (final s in streets.take(10)) s.id],
    );
    for (final s in streets.take(answered)) {
      await db
          .into(db.answers)
          .insert(
            AnswersCompanion.insert(
              roundId: id,
              streetId: s.id,
              pinLat: s.midpoint.lat,
              pinLon: s.midpoint.lon,
              distanceM: 42,
              tier: Tier.great,
              xp: 600,
              packVersion: 'v1',
            ),
          );
    }
    return id;
  }

  testWidgets('home offers play without a round in progress', (tester) async {
    await pumpApp(tester, Routes.home);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('New round'), findsNothing);
    expect(find.textContaining('Level 1'), findsOneWidget);
  });

  testWidgets('home offers to continue an unfinished round', (tester) async {
    await tester.runAsync(() => roundWithAnswers(1));
    await pumpApp(tester, Routes.home);
    expect(find.text('Continue (1/10)'), findsOneWidget);
    expect(find.text('New round'), findsOneWidget);
  });

  testWidgets('results list each answer with its street and the level', (
    tester,
  ) async {
    final id = (await tester.runAsync(() => roundWithAnswers(2)))!;
    await pumpApp(tester, '${Routes.results}?round=$id');
    expect(find.byType(FeedbackBadge), findsNWidgets(2));
    expect(find.text(streets[0].nameKa), findsOneWidget);
    expect(find.text('42 m · +600 xp'), findsNWidgets(2));
    expect(find.text('+1200 xp this round · level up!'), findsOneWidget);
    expect(find.textContaining('Level 2'), findsOneWidget);
  });

  testWidgets('results without a round go home', (tester) async {
    await pumpApp(tester, Routes.results);
    expect(find.text('Play'), findsOneWidget);
  });
}
