import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/app/app.dart';
import 'package:pindoro/app/config.dart';
import 'package:pindoro/app/database.dart';
import 'package:pindoro/app/router.dart';
import 'package:pindoro/features/map/pindoro_map.dart';
import 'package:pindoro/features/pack/sqlite_pack_repository.dart';
import 'package:pindoro/features/quiz/quiz_screen.dart';
import 'package:pindoro/features/quiz/round_controller.dart';
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

  testWidgets('confirm reveals the score, next asks the following street', (
    tester,
  ) async {
    PindoroMap? map;
    await tester.runAsync(
      () => db.updateSettings(
        UserSettingsCompanion(
          lastAreaJson: Value(
            jsonEncode(
              const DistrictsArea({AppConfig.fixtureDistrictId}).toJson(),
            ),
          ),
          lastDifficulty: const Value(Difficulty.expert),
          onboardingDone: const Value(true),
        ),
      ),
    );
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
        child: const PindoroApp(initialLocation: Routes.quiz),
      ),
    );
    await settle(tester);

    expect(find.text('1 / 10'), findsOneWidget);
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

    expect(find.byType(FeedbackBadge), findsOneWidget);
    expect(find.text('0 m · +100 xp'), findsOneWidget);
    expect(map!.truth, isNotNull);
    expect(map!.onTap, isNull, reason: 'no new pins while revealed');

    await tester.tap(find.text('Next'));
    await settle(tester);
    expect(find.text('2 / 10'), findsOneWidget);
    expect(map!.truth, isNull);
  });
}
