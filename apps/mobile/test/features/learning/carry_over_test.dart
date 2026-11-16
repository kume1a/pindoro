import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/features/learning/data/carry_over.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

void main() {
  final now = DateTime(2026, 3, 2, 9);
  late AppDatabase db;
  late ProviderContainer container;
  late List<NamedStreet> streets;

  setUpAll(() {
    final pack = SqlitePackRepository.open(AppConfig.fixturePackAsset);
    streets = streetsByPartId(pack.streets()).values.toSet().toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    pack.close();
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
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
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// One old-game round answering [tiers] by street.
  Future<void> answered(Map<NamedStreet, Tier> tiers) async {
    final progress = ProgressDao(db);
    final round = await progress.startRound(
      cityId: AppConfig.defaultCityId,
      area: const DistrictsArea({AppConfig.fixtureDistrictId}),
      difficulty: Difficulty.medium,
      packVersion: 'v',
      streetIds: [for (final s in tiers.keys) s.id],
    );
    for (final MapEntry(key: street, value: tier) in tiers.entries) {
      await progress.recordAnswer(
        roundId: round,
        streetId: street.parts.last.id,
        pin: street.parts.first.midpoint,
        distanceM: 10,
        tier: tier,
        xp: 0,
        packVersion: 'v',
      );
    }
  }

  test('a street the old game knew becomes a prior-known card, once', () async {
    final [known, missed, learning, ...] = streets;
    await answered({
      known: Tier.great,
      missed: Tier.miss,
      learning: Tier.perfect,
    });
    final dao = LearningDao(db);
    final intro = introduce(CardType.p.item(learning.parts.last.id), now);
    await dao.putCard(intro);

    await container.read(carryOverProvider.future);
    final cards = await dao.cards();
    expect(cards.map((c) => c.itemId), {
      intro.itemId,
      CardType.p.item(known.id),
    });
    final carried = await dao.card(CardType.p.item(known.id));
    expect(carried!.priorKnown, isTrue);
    expect(carried.dueAt!.difference(now).inDays, inInclusiveRange(1, 7));

    container.invalidate(carryOverProvider);
    await container.read(carryOverProvider.future);
    expect(await dao.cards(), hasLength(2));
  });
}
