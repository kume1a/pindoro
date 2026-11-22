import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/app/app.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/learning/data/drive_log.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/progress.dart';
import 'package:pindoro/features/learning/data/today_plan.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
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

  Future<void> placed() =>
      LearningDao(db).markPlaced(AppConfig.defaultCityId, DateTime(2026));

  Future<void> pump(
    WidgetTester tester,
    SessionPlan plan, {
    List<Override> more = const [],
  }) async {
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
          ...more,
          databaseProvider.overrideWithValue(db),
          pindoroMapBuilderProvider.overrideWithValue((_) => const SizedBox()),
          todayPlanProvider.overrideWith((ref) async => plan),
          dueTomorrowProvider.overrideWith((ref) async => 22),
          packRepositoryProvider.overrideWith((ref) async {
            final repo = SqlitePackRepository.open(AppConfig.fixturePackAsset);
            ref.onDispose(repo.close);
            return repo;
          }),
          cityMemoryProvider.overrideWith(
            (ref) async => (
              city: (
                memory: 1284.4,
                total: 3282,
                counts: {
                  MemoryState.mastered: 412,
                  MemoryState.solid: 630,
                  MemoryState.known: 220,
                  MemoryState.seen: 90,
                },
              ),
              sinceYesterday: 8.2,
              sinceWeek: -41.2,
              firstDay: false,
            ),
          ),
        ],
        child: const PindoroApp(initialLocation: Routes.today),
      ),
    );
    await settle(tester);
  }

  const ready = SessionPlan(
    rounds: [
      [(kind: StepKind.review, itemId: 'P:x')],
      [(kind: StepKind.review, itemId: 'P:y')],
    ],
    dueCount: 24,
    backlog: false,
    reviewCount: 24,
    newCount: 10,
  );

  testWidgets('first run: placement or zero; zero goes on to ready', (
    tester,
  ) async {
    await pump(tester, ready);
    expect(find.text('Let’s see what you already know'), findsOneWidget);
    expect(find.text('Today’s drive'), findsNothing);
    await tapThrough(tester, find.text('Start from zero'));
    expect(find.text('Today’s drive'), findsOneWidget);
  });

  testWidgets('ready: the session’s size, its counts and Start, over City '
      'memory', (tester) async {
    await placed();
    await pump(tester, ready);
    expect(find.text('Today’s drive'), findsOneWidget);
    expect(find.text('2 rounds · saves as you go'), findsOneWidget);
    expect(find.bySemanticsLabel('Reviews, 24'), findsOneWidget);
    expect(find.bySemanticsLabel('New, 10'), findsOneWidget);
    expect(find.text('Turns'), findsNothing);
    expect(find.text('Drills'), findsNothing);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('+8 since yesterday'), findsOneWidget);
    expect(find.text('Coming up'), findsOneWidget);
    expect(find.text('Now learning'), findsOneWidget);
    expect(find.text('Main roads'), findsOneWidget);
    expect(find.textContaining('Next: Secondary roads'), findsOneWidget);
    expect(find.text('Next 7 days'), findsOneWidget);
    expect(find.text('Last 7 days'), findsNothing);
    expect(find.textContaining('1\u202f284 of 3\u202f282'), findsOneWidget);
  });

  testWidgets('a day of only drills shows them, never Reviews 0 and New 0', (
    tester,
  ) async {
    await placed();
    await pump(
      tester,
      const SessionPlan(
        rounds: [
          [(kind: StepKind.bearing, itemId: 'P:x')],
        ],
        dueCount: 0,
        backlog: false,
        reviewCount: 0,
        newCount: 0,
        drills: Drills(bearings: ['P:y', 'P:z']),
      ),
    );
    expect(find.bySemanticsLabel('Drills, 2, bearings'), findsOneWidget);
    expect(find.text('Reviews'), findsNothing);
    expect(find.text('New'), findsNothing);
  });

  testWidgets('done: nothing left today, tomorrow’s reviews', (tester) async {
    await placed();
    await pump(
      tester,
      const SessionPlan(
        rounds: [],
        dueCount: 0,
        backlog: false,
        reviewCount: 0,
        newCount: 0,
      ),
    );
    expect(find.text('Today’s goal done'), findsOneWidget);
    expect(find.text('22 reviews due tomorrow'), findsOneWidget);
    expect(find.text('Start'), findsNothing);
    expect(find.text('Learn 10 more'), findsOneWidget);
    expect(find.text('Free play'), findsOneWidget);
    expect(find.text('Last 7 days'), findsOneWidget);
    expect(find.text('tomorrow 0'), findsOneWidget);
  });

  testWidgets('the day’s minutes spent with reviews still due: done, never '
      'Catch up into an empty session', (tester) async {
    await placed();
    await pump(
      tester,
      const SessionPlan(
        rounds: [],
        dueCount: 2,
        backlog: true,
        reviewCount: 0,
        newCount: 0,
      ),
    );
    expect(find.text('Today’s goal done'), findsOneWidget);
    expect(find.text('Catch up'), findsNothing);
    expect(find.textContaining('Most overdue first'), findsNothing);
    expect(find.text('Learn 10 more'), findsOneWidget);
    expect(find.textContaining('caught up by'), findsNothing);
  });

  testWidgets('catching up: the reviews waiting, no new streets, Catch up and '
      'the week’s change', (tester) async {
    await placed();
    await pump(
      tester,
      const SessionPlan(
        rounds: [
          [(kind: StepKind.review, itemId: 'P:x')],
        ],
        dueCount: 186,
        backlog: true,
        reviewCount: 150,
        newCount: 0,
      ),
    );
    expect(find.text('186 reviews waiting'), findsOneWidget);
    expect(
      find.text(
        'New streets are paused until you catch up. About 2 days at 20 min.',
      ),
      findsOneWidget,
    );
    expect(find.text('Catch up'), findsOneWidget);
    expect(find.bySemanticsLabel('New, 0, paused'), findsOneWidget);
    expect(find.text('−41 this week'), findsOneWidget);
    expect(find.textContaining('Most overdue first'), findsOneWidget);
    expect(find.textContaining('caught up by'), findsOneWidget);
    expect(find.textContaining('· paused'), findsOneWidget);
  });

  testWidgets('drives: the one waiting to be gone through, the week’s goal '
      'and, once a week, the two drives to pick', (tester) async {
    await placed();
    // A Wednesday: three drives this week on one route, the last an hour ago.
    final now = DateTime(2026, 11, 18, 12);
    final pack = SqlitePackRepository.open(AppConfig.fixturePackAsset);
    final nodes = pack.junctionNodes().values.toList();
    final street = pack.roadGraph()!.edges.first.streetId!;
    pack.close();
    final log = DriveLogDao(db);
    for (var i = 0; i < 3; i++) {
      final at = now.subtract(Duration(hours: 3 - i));
      await log.save(
        DriveRow(
          id: 'd$i',
          startedAt: at.subtract(const Duration(minutes: 20)),
          endedAt: at,
          level: DriveLevel.quiet,
          goal: 'own',
          startNode: nodes.first,
          targetNode: nodes.last,
          targetStreet: street,
          outcome: DriveOutcome.arrived,
          drivenM: 2000,
          credited: 0,
          failed: 0,
          fixes: 0,
          gpsGaps: 0,
          longestGapS: 0,
          recoveries: 0,
          rescued: false,
          mostHelp: DriveLevel.quiet,
        ),
        '',
        decisions: [
          DriveDecisionRow(
            driveId: 'd$i',
            seq: 0,
            at: at,
            itemKey: 'J:n1:n2:n3',
            planned: true,
            ok: true,
            level: DriveLevel.quiet,
            help: NavHelp.none,
            recentHelp: false,
            hesitated: false,
            keyTurn: true,
          ),
        ],
      );
    }
    await pump(
      tester,
      ready,
      more: [clockProvider.overrideWithValue(() => now)],
    );
    expect(find.text('Drives'), findsOneWidget);
    expect(find.text('Your drive is waiting'), findsOneWidget);
    expect(find.text('This week’s goal is done.'), findsOneWidget);
    expect(find.text('Pick your two drives'), findsOneWidget);
    await tapThrough(tester, find.text('Not this week'));
    expect(find.text('Pick your two drives'), findsNothing);
  });
}
