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
import 'package:pindoro/features/session/ui/session_controller.dart';
import 'package:pindoro/features/session/ui/session_screen.dart';
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
  late NamedStreet parent;
  late NamedStreet child;

  /// A family with two children, for the sweep.
  late NamedStreet sweepParent;
  late List<NamedStreet> lanes;

  /// A street crossed by at least three others, in order.
  late NamedStreet avenue;
  late List<Crossing> crossings;

  setUpAll(() {
    final repo = SqlitePackRepository.open(AppConfig.fixturePackAsset);
    final byPart = streetsByPartId(repo.streets());
    final streets = byPart.values.toSet().toList()
      ..sort((x, y) => y.lengthM.compareTo(x.lengthM));
    final link = repo.families().firstWhere(
      (f) => !f.orphan && byPart[f.parentId] != byPart[f.childId],
    );
    parent = byPart[link.parentId]!;
    child = byPart[link.childId]!;
    final children = <NamedStreet, Set<NamedStreet>>{};
    for (final f in repo.families().where((f) => !f.orphan)) {
      final p = byPart[f.parentId]!, c = byPart[f.childId]!;
      if (p != c) children.putIfAbsent(p, () => {}).add(c);
    }
    final family = children.entries.firstWhere((e) => e.value.length >= 2);
    sweepParent = family.key;
    lanes = family.value.take(2).toList();
    repo.close();
    LatLng mid(NamedStreet s) => s.parts.first.midpoint;
    a = streets.first;
    b = streets.firstWhere((s) => distanceBetween(mid(s), mid(a)) > 800);
    c = streets.firstWhere(
      (s) =>
          distanceBetween(mid(s), mid(a)) > 400 &&
          distanceBetween(mid(s), mid(b)) > 400,
    );
    final all = streets.toSet();
    avenue = streets.firstWhere((s) => crossingsAlong(s, all).length >= 3);
    crossings = crossingsAlong(avenue, all);
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

  Future<void> pump(
    WidgetTester tester,
    List<SessionStep> steps, {
    String at = Routes.session,
    Drills drills = Drills.none,
  }) async {
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
              drills: drills,
            ),
          ),
        ],
        child: PindoroApp(initialLocation: at),
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

  SessionController controller(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(SessionScreen)),
      ).read(sessionControllerProvider.notifier);

  /// A P card reviewed [daysAgo] days ago, due [dueInDays] from now.
  CardState reviewed(
    String itemId, {
    double stability = 10,
    int daysAgo = 3,
    int dueInDays = 0,
    CardPhase phase = CardPhase.review,
    int lapses = 0,
  }) => CardState(
    itemId: itemId,
    phase: phase,
    memory: Memory(
      stability: stability,
      difficulty: 5,
      lastReview: now.subtract(Duration(days: daysAgo)),
    ),
    dueAt: now.add(Duration(days: dueInDays)),
    lastRating: Rating.good,
    lapses: lapses,
    priorKnown: true,
  );

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
  testWidgets('a child of a known street is guessed first, then introduced '
      'with its family', (tester) async {
    await dao.putCard(
      CardState(
        itemId: item(parent),
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
    await pump(tester, [(kind: StepKind.intro, itemId: item(child))]);
    expect(find.text('Guess first'), findsOneWidget);
    expect(find.textContaining('You know ${parent.name}'), findsOneWidget);
    expect(maps.last.known, isEmpty);
    maps.last.onTap!(onStreet(child));
    await settle(tester);
    await tapThrough(tester, find.text('Confirm guess'));

    expect((await dao.log()).single.format, ReviewFormat.pretest);
    expect(await dao.card(item(child)), isNull);
    expect(find.textContaining('Family: ${parent.name}'), findsOneWidget);
    expect(maps.last.known.map((k) => k.label), contains(parent.name));
    await tapThrough(tester, find.text('Got it'));
    expect((await dao.card(item(child)))!.phase, CardPhase.learning);
  });

  testWidgets(
    'placement: a placed street becomes a known card, a skip leaves '
    'it unseen, then the result',
    timeout: const Timeout(Duration(minutes: 2)),
    (tester) async {
      final repo = SqlitePackRepository.open(AppConfig.fixturePackAsset);
      final curriculum = Curriculum(
        streets: streetsByPartId(repo.streets()).values,
        districts: repo.districts(),
        centre: repo.city().center,
        families: repo.families(),
        chunkNeighbours: repo.chunkNeighbours(),
      );
      final byPart = streetsByPartId(repo.streets());
      final cityId = repo.city().id;
      repo.close();
      final asked = Placement(
        curriculum,
        seed: now.microsecondsSinceEpoch,
      ).streets;
      final first = byPart[asked.first]!;

      await pump(tester, const [], at: Routes.placement);
      expect(find.text('Placement · 1 of ${asked.length}'), findsOneWidget);
      await answer(tester, onStreet(first));
      expect(find.textContaining('Next review in'), findsOneWidget);
      await tapThrough(tester, find.text('Next'));

      for (var i = 0; i < asked.length; i++) {
        if (find.text('Start learning').evaluate().isNotEmpty) break;
        await tapThrough(tester, find.text('I don’t know this one'));
      }
      expect(find.text('You know 1 street already'), findsOneWidget);
      final card = (await dao.cards()).single;
      expect(card.itemId, item(first));
      expect(card.priorKnown, isTrue);
      expect((await dao.log()).single.format, ReviewFormat.placement);
      expect((await dao.learnCity(cityId))?.placedAt, isNotNull);
    },
  );

  group('M4 cards and drills', () {
    testWidgets('a name card: Show name, then Knew it saves a name review', (
      tester,
    ) async {
      await pump(tester, [(kind: StepKind.review, itemId: 'N:${a.id}')]);
      expect(find.text('What’s this street called?'), findsOneWidget);
      expect(maps.last.truth, a.geometry, reason: 'the street is the cue');
      await tapThrough(tester, find.text('Show name'));
      expect(find.text('Did you know it?'), findsOneWidget);
      await tapThrough(tester, find.text('Knew it'));
      expect(find.text('Session done'), findsOneWidget);
      final row = (await dao.log()).single;
      expect((row.format, row.rating), (ReviewFormat.name, Rating.good));
      expect((await dao.card('N:${a.id}'))!.phase, CardPhase.review);
    });

    testWidgets('every 10th name review picks among six names', (tester) async {
      for (var i = 0; i < 9; i++) {
        await dao.saveAnswer(
          log: LogEntry(
            ts: now.subtract(Duration(days: 30 - i)),
            itemId: 'N:other$i',
            format: ReviewFormat.name,
            rating: Rating.good,
            source: ReviewSource.session,
          ),
        );
      }
      await pump(tester, [(kind: StepKind.review, itemId: 'N:${a.id}')]);
      expect(find.text('Which name is it?'), findsOneWidget);
      expect(find.text('Show name'), findsNothing);
      await tapThrough(tester, find.text(a.name).last);
      expect(find.text('It’s ${a.name}.'), findsOneWidget);
      expect(find.textContaining('Next review in'), findsOneWidget);
      expect((await dao.log()).last.format, ReviewFormat.nameCheck);
    });

    testWidgets('both ends: two pins, Confirm, then how many were right', (
      tester,
    ) async {
      await pump(tester, [(kind: StepKind.review, itemId: 'E:${a.id}')]);
      final confirm = find.text('Confirm both ends');
      final (end1, end2) = streetEnds(a);
      maps.last.onTap!(end1);
      await settle(tester);
      expect(find.text('Now drop a pin on the other end'), findsOneWidget);
      maps.last.onTap!(end2);
      await settle(tester);
      expect(maps.last.morePins, [end2]);
      await tapThrough(tester, confirm);
      expect(find.text('Both ends are right.'), findsOneWidget);
      expect(maps.last.truth, a.geometry);
      final row = (await dao.log()).single;
      expect((row.format, row.rating), (ReviewFormat.extent, Rating.good));
    });

    testWidgets('a leech comes back beside its mix-up and keeps a note', (
      tester,
    ) async {
      await dao.putCard(
        reviewed(
          item(a),
          stability: 1,
          daysAgo: 1,
          phase: CardPhase.suspended,
          lapses: LearningConfig.leechLapses,
        ),
      );
      await db
          .into(db.confusions)
          .insert(
            ConfusionsCompanion.insert(
              streetA: a.id,
              streetB: b.id,
              lastAt: now,
            ),
          );
      await pump(tester, [
        (kind: StepKind.intro, itemId: item(a)),
        (kind: StepKind.retrieval1, itemId: item(a)),
      ]);
      expect(find.text('Back for a closer look'), findsOneWidget);
      expect(find.text('Not to be confused with ${b.name}'), findsOneWidget);
      expect(find.text('Guess first'), findsNothing);
      expect(maps.last.hit?.geometry, b.geometry);
      await tester.enterText(find.byType(TextField), ' by the bakery ');
      await tapThrough(tester, find.text('Got it'));
      final card = (await dao.card(item(a)))!;
      expect((card.phase, card.note), (CardPhase.relearning, 'by the bakery'));
      expect(card.lapses, LearningConfig.leechLapses);
    });

    testWidgets('the family sweep grades each lane\'s pin card and saves '
        'the swapped pair', (tester) async {
      for (final lane in lanes) {
        await dao.putCard(reviewed(item(lane)));
      }
      await pump(
        tester,
        [(kind: StepKind.familySweep, itemId: item(sweepParent))],
        drills: Drills(
          sweep: (
            parentId: sweepParent.id,
            children: [for (final lane in lanes) item(lane)],
          ),
        ),
      );
      expect(find.text('Put its lanes in order'), findsOneWidget);
      expect(find.text('Check · 0 of 2 placed'), findsOneWidget);
      final session = controller(tester);
      session
        ..placeLane(lanes[0].id, lanes[1].id)
        ..placeLane(lanes[1].id, lanes[0].id);
      await settle(tester);
      await tapThrough(tester, find.text('Check · 2 of 2 placed'));
      expect(find.text('0 of 2 in the right place.'), findsOneWidget);
      final log = await dao.log();
      expect(log.map((e) => (e.format, e.rating)).toSet(), {
        (ReviewFormat.familySweep, Rating.again),
      });
      expect(await db.select(db.confusions).get(), hasLength(2));
      expect((await dao.card(item(lanes[0])))!.phase, CardPhase.relearning);
    });

    testWidgets('the crossings drill logs each name and moves no card', (
      tester,
    ) async {
      final asked = crossings.skip(1).take(2).toList();
      await pump(
        tester,
        [(kind: StepKind.crossings, itemId: item(avenue))],
        drills: Drills(
          crossings: (
            streetId: avenue.id,
            fromId: crossings.first.street.id,
            crossings: [for (final c in asked) c.street.id],
          ),
        ),
      );
      expect(find.text('Name the streets you cross on'), findsOneWidget);
      expect(find.text('Crossing 1 of 2'), findsOneWidget);
      await tester.enterText(find.byType(TextField), asked.first.street.name);
      await settle(tester);
      await tapThrough(tester, find.text('Next crossing'));
      await tester.enterText(find.byType(TextField), 'qqqqqq');
      await settle(tester);
      await tapThrough(tester, find.text('Next crossing'));
      expect(find.text('You named 1 of 2.'), findsOneWidget);
      final log = await dao.log();
      expect(log.map((e) => (e.format, e.rating)), [
        (ReviewFormat.crossings, Rating.good),
        (ReviewFormat.crossings, Rating.again),
      ]);
      expect(await dao.cards(), isEmpty);
      await tapThrough(tester, find.text('Next'));
      expect(find.text('Session done'), findsOneWidget);
    });

    testWidgets('a bearing from the centre: turn, Check, the angle off', (
      tester,
    ) async {
      await pump(tester, [(kind: StepKind.bearing, itemId: item(c))]);
      expect(find.textContaining('which way is ${c.name}?'), findsOneWidget);
      final task = (await tester.runAsync(() async {
        final s = ProviderScope.containerOf(
          tester.element(find.byType(SessionScreen)),
        ).read(sessionControllerProvider);
        return (s as SessionPlaying).task as BearingTask;
      }))!;
      controller(tester).turn(task.trueBearing + 10);
      await settle(tester);
      await tapThrough(tester, find.text('Check'));
      expect(find.text('Great! · 10° off'), findsOneWidget);
      final row = (await dao.log()).single;
      expect((row.format, row.rating), (ReviewFormat.bearing, Rating.good));
      expect(await dao.cards(), isEmpty);
    });
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
