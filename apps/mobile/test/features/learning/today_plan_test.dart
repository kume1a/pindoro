import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/features/learning/data/carry_over.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/today_plan.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

Street _part(String id, double lengthM) {
  const at = LatLng(41.7, 44.8);
  return Street(
    id: id,
    nameKa: id.substring(0, 1),
    nameEn: null,
    roadClass: 'residential',
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

  // Street a has two parts; its card is keyed by the shorter one.
  final a = NamedStreet([_part('a1', 300), _part('a2', 120)]);
  final b = NamedStreet([_part('b1', 200)]);
  final c = NamedStreet([_part('c1', 180)]);

  setUp(() async {
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
        curriculumProvider.overrideWith(
          (ref) async => Curriculum(
            streets: [a, b, c],
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

  test('a street carded under another of its parts is not new again', () async {
    final p = await plan();
    expect(
      p.steps.where((s) => s.kind == StepKind.intro).map((s) => s.itemId),
      ['P:b1', 'P:c1'],
    );
  });

  test('Learn 5 more plans new streets past the daily number', () async {
    container.listen(learnMorePlanProvider, (_, _) {});
    final p = await container.read(learnMorePlanProvider.future);
    expect(p.newCount, 2);
    expect(p.backlog, isFalse);
  });

  test('takes the minutes a day from settings', () async {
    final p = await plan();
    expect(p.estimatedS, 12 + 2 * 45);
    expect(p.backlog, isFalse);
  });

  test('new streets come from the pack’s curriculum', () async {
    final pack = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => now),
        packRepositoryProvider.overrideWith((ref) async {
          final repo = SqlitePackRepository.open(AppConfig.fixturePackAsset);
          ref.onDispose(repo.close);
          return repo;
        }),
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
