import 'dart:convert';

import 'package:drift/drift.dart' show DatabaseConnection, Value;
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

  Future<String> roundWithAnswers(
    int answered, {
    Tier tier = Tier.great,
    int xp = 60,
  }) async {
    const vake = DistrictsArea({AppConfig.fixtureDistrictId});
    await db.updateSettings(
      UserSettingsCompanion(
        lastCity: const Value('tbilisi'),
        lastAreaJson: Value(jsonEncode(vake.toJson())),
      ),
    );
    final id = await db.startRound(
      cityId: 'tbilisi',
      area: vake,
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
              tier: tier,
              xp: xp,
              packVersion: 'v1',
            ),
          );
    }
    return id;
  }

  testWidgets('home without an area asks for one', (tester) async {
    await pumpApp(tester, Routes.home);
    expect(find.text('Choose an area'), findsOneWidget);
    expect(find.text('Level 1'), findsOneWidget);
    expect(find.text('Streets you know'), findsOneWidget);
  });

  testWidgets('home offers to continue an unfinished round', (tester) async {
    await tester.runAsync(() => roundWithAnswers(1));
    await pumpApp(tester, Routes.home);
    expect(find.text('Round in progress'), findsOneWidget);
    expect(find.text('Continue round'), findsOneWidget);
    expect(find.text('Start a new round instead'), findsOneWidget);
  });

  testWidgets('results list each answer with its street and the level', (
    tester,
  ) async {
    final id = (await tester.runAsync(() => roundWithAnswers(2, xp: 600)))!;
    await pumpApp(tester, '${Routes.results}?round=$id');
    expect(find.text('Level 2!'), findsOneWidget, reason: 'level-up moment');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.byType(ResultRow), findsNWidgets(2));
    expect(find.text(streets[0].nameKa), findsOneWidget);
    expect(find.text('+600'), findsNWidgets(2));
    expect(find.text('+1 200 XP'), findsOneWidget);
    expect(find.text('Level 2'), findsOneWidget);
  });

  testWidgets('done on results counts the round into home', (tester) async {
    final id = (await tester.runAsync(() => roundWithAnswers(2)))!;
    await pumpApp(tester, '${Routes.results}?round=$id');
    await tester.tap(find.bySemanticsLabel('Done'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Streets you know'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget, reason: 'newly known streets');
    expect(find.text('+120 XP'), findsOneWidget, reason: 'tip on the bar');
    expect(find.text('120'), findsOneWidget, reason: 'XP pill counted up');
  });

  testWidgets('results offer to retry Close and Miss streets', (tester) async {
    final missed = (await tester.runAsync(
      () => roundWithAnswers(3, tier: Tier.miss),
    ))!;
    await pumpApp(tester, '${Routes.results}?round=$missed');
    expect(find.text('Retry 3 missed'), findsOneWidget);
  });

  testWidgets('results without Close or Miss offer no retry', (tester) async {
    final great = (await tester.runAsync(() => roundWithAnswers(2)))!;
    await pumpApp(tester, '${Routes.results}?round=$great');
    expect(find.textContaining('Retry'), findsNothing);
  });

  testWidgets('results without a round go home', (tester) async {
    await pumpApp(tester, Routes.results);
    expect(find.text('Streets you know'), findsOneWidget);
  });
}
