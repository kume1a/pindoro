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
import 'package:pindoro/core/speech.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/today_plan.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/reminders.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

import '../../support/settle.dart';

void main() {
  late AppDatabase db;
  late LearningDao dao;
  late List<PindoroMap> maps;
  late DateTime now;
  late NamedStreet a;
  late NamedStreet b;
  late NamedStreet c;

  setUpAll(() {
    final repo = SqlitePackRepository.open(AppConfig.fixturePackAsset);
    final streets = streetsByPartId(repo.streets()).values.toSet().toList()
      ..sort((x, y) => y.lengthM.compareTo(x.lengthM));
    repo.close();
    LatLng mid(NamedStreet s) => s.parts.first.midpoint;
    a = streets.first;
    b = streets.firstWhere((s) => distanceBetween(mid(s), mid(a)) > 800);
    c = streets.firstWhere(
      (s) =>
          distanceBetween(mid(s), mid(a)) > 400 &&
          distanceBetween(mid(s), mid(b)) > 400,
    );
  });

  setUp(() {
    maps = [];
    now = DateTime(2026, 3, 2, 9);
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    dao = LearningDao(db);
  });
  tearDown(() => db.close());

  String item(NamedStreet s) => CardType.p.item(s.id);

  Future<void> pump(WidgetTester tester, List<SessionStep> steps) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          remindersProvider.overrideWithValue(_NoReminders()),
          speechProvider.overrideWithValue(_NoSpeech()),
          clockProvider.overrideWithValue(() => now),
          pindoroMapBuilderProvider.overrideWithValue((map) {
            maps.add(map);
            return const SizedBox.expand();
          }),
          packRepositoryProvider.overrideWith((ref) async {
            final repo = SqlitePackRepository.open(AppConfig.fixturePackAsset);
            ref.onDispose(repo.close);
            return repo;
          }),
          todayPlanProvider.overrideWith(
            (ref) async => SessionPlan(
              steps: steps,
              dueCount: 0,
              backlog: false,
              reviewCount: 0,
              newCount: 1,
              estimatedS: 45,
            ),
          ),
        ],
        child: const PindoroApp(initialLocation: Routes.session),
      ),
    );
    await settle(tester);
    await settle(tester);
  }

  /// Drops the pin [at] after [seconds] of thinking, then confirms.
  Future<void> answer(WidgetTester tester, LatLng at, {int seconds = 4}) async {
    now = now.add(Duration(seconds: seconds));
    maps.last.onTap!(at);
    await settle(tester);
    await tapThrough(tester, find.text('Confirm'));
  }

  LatLng onStreet(NamedStreet s) => s.parts.first.geometry.first.first;

  testWidgets(
    'intro, retrieval 1, a forgotten retrieval 2 and its relearn, then done',
    (tester) async {
      await pump(tester, [
        (kind: StepKind.intro, itemId: item(a)),
        (kind: StepKind.retrieval1, itemId: item(a)),
        (kind: StepKind.retrieval2, itemId: item(a)),
      ]);
      expect(find.text('New street · 1 of 1'), findsOneWidget);
      expect(find.text('Where it is'), findsOneWidget);
      await tapThrough(tester, find.text('Got it'));
      expect((await dao.card(item(a)))!.phase, CardPhase.learning);

      await answer(tester, onStreet(a));
      expect(find.text('Next review in 2 days'), findsOneWidget);
      await tapThrough(tester, find.text('Next'));

      // Retrieval 2, two kilometres off: forgotten, back in this session.
      await answer(tester, LatLng(onStreet(a).lat + 0.02, onStreet(a).lon));
      expect(find.text('Back in this session'), findsOneWidget);
      await tapThrough(tester, find.text('Got it'));

      await answer(tester, onStreet(a));
      expect(find.textContaining('Next review in'), findsOneWidget);
      await tapThrough(tester, find.text('Next'));

      expect(find.text('Session done'), findsOneWidget);
      final log = await dao.log();
      expect(log.map((e) => e.format), [
        ReviewFormat.retrieval1,
        ReviewFormat.retrieval2,
        ReviewFormat.relearn,
      ]);
      expect(log.map((e) => e.rating), [
        Rating.good,
        Rating.again,
        isNot(Rating.again),
      ]);
      expect(log.map((e) => e.sessionId).toSet(), hasLength(1));
      expect((await dao.card(item(a)))!.phase, CardPhase.review);
    },
  );

  testWidgets('a pin on a confused street is a Mix-up and saves the pair', (
    tester,
  ) async {
    await db
        .into(db.confusions)
        .insert(
          ConfusionsCompanion.insert(streetA: a.id, streetB: b.id, lastAt: now),
        );
    await pump(tester, [(kind: StepKind.retrieval1, itemId: item(a))]);
    await answer(tester, onStreet(b));
    expect(find.text('Mix-up'), findsOneWidget);
    expect(find.textContaining('Pair saved:'), findsOneWidget);
    expect(find.text('Back in this session'), findsOneWidget);
    expect(maps.last.hit?.geometry, b.geometry);
    expect(maps.last.measure, isNull);
    final pair = await db.select(db.confusions).getSingle();
    expect(pair.count, 2);
    expect((await dao.log()).single.snapId, b.id);
  });

  testWidgets('known streets are named on the reveal, never while asking', (
    tester,
  ) async {
    await dao.putCard(
      CardState(
        itemId: item(c),
        phase: CardPhase.review,
        memory: Memory(
          stability: 30,
          difficulty: 5,
          lastReview: now.subtract(const Duration(days: 3)),
        ),
        dueAt: now.add(const Duration(days: 20)),
        lastRating: Rating.good,
        priorKnown: true,
      ),
    );
    await pump(tester, [(kind: StepKind.retrieval1, itemId: item(a))]);
    expect(maps.last.known, isEmpty);
    await answer(tester, onStreet(a));
    expect(maps.last.known.map((k) => k.geometry), [c.geometry]);
    expect(maps.last.known.map((k) => k.geometry), isNot(contains(a.geometry)));
  });
}

class _NoReminders implements Reminders {
  @override
  dynamic noSuchMethod(Invocation invocation) async {}
}

class _NoSpeech implements Speech {
  @override
  dynamic noSuchMethod(Invocation invocation) async => false;
}
