import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/app/app.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/learning/data/today_plan.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

import '../../support/settle.dart';

void main() {
  late AppDatabase db;

  setUp(
    () => db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    ),
  );
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, SessionPlan plan) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          pindoroMapBuilderProvider.overrideWithValue((_) => const SizedBox()),
          todayPlanProvider.overrideWith((ref) async => plan),
          dueTomorrowProvider.overrideWith((ref) async => 22),
        ],
        child: const PindoroApp(initialLocation: Routes.today),
      ),
    );
    await settle(tester);
  }

  testWidgets('ready: the session’s size, its counts and Start', (
    tester,
  ) async {
    await pump(
      tester,
      const SessionPlan(
        steps: [(kind: StepKind.review, itemId: 'P:x')],
        dueCount: 24,
        backlog: false,
        reviewCount: 24,
        newCount: 10,
        estimatedS: 24 * 12 + 10 * 45,
      ),
    );
    expect(find.text('Today’s drive'), findsOneWidget);
    expect(find.text('About 13 min · saves as you go'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('done: nothing left today, tomorrow’s reviews', (tester) async {
    await pump(
      tester,
      const SessionPlan(
        steps: [],
        dueCount: 0,
        backlog: false,
        reviewCount: 0,
        newCount: 0,
        estimatedS: 0,
      ),
    );
    expect(find.text('Done for today'), findsOneWidget);
    expect(find.text('22 reviews due tomorrow'), findsOneWidget);
    expect(find.text('Start'), findsNothing);
  });
}
