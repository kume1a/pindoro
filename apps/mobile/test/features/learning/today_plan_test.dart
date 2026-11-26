import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/features/learning/data/cards.dart';
import 'package:pindoro/features/learning/data/carry_over.dart';
import 'package:pindoro/features/learning/data/day.dart';
import 'package:pindoro/features/learning/data/drive_history.dart';
import 'package:pindoro/features/learning/data/explore.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/route_book.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/learning/data/today_plan.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

Street _part(String id, double lengthM, {String roadClass = 'residential'}) {
  const at = LatLng(41.7, 44.8);
  return Street(
    id: id,
    nameKa: id.substring(0, 1),
    nameEn: null,
    roadClass: roadClass,
    difficulty: Difficulty.expert,
    lengthM: lengthM,
    midpoint: at,
    bbox: const Bbox(41.7, 44.8, 41.7, 44.8),
    geometry: const [
      [at, at],
    ],
  );
}

void main() {
  final now = DateTime(2026, 3, 2, 9);
  late AppDatabase db;
  late ProviderContainer container;
  // Streets only the curriculum knows: a main road makes its class the taught one.
  var curriculumOnly = <NamedStreet>[];
  // The player's routes (SPEC §16.23 item 120).
  var yours = (routes: const <String>{}, streets: const <String>[]);

  // Street a has two parts; its card is keyed by the shorter one.
  final a = NamedStreet([_part('a1', 300), _part('a2', 120)]);
  final b = NamedStreet([_part('b1', 200)]);
  final c = NamedStreet([_part('c1', 180)]);
  final fixturePack = packRepositoryProvider.overrideWith((ref) async {
    final repo = SqlitePackRepository.open(AppConfig.fixturePackAsset);
    ref.onDispose(repo.close);
    return repo;
  });

  setUp(() async {
    curriculumOnly = [];
    yours = (routes: const <String>{}, streets: const <String>[]);
    db = AppDatabase(NativeDatabase.memory());
    final dao = LearningDao(db);
    for (final id in ['P:a2', 'P:gone']) {
      await dao.putCard(
        CardState(
          itemId: id,
          phase: CardPhase.review,
          memory: Memory(
            stability: 3,
            difficulty: 5,
            lastReview: now.subtract(const Duration(days: 3)),
          ),
          dueAt: now.subtract(const Duration(hours: 1)),
        ),
      );
    }
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => now),
        fixturePack,
        cityStreetsProvider.overrideWith(
          (ref) async => {
            for (final s in [a, b, c])
              for (final p in s.parts) p.id: s,
          },
        ),
        newCandidatesProvider.overrideWith(
          (ref, _) async => ['P:a1', 'P:b1', 'P:c1'],
        ),
        carryOverProvider.overrideWith((ref) async {}),
        routeBookProvider.overrideWith(
          (ref) async => (
            candidates: const <RouteCandidate>[],
            questions: const <String, RouteQuestion>{},
          ),
        ),
        runsProvider.overrideWith((ref) async => const <Run>[]),
        yourRouteItemsProvider.overrideWith((ref) async => yours),
        curriculumProvider.overrideWith(
          (ref) async => Curriculum(
            streets: [a, b, c, ...curriculumOnly],
            districts: const [],
            centre: const LatLng(41.7, 44.8),
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<SessionPlan> plan() {
    container.listen(todayPlanProvider, (_, _) {});
    return container.read(todayPlanProvider.future);
  }

  test(
    "plans over this city's cards: other streets' cards are skipped",
    () async {
      final p = await plan();
      expect(p.dueCount, 1);
      expect(
        p.steps.where((s) => s.kind == StepKind.review).map((s) => s.itemId),
        ['P:a2'],
      );
    },
  );

  test('a card the pack no longer asks is never due: clearing the rest '
      'counts the day', () async {
    await LearningDao(db).saveAnswer(
      card: CardState(
        itemId: 'P:a2',
        phase: CardPhase.review,
        memory: Memory(stability: 5, difficulty: 5, lastReview: now),
        dueAt: now.add(const Duration(days: 5)),
      ),
      log: LogEntry(
        ts: now,
        itemId: 'P:a2',
        format: ReviewFormat.review,
        rating: Rating.good,
        source: ReviewSource.session,
      ),
    );
    final markDay = FutureProvider<void>(markDayIfCounts);
    await container.read(markDay.future);
    expect((await ProgressDao(db).goalDayRounds()).keys, [calendarDay(now)]);
  });

  test('while main roads are taught, a residential card waits: never due, '
      'and the day counts without it', () async {
    curriculumOnly = [
      NamedStreet([_part('m1', 400, roadClass: 'primary')]),
    ];
    await LearningDao(db).saveAnswer(
      card: CardState(
        itemId: 'P:c1',
        phase: CardPhase.review,
        memory: Memory(stability: 5, difficulty: 5, lastReview: now),
        dueAt: now.add(const Duration(days: 5)),
      ),
      log: LogEntry(
        ts: now,
        itemId: 'P:c1',
        format: ReviewFormat.review,
        rating: Rating.good,
        source: ReviewSource.session,
      ),
    );
    final p = await plan();
    expect(p.dueCount, 0);
    expect(p.steps.where((s) => s.kind == StepKind.review), isEmpty);
    final markDay = FutureProvider<void>(markDayIfCounts);
    await container.read(markDay.future);
    expect((await ProgressDao(db).goalDayRounds()).keys, [calendarDay(now)]);
  });

  test('a street carded under another of its parts is not new again', () async {
    final p = await plan();
    expect(
      p.steps.where((s) => s.kind == StepKind.intro).map((s) => s.itemId),
      ['P:b1', 'P:c1'],
    );
  });

  test(
    'a street of the player’s routes comes first, and is never parked',
    () async {
      yours = (routes: const {'J:x'}, streets: [c.id]);
      curriculumOnly = [
        NamedStreet([_part('main', 900, roadClass: 'primary')]),
      ];
      final p = await plan();
      expect(
        p.steps.where((s) => s.kind == StepKind.intro).map((s) => s.itemId),
        ['P:c1', 'P:b1'],
      );
      final curriculum = await container.read(curriculumProvider.future);
      final cards = [
        CardState(itemId: 'P:c1', phase: CardPhase.review, introAt: now),
      ];
      bool reviewed(Iterable<String> mine) => reviewsOf(
        (_) => true,
        streets: {
          for (final s in [a, b, c]) s.id: s,
        },
        curriculum: curriculum,
        cards: cards,
        yours: mine,
      )(cards.single);
      expect(reviewed(const []), isFalse, reason: 'residential waits for main');
      expect(reviewed([c.id]), isTrue);
    },
  );

  test('cards are keyed by street, whichever part they were made on', () async {
    final byPart = {
      for (final s in [a, b, c])
        for (final p in s.parts) p.id: s,
    };
    final cards = await LearningDao(db).cards();
    expect(streetCardsOf(byPart, cards).keys, [a.id]);
    expect(
      cardsByItemOf(byPart, cards).keys,
      unorderedEquals(['P:${a.id}', 'P:gone']),
    );
  });

  test('of two cards on one street, the one on its own id wins, and the other '
      'is never reviewed', () async {
    final byPart = {
      for (final s in [a, b, c])
        for (final p in s.parts) p.id: s,
    };
    const onPart = CardState(itemId: 'P:a2', phase: CardPhase.review);
    const own = CardState(itemId: 'P:a1', phase: CardPhase.review);
    for (final cards in [
      [own, onPart],
      [onPart, own],
    ]) {
      expect(streetCardsOf(byPart, cards)[a.id], same(own));
      expect(cardsByItemOf(byPart, cards)['P:a1'], same(own));
    }
    final reviews = reviewsOf(
      (_) => true,
      streets: byPart,
      curriculum: await container.read(curriculumProvider.future),
      cards: const [onPart, own],
    );
    expect(reviews(own), isTrue);
    expect(reviews(onPart), isFalse, reason: 'it would stay due for good');
  });

  test('an Explore pin reviews the card on the street’s own id', () async {
    await LearningDao(
      db,
    ).putCard(const CardState(itemId: 'P:a1', phase: CardPhase.review));
    final roundId = await ProgressDao(db).startRound(
      cityId: 'tbilisi',
      area: const DistrictsArea({'vake'}),
      difficulty: Difficulty.expert,
      packVersion: '1',
      streetIds: [a.id],
    );
    final explore = FutureProvider<void>(
      (ref) => learnFromExplore(
        ref,
        street: a,
        pin: a.parts.first.midpoint,
        rtMs: 3000,
        roundId: roundId,
      ),
    );
    await container.read(explore.future);
    expect((await LearningDao(db).log()).single.itemId, 'P:a1');
  });

  test('cards made on two parts of one street ask it once', () async {
    await LearningDao(db).putCard(
      CardState(
        itemId: 'P:a1',
        phase: CardPhase.review,
        memory: Memory(
          stability: 3,
          difficulty: 5,
          lastReview: now.subtract(const Duration(days: 3)),
        ),
        dueAt: now.subtract(const Duration(hours: 1)),
      ),
    );
    final p = await plan();
    expect(p.dueCount, 1);
    expect(p.steps.where((s) => s.kind == StepKind.review), hasLength(1));
  });

  test('an Explore pin reviews the card made on another part of its street, '
      'not a new one', () async {
    final roundId = await ProgressDao(db).startRound(
      cityId: 'tbilisi',
      area: const DistrictsArea({'vake'}),
      difficulty: Difficulty.expert,
      packVersion: '1',
      streetIds: [a.id],
    );
    final explore = FutureProvider<void>(
      (ref) => learnFromExplore(
        ref,
        street: a,
        pin: a.parts.first.midpoint,
        rtMs: 3000,
        roundId: roundId,
      ),
    );
    await container.read(explore.future);
    final dao = LearningDao(db);
    expect(
      (await dao.cards()).map((card) => card.itemId),
      unorderedEquals(['P:a2', 'P:gone']),
    );
    expect((await dao.log()).single.itemId, 'P:a2');
  });

  test('Learn 10 more plans new streets past the daily number', () async {
    container.listen(learnMorePlanProvider, (_, _) {});
    final p = await container.read(learnMorePlanProvider.future);
    expect(p.newCount, 2);
    expect(p.backlog, isFalse);
  });

  test('a small day fits one round', () async {
    final p = await plan();
    expect(p.rounds.single, isNotEmpty);
    expect(p.backlog, isFalse);
  });

  test('new streets come from the pack’s curriculum', () async {
    final pack = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => now),
        fixturePack,
      ],
    );
    addTearDown(pack.dispose);
    final count = LearningConfig.newPerDay[20]!;
    pack.listen(newCandidatesProvider(count), (_, _) {});
    final candidates = await pack.read(newCandidatesProvider(count).future);
    final streets = await pack.read(cityStreetsProvider.future);
    expect(candidates, hasLength(count));
    expect(candidates.every((id) => streets.containsKey(itemKey(id))), isTrue);
  });
}
