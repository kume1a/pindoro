import 'dart:math';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/app/app.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/quiz/ui/quiz_screen.dart';
import 'package:pindoro/features/quiz/ui/round_controller.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  PindoroMap? map;

  /// A round in the fixture's Vake at Expert, at question 1.
  Future<void> pumpRound(WidgetTester tester) async {
    await tester.runAsync(() async {
      final settings = SettingsDao(db);
      await settings.chooseArea(
        const DistrictsArea({AppConfig.fixtureDistrictId}),
      );
      await settings.chooseDifficulty(Difficulty.expert);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          packRepositoryProvider.overrideWith((ref) async {
            final repo = SqlitePackRepository.open(AppConfig.fixturePackAsset);
            ref.onDispose(repo.close);
            return repo;
          }),
          questionSelectorProvider.overrideWithValue(
            QuestionSelector(random: Random(7)),
          ),
          pindoroMapBuilderProvider.overrideWithValue((m) {
            map = m;
            return const SizedBox.expand();
          }),
        ],
        child: const PindoroApp(initialLocation: Routes.round),
      ),
    );
    await settle(tester);
  }

  testWidgets('a Miss goes to the Pit stop', (tester) async {
    await pumpRound(tester);
    map!.onTap!(const LatLng(41.9, 45.2));
    await tester.pump();
    await tester.tap(find.text('Confirm'));
    await settle(tester);
    expect(find.text('Not this time'), findsOneWidget);
    expect(find.text('Added to your Pit stop'), findsOneWidget);
  });

  testWidgets('confirm reveals the score, next asks the following street', (
    tester,
  ) async {
    await pumpRound(tester);

    expect(find.bySemanticsLabel('Question 1 of 10'), findsOneWidget);
    PindoroButton button(String label) =>
        tester.widget(find.widgetWithText(PindoroButton, label));
    expect(button('Confirm').onPressed, isNull, reason: 'no pin yet');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(QuizScreen)),
    );
    final street =
        (container.read(roundControllerProvider) as RoundAsking).round.current;
    expect(find.text(street.name), findsOneWidget);

    map!.onTap!(street.geometry.first.first);
    await tester.pump();
    await tester.tap(find.text('Confirm'));
    await settle(tester);

    expect(find.byType(RevealSheet), findsOneWidget);
    expect(find.text('Perfect!'), findsOneWidget);
    expect(find.text('+100 XP'), findsOneWidget);
    expect(find.text('100'), findsOneWidget, reason: 'the round XP pill');
    expect(map!.truth, isNotNull);
    expect(map!.onTap, isNull, reason: 'no new pins while revealed');

    await tester.tap(find.text('Next'));
    await settle(tester);
    expect(find.bySemanticsLabel('Question 2 of 10'), findsOneWidget);
    expect(map!.truth, isNull);
  });
}
