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
import 'package:pindoro/features/learning/data/route_book.dart';
import 'package:pindoro/features/learning/data/today_plan.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/ui/explore_map.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/reminders.dart';
import 'package:pindoro/features/session/ui/session_controller.dart';
import 'package:pindoro/features/session/ui/session_screen.dart';
import 'package:pindoro/features/session/ui/widgets/task_scaffold.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart' show AnswerTray;
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

  /// A street crossing [a].
  late NamedStreet parent;
  late NamedStreet child;

  /// A family with two children, for the sweep.
  late NamedStreet sweepParent;
  late List<NamedStreet> lanes;

  /// A street crossed by at least three others, in order.
  late NamedStreet avenue;
  late List<Crossing> crossings;

  /// The Vake pack's route items, and its junctions' OSM nodes.
  late RouteBook routes;
  late Map<int, int> nodes;

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
    nodes = repo.junctionNodes();
    routes = buildRouteBook(
      graph: repo.roadGraph()!,
      junctionNodes: repo.junctionNodes(),
      items: repo.junctionItems(),
      landmarks: repo.landmarks(),
      bridges: repo.bridges(),
      streets: byPart,
      curriculum: Curriculum(
        streets: byPart.values,
        districts: repo.districts(),
        centre: repo.city().center,
        families: repo.families(),
      ),
    );
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
    List<List<SessionStep>>? rounds,
    List<List<SessionStep>> more = const [],
    bool ticking = false,
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
          clockProvider.overrideWithValue(
            () =>
                ticking ? now = now.add(const Duration(milliseconds: 1)) : now,
          ),
          exploreMapBuilderProvider.overrideWithValue(
            (_) => const SizedBox.expand(),
          ),
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
              rounds: rounds ?? [if (steps.isNotEmpty) steps],
              dueCount: 0,
              backlog: false,
              reviewCount: 0,
              newCount: 1,
              drills: drills,
            ),
          ),
          learnMorePlanProvider.overrideWith(
            (ref) async => SessionPlan(
              rounds: more,
              dueCount: 0,
              backlog: false,
              reviewCount: 0,
              newCount: 1,
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
    String? note,
  }) => CardState(
    itemId: itemId,
    note: note,
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

  testWidgets('the next review counts whole days from the review, however '
      'long its save takes', (tester) async {
    await pump(tester, [
      (kind: StepKind.intro, itemId: item(a)),
      (kind: StepKind.retrieval1, itemId: item(a)),
    ], ticking: true);
    await tapThrough(tester, find.text('Got it'));
    await answer(tester, onStreet(a));
    expect(find.text('Next review in 2 days'), findsOneWidget);
  });

  testWidgets('"I don’t know" on a pin: a miss with no pin or distance, the '
      'street shown, back in this session', (tester) async {
    await pump(tester, [
      (kind: StepKind.intro, itemId: item(a)),
      (kind: StepKind.retrieval1, itemId: item(a)),
    ]);
    await tapThrough(tester, find.text('Got it'));
    // A pin dropped before "I don't know" isn't shown on its reveal.
    maps.last.onTap!(onStreet(a));
    await settle(tester);
    await tapThrough(tester, find.text('I don’t know'));
    expect(find.text('Didn’t know'), findsOneWidget);
    expect(maps.last.truth, a.geometry);
    expect((maps.last.pin, maps.last.measure), (null, null));
    expect(find.text('Back in this session'), findsOneWidget);
    final row = (await dao.log()).single;
    expect((row.rating, row.distanceM), (Rating.again, null));
  });

  testWidgets('a double tap on Got it introduces one street, not the next', (
    tester,
  ) async {
    await pump(tester, [
      (kind: StepKind.intro, itemId: item(a)),
      (kind: StepKind.intro, itemId: item(b)),
    ]);
    await tester.runAsync(() async {
      await tester.tap(find.text('Got it'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    // The second tap lands on the next intro's sheet as it rises in.
    await tester.tap(find.text('Got it'), warnIfMissed: false);
    await settle(tester);
    expect(find.text('New street · 2 of 2'), findsOneWidget);
    expect(await dao.card(item(b)), isNull);
  });

  testWidgets('a day in rounds: each ends on its own summary, Next round '
      'goes on, the last offers no more', (tester) async {
    await pump(
      tester,
      const [],
      rounds: [
        [(kind: StepKind.retrieval1, itemId: item(a))],
        [(kind: StepKind.retrieval1, itemId: item(b))],
      ],
    );
    expect(find.text('Round 1 of 2'), findsOneWidget);
    // Inside the city, so no toast covers the round's buttons.
    await answer(tester, a.parts.first.midpoint);
    await tapThrough(tester, find.text('Next'));
    expect(find.text('Round 1 of 2 done'), findsOneWidget);
    expect(
      find.textContaining('cleared'),
      findsNothing,
      reason: 'more to come',
    );
    expect(find.text('Done for now'), findsOneWidget);

    await tapThrough(tester, find.text('Next round'));
    expect(find.text('Round 2 of 2'), findsOneWidget);
    await answer(tester, b.parts.first.midpoint);
    await tapThrough(tester, find.text('Next'));
    expect(find.text('Session done'), findsOneWidget);
    expect(find.text('Next round'), findsNothing);
  });

  testWidgets('Learn 10 more after the last round starts over in place, at '
      'its own round 1', (tester) async {
    await pump(
      tester,
      const [],
      rounds: [
        [(kind: StepKind.retrieval1, itemId: item(a))],
        [(kind: StepKind.retrieval1, itemId: item(b))],
      ],
      more: [
        [(kind: StepKind.retrieval1, itemId: item(c))],
        [(kind: StepKind.retrieval1, itemId: item(parent))],
      ],
    );
    for (final s in [a, b]) {
      await answer(tester, s.parts.first.midpoint);
      await tapThrough(tester, find.text('Next'));
      if (s == a) await tapThrough(tester, find.text('Next round'));
    }
    await tapThrough(tester, find.text('Learn 10 more'));
    expect(find.byType(SessionScreen), findsOneWidget);
    expect(find.text('Round 1 of 2'), findsOneWidget);
    await answer(tester, c.parts.first.midpoint);
    await tapThrough(tester, find.text('Next'));
    expect(find.text('Round 1 of 2 done'), findsOneWidget);
    final log = await dao.log();
    expect(log.map((e) => e.sessionId).toSet(), hasLength(2));
  });

  testWidgets('a double tap on Confirm answers once', (tester) async {
    await pump(tester, [(kind: StepKind.retrieval1, itemId: item(a))]);
    maps.last.onTap!(a.parts.first.midpoint);
    await settle(tester);
    final session = controller(tester);
    await tester.runAsync(
      () => Future.wait([session.confirm(), session.confirm()]),
    );
    await settle(tester);
    expect(await dao.log(), hasLength(1));
  });

  testWidgets('the relearn cap counts the whole session, not each round', (
    tester,
  ) async {
    final miss = LatLng(onStreet(a).lat + 0.02, onStreet(a).lon);
    await dao.putCard(reviewed(item(a)));
    await pump(
      tester,
      const [],
      rounds: [
        [(kind: StepKind.review, itemId: item(a))],
        [(kind: StepKind.review, itemId: item(a))],
      ],
    );
    for (final chip in ['Back in this session', 'Back in this session']) {
      await answer(tester, miss);
      expect(find.text(chip), findsOneWidget);
      await tapThrough(tester, find.text('Got it'));
    }
    await answer(tester, miss);
    expect(find.text('Back in this session'), findsNothing);
    await tapThrough(tester, find.text('Got it'));
    await tapThrough(tester, find.text('Next round'));
    await answer(tester, miss);
    expect(find.text('Back in this session'), findsNothing);
  });

  testWidgets('Done for now leaves between rounds', (tester) async {
    await pump(
      tester,
      const [],
      rounds: [
        [(kind: StepKind.retrieval1, itemId: item(a))],
        [(kind: StepKind.retrieval1, itemId: item(b))],
      ],
    );
    await answer(tester, a.parts.first.midpoint);
    await tapThrough(tester, find.text('Next'));
    await tapThrough(tester, find.text('Done for now'));
    expect(find.byType(SessionScreen), findsNothing);
    expect((await dao.log()).map((e) => e.itemId), [item(a)]);
  });

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
    expect(maps.last.hit, b.geometry);
    expect(maps.last.measure, isNull);
    final pair = await db.select(db.confusions).getSingle();
    expect(pair.count, 2);
    expect((await dao.log()).single.snapId, b.id);
  });

  testWidgets('places are named while asking but streets only on the '
      'reveal', (tester) async {
    await pump(tester, [(kind: StepKind.retrieval1, itemId: item(a))]);
    expect(find.textContaining('Round'), findsNothing, reason: 'one round');
    expect(
      maps.last.names,
      MapNames(places: true, placesNot: nameStems(a)),
      reason: 'no street, no place named after the street',
    );
    await answer(tester, onStreet(a));
    expect(maps.last.names, MapNames.all);
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
    expect(maps.last.names.streets, isEmpty);
    maps.last.onTap!(onStreet(child));
    await settle(tester);
    await tapThrough(tester, find.text('Confirm guess'));

    expect((await dao.log()).single.format, ReviewFormat.pretest);
    expect(await dao.card(item(child)), isNull);
    expect(find.textContaining('Family: ${parent.name}'), findsOneWidget);
    expect(maps.last.names, MapNames.all);
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
    testWidgets('a name card picks among six names, then saves the check', (
      tester,
    ) async {
      await pump(tester, [(kind: StepKind.review, itemId: 'N:${a.id}')]);
      expect(find.text('Which street is painted yellow?'), findsOneWidget);
      expect(find.text('6 names'), findsOneWidget);
      expect(maps.last.truth, a.geometry, reason: 'the street is the cue');
      await tester.ensureVisible(find.text(a.name).last);
      await tester.pump();
      await tester.tap(find.text(a.name).last);
      await tester.pump();
      await confirmTray(tester);
      expect(find.text('It’s ${a.name}.'), findsOneWidget);
      expect(find.textContaining('Next review in'), findsOneWidget);
      final row = (await dao.log()).single;
      expect((row.format, row.rating), (ReviewFormat.nameCheck, Rating.good));
      expect((await dao.card('N:${a.id}'))!.phase, CardPhase.review);
    });

    testWidgets('"I don’t know" on a name card shows the name, Again', (
      tester,
    ) async {
      await pump(tester, [(kind: StepKind.review, itemId: 'N:${a.id}')]);
      await tester.ensureVisible(find.text('I don’t know'));
      await tapThrough(tester, find.text('I don’t know'));
      expect(find.text('It’s ${a.name}.'), findsOneWidget);
      expect(find.text('Did you know it?'), findsOneWidget);
      expect(maps.last.names, MapNames.all, reason: 'revealed: every name');
      final row = (await dao.log()).single;
      expect((row.format, row.rating), (ReviewFormat.nameCheck, Rating.again));
      expect(await dao.confusionPairs(), isEmpty);
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

    testWidgets('both ends: asked without places named after the street; '
        '"I don’t know" after one pin shows no pin', (tester) async {
      await pump(tester, [(kind: StepKind.review, itemId: 'E:${a.id}')]);
      expect(maps.last.names, MapNames(places: true, placesNot: nameStems(a)));
      maps.last.onTap!(streetEnds(a).$1);
      await settle(tester);
      await tapThrough(tester, find.text('I don’t know'));
      expect(maps.last.truth, a.geometry);
      expect(maps.last.pin, isNull);
      expect(maps.last.morePins, isEmpty);
      expect((await dao.log()).single.rating, Rating.again);
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
      expect(maps.last.hit, b.geometry);
      await tester.enterText(find.byType(TextField), ' by the bakery ');
      await tapThrough(tester, find.text('Got it'));
      final card = (await dao.card(item(a)))!;
      expect((card.phase, card.note), (CardPhase.relearning, 'by the bakery'));
      expect(card.lapses, LearningConfig.leechLapses);
    });

    testWidgets('two leeches in a row each keep their own note', (
      tester,
    ) async {
      for (final (street, note) in [(a, 'by the bakery'), (b, 'one way up')]) {
        await dao.putCard(
          reviewed(
            item(street),
            stability: 1,
            daysAgo: 1,
            phase: CardPhase.suspended,
            lapses: LearningConfig.leechLapses,
            note: note,
          ),
        );
      }
      await pump(tester, [
        (kind: StepKind.intro, itemId: item(a)),
        (kind: StepKind.intro, itemId: item(b)),
      ]);
      expect(find.text('by the bakery'), findsOneWidget);
      await tapThrough(tester, find.text('Got it'));
      expect(find.text('one way up'), findsOneWidget);
      await tapThrough(tester, find.text('Got it'));
      expect((await dao.card(item(a)))!.note, 'by the bakery');
      expect((await dao.card(item(b)))!.note, 'one way up');
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
      expect(find.text('0 of 2 placed'), findsOneWidget);
      final session = controller(tester);
      session
        ..placeLane(lanes[0].id, lanes[1].id)
        ..placeLane(lanes[1].id, lanes[0].id);
      await settle(tester);
      expect(find.text('2 of 2 placed'), findsOneWidget);
      await confirmTray(tester);
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

  group('M5 route cards', () {
    T first<T extends RouteQuestion>([bool Function(T)? test]) =>
        routes.questions.values.whereType<T>().firstWhere(test ?? (_) => true);

    testWidgets('a J card: the right exit is Right!; a wrong one comes back', (
      tester,
    ) async {
      final q = first<TurnQuestion>();
      final wrong = q.exits.keys.firstWhere((t) => t != q.correct);
      await pump(tester, [(kind: StepKind.review, itemId: q.itemId)]);
      expect(maps.last.hit, hasLength(1), reason: 'the approach, cobalt');
      expect(maps.last.names.streets, isEmpty, reason: 'no street named');
      expect(find.textContaining('Which way at'), findsOneWidget);
      controller(tester).choose(wrong);
      await settle(tester);
      await tapThrough(tester, find.text('Confirm'));
      expect(find.text('Not this one'), findsOneWidget);
      expect(maps.last.truth, hasLength(2), reason: 'approach and right exit');
      expect(find.text('Back in this session'), findsOneWidget);
      await tapThrough(tester, find.text('Next'));
      controller(tester).choose(q.correct);
      await settle(tester);
      await tapThrough(tester, find.text('Confirm'));
      expect(find.text('Right!'), findsOneWidget);
      final log = await dao.log();
      expect(log.map((e) => (e.format, e.rating)), [
        (ReviewFormat.junction, Rating.again),
        (ReviewFormat.junction, Rating.good),
      ]);
    });

    testWidgets('"I don’t know" on a J card shows the way, Again', (
      tester,
    ) async {
      final q = first<TurnQuestion>();
      await pump(tester, [(kind: StepKind.review, itemId: q.itemId)]);
      // The right exit picked first doesn't make "I don't know" read Right!
      controller(tester).choose(q.correct);
      await settle(tester);
      await tapThrough(tester, find.text('I don’t know'));
      expect(find.text('Not this one'), findsOneWidget);
      expect(maps.last.truth, hasLength(2), reason: 'approach and right exit');
      final row = (await dao.log()).single;
      expect((row.format, row.rating), (ReviewFormat.junction, Rating.again));
    });

    testWidgets('a typed street is not carried to the next route card', (
      tester,
    ) async {
      final q = first<ConnectionQuestion>();
      final next = first<ConnectionQuestion>((o) => o.itemId != q.itemId);
      await pump(tester, [
        (kind: StepKind.review, itemId: q.itemId),
        (kind: StepKind.review, itemId: next.itemId),
      ]);
      await tester.enterText(find.byType(TextField), q.to.name);
      await settle(tester);
      await tapThrough(tester, find.text('Check'));
      await tapThrough(tester, find.text('Next'));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });

    testWidgets('a card missed again and again comes back twice, then waits '
        'for another day', (tester) async {
      final q = first<TurnQuestion>();
      final wrong = q.exits.keys.firstWhere((t) => t != q.correct);
      await pump(tester, [(kind: StepKind.review, itemId: q.itemId)]);
      for (final chip in [
        'Back in this session',
        'Back in this session',
        'Next review in 1 day',
      ]) {
        controller(tester).choose(wrong);
        await settle(tester);
        await tapThrough(tester, find.text('Confirm'));
        expect(find.text(chip), findsOneWidget);
        await tapThrough(tester, find.text('Next'));
      }
      expect(find.text('Session done'), findsOneWidget);
      expect((await dao.log()).length, 3);
    });

    testWidgets('a gateway: the pin at the junction and the street typed', (
      tester,
    ) async {
      final q = first<GatewayQuestion>((q) => q.exitStreet != null);
      await pump(tester, [(kind: StepKind.review, itemId: q.itemId)]);
      expect(find.text(q.out ? 'Way out of' : 'Way into'), findsOneWidget);
      maps.last.onTap!(q.at);
      await settle(tester);
      await tester.enterText(find.byType(TextField), q.exitStreet!.name);
      await tapThrough(tester, find.text('Confirm'));
      final row = (await dao.log()).single;
      expect((row.format, row.rating), (ReviewFormat.gateway, Rating.good));
    });

    testWidgets('a connection: type the street at the other end', (
      tester,
    ) async {
      final q = first<ConnectionQuestion>();
      await pump(tester, [(kind: StepKind.review, itemId: q.itemId)]);
      await tester.enterText(find.byType(TextField), q.to.name);
      await settle(tester);
      await tapThrough(tester, find.text('Check'));
      final row = (await dao.log()).single;
      expect((row.format, row.rating), (ReviewFormat.connection, Rating.good));
    });

    testWidgets('a landmark card: pick its junction', (tester) async {
      final q = first<LandmarkQuestion>((q) => q.n == 2);
      await pump(tester, [(kind: StepKind.review, itemId: q.itemId)]);
      expect(find.textContaining(q.landmark.name), findsWidgets);
      final tray = tester.widget<AnswerTray>(find.byType(AnswerTray));
      final right = tray.choices[q.junctions.indexOf(q.junction!)].label;
      await tester.ensureVisible(find.text(right));
      await tester.pump();
      await tester.tap(find.text(right));
      await tester.pump();
      await confirmTray(tester);
      final row = (await dao.log()).single;
      expect((row.format, row.rating), (ReviewFormat.landmark, Rating.good));
      expect((await dao.card(q.itemId))!.phase, CardPhase.review);
    });

    testWidgets('a new place is shown first, named with its street when a '
        'chain, then asked', (tester) async {
      final q = first<LandmarkQuestion>((q) => q.n == 1 && q.ambiguous);
      await pump(tester, [
        (kind: StepKind.intro, itemId: q.itemId),
        (kind: StepKind.retrieval1, itemId: q.itemId),
      ]);
      expect(find.text('New place · 1 of 1'), findsOneWidget);
      expect(find.textContaining('${q.landmark.name}, '), findsWidgets);
      expect(maps.last.truthPoint, q.landmark.at);
      expect(maps.last.names, MapNames.all);
      expect(find.bySemanticsLabel('Street View'), findsOneWidget);
      await tapThrough(tester, find.text('Got it'));
      expect((await dao.card(q.itemId))!.phase, CardPhase.learning);
      expect(find.text('Where is it?'), findsOneWidget);
      expect(maps.last.truthPoint, isNull, reason: 'asking shows nothing');
      expect(maps.last.names.places, isFalse);
      expect(
        maps.last.names.streets,
        isNot(contains(q.street!.name)),
        reason: 'the street in its name stays unnamed while asking',
      );

      final far = LatLng(q.landmark.at.lat + 0.01, q.landmark.at.lon);
      maps.last.onTap!(far);
      await settle(tester);
      await tapThrough(tester, find.text('Confirm'));
      expect(maps.last.truthPoint, q.landmark.at);
      expect(
        (maps.last.measure?.from, maps.last.measure?.to),
        (far, q.landmark.at),
      );
      expect(maps.last.names, MapNames.all);
      expect(find.bySemanticsLabel('Street View'), findsOneWidget);
      expect(find.text("Can't find it?"), findsOneWidget);
      final row = (await dao.log()).single;
      expect((row.format, row.rating), (ReviewFormat.landmark, Rating.again));
    });

    testWidgets('a second place of one name on its street is asked with its '
        'corner', (tester) async {
      final q = first<LandmarkQuestion>(
        (q) => q.n == 1 && q.crossStreet != null,
      );
      await pump(tester, [(kind: StepKind.retrieval1, itemId: q.itemId)]);
      expect(
        find.text(
          '${q.landmark.name}, ${q.street!.name} × ${q.crossStreet!.name}',
        ),
        findsOneWidget,
      );
    });

    testWidgets("a place the player can't find is hidden on the phone, its "
        'cards gone from the session', (tester) async {
      final q = first<LandmarkQuestion>(
        (q) => q.n == 1 && !q.landmark.personal,
      );
      await pump(tester, [
        (kind: StepKind.intro, itemId: q.itemId),
        (kind: StepKind.retrieval1, itemId: q.itemId),
      ]);
      await tapThrough(tester, find.text("Can't find it?"));
      await tapThrough(tester, find.text('Keep it'));
      expect(await dao.hiddenPlaces(), isEmpty, reason: 'kept');
      await tapThrough(tester, find.text("Can't find it?"));
      await tapThrough(tester, find.text('Hide it'));
      expect(await dao.hiddenPlaces(), {q.landmark.id});
      expect(await dao.card(q.itemId), isNull);
      expect(controller(tester).state, isA<SessionDone>());
      final book = await ProviderScope.containerOf(
        tester.element(find.byType(SessionScreen)),
      ).read(routeBookProvider.future);
      expect(
        book.questions.values.whereType<LandmarkQuestion>().where(
          (l) => l.landmark.id == q.landmark.id,
        ),
        isEmpty,
      );
    });
  });

  group('M6 recitals', () {
    testWidgets('typed street by street, graded against the best route; the '
        'turns it drives are evidence for their J cards', (tester) async {
      final q = routes.questions.values.whereType<TurnQuestion>().firstWhere(
        (q) =>
            q.approachStreet != null &&
            q.exitStreet != null &&
            q.approachStreet != q.exitStreet,
      );
      final from = q.approach.other(q.junction);
      final to = q.exits[q.correct]!.other(q.junction);
      final run = (
        id: runId(nodes[from]!, nodes[to]!),
        fromNode: nodes[from]!,
        toNode: nodes[to]!,
        random: true,
        items: [q.itemId],
        createdAt: now,
      );
      await dao.saveRun(run);
      await pump(tester, [
        (kind: StepKind.review, itemId: CardType.r.item(run.id)),
      ]);
      expect(find.text('By heart, no map'), findsOneWidget);
      expect(find.text('Check my route'), findsOneWidget);
      await tester.enterText(find.byType(TextField), q.exitStreet!.name);
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await settle(tester);
      expect(find.text('No street or landmark by that name'), findsNothing);
      expect(
        ((controller(tester).state as SessionPlaying).task as RecitalTask)
            .steps
            .single
            .street
            ?.id,
        q.exitStreet!.id,
      );
      await tapThrough(tester, find.text('Check my route'));
      expect(find.text('Next'), findsOneWidget);
      final log = await dao.log();
      expect(log.first.itemId, CardType.r.item(run.id));
      expect(log.first.format, ReviewFormat.recital);
      expect(await dao.card(CardType.r.item(run.id)), isNotNull);
      expect(await db.select(db.implicitEvidence).get(), isNotEmpty);
    });

    testWidgets('the next recital starts with an empty field', (tester) async {
      final turns = routes.questions.values.whereType<TurnQuestion>().toList();
      final runs = [
        for (final q in turns.take(2))
          (
            id: runId(
              nodes[q.approach.other(q.junction)]!,
              nodes[q.exits[q.correct]!.other(q.junction)]!,
            ),
            fromNode: nodes[q.approach.other(q.junction)]!,
            toNode: nodes[q.exits[q.correct]!.other(q.junction)]!,
            random: true,
            items: [q.itemId],
            createdAt: now,
          ),
      ];
      for (final run in runs) {
        await dao.saveRun(run);
      }
      await pump(tester, [
        for (final run in runs)
          (kind: StepKind.review, itemId: CardType.r.item(run.id)),
      ]);
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await settle(tester);
      expect(find.text('No street or landmark by that name'), findsOneWidget);
      await tapThrough(tester, find.text('I don’t know'));
      await tapThrough(tester, find.text('Next'));
      expect(find.text('No street or landmark by that name'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });

    testWidgets('drawn along the streets from A to B', (tester) async {
      final graph = SqlitePackRepository.open(AppConfig.fixturePackAsset);
      addTearDown(graph.close);
      final q = routes.questions.values.whereType<TurnQuestion>().first;
      final from = q.approach.other(q.junction);
      final to = q.exits[q.correct]!.other(q.junction);
      final run = (
        id: runId(nodes[from]!, nodes[to]!),
        fromNode: nodes[from]!,
        toNode: nodes[to]!,
        random: true,
        items: [q.itemId],
        createdAt: now,
      );
      await dao.saveRun(run);
      await pump(tester, [
        (kind: StepKind.review, itemId: CardType.r.item(run.id)),
      ]);
      await tapThrough(tester, find.text('Draw'));
      final task = (controller(tester).state as SessionPlaying).task;
      var draft = (task as RecitalTask).draft;
      final best = draft.graph.shortestRoute(task.from, {task.to})!;
      for (final e in best.edges) {
        draft = draft.take(e);
      }
      controller(tester).recitalDraw(draft);
      await settle(tester);
      await tapThrough(tester, find.text('Check my route'));
      expect(find.text('Perfect!'), findsOneWidget);
      expect((await dao.log()).single.rating, Rating.easy);
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

/// Confirms the answer tray's pick and waits out the right and wrong shown on
/// it before the reveal.
Future<void> confirmTray(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.text('Confirm'));
    await Future<void>.delayed(
      answerResultDelay + const Duration(milliseconds: 300),
    );
  });
  await settle(tester);
}
