import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/pack/data/pack_store.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// The player's [BadgeStats], read fresh from the database and the packs of
/// played cities: an end screen awards right after its play was saved,
/// before any provider reloads. The [open] pack stands in for its city's
/// installed one, and gives City memory; never loads or downloads a pack.
Future<BadgeStats> readBadgeStats(
  ProgressDao dao,
  LearningDao learning,
  PackStore store, {
  OpenPack? open,
  DateTime? at,
}) async {
  final now = at ?? DateTime.now();
  final counts = await dao.badgeCounts();
  final allCards = await learning.cards();
  final cards = {
    for (final c in allCards)
      if (c.type == CardType.p) itemKey(c.itemId): c,
  };
  final pins = [
    for (final e in await learning.log())
      if (e.type == CardType.p &&
          e.source != ReviewSource.explore &&
          e.distanceM != null)
        e,
  ];
  final cities = await readCityPacks(
    () => store,
    await dao.recentCityIds(),
    open: open,
    (pack, streets) async {
      final areas = areaCounts(
        streets: streets.values,
        districts: pack.districts(),
        cards: cards,
        now: now,
      );
      final perfects = pins.where((e) {
        final street = streets[itemKey(e.itemId)];
        return street != null &&
            scoreAnswer(
                  e.distanceM!,
                  street.parts.first.roadClass,
                  Difficulty.medium,
                ) ==
                Tier.perfect;
      }).length;
      return (areas: areas, perfects: perfects);
    },
  );
  final days = (await dao.goalDayRounds()).keys.toSet();
  final openCore = open?.streets.values.toSet().where(Curriculum.isCore);
  return (
    pins: counts.pins,
    perfects:
        counts.perfects + cities.fold<int>(0, (sum, c) => sum + c.perfects),
    bestStreak: streakOf(days, calendarDay(now)).best,
    masteredDistricts: cities.fold(0, (sum, c) => sum + c.areas.masteredRaions),
    masteredNeighbourhoods: cities.fold(
      0,
      (sum, c) => sum + c.areas.masteredNeighbourhoods,
    ),
    knownDistricts: cities.fold(0, (most, c) => max(most, c.areas.knownRaions)),
    goalDays: counts.goalDays,
    leechesCleared: leechesCleared(allCards),
    lateAnswer: counts.lateAnswer,
    cityMemory: openCore == null
        ? 0
        : cityMemory(
            [for (final s in openCore) ?cards[s.id]],
            now,
            isCore: (_) => true,
          ).round(),
  );
}

/// The stored ids of every badge [stats] earn: the live badges, then each
/// City memory milestone reached.
List<String> earnedIds(BadgeStats stats) => [
  for (final id in BadgeId.values)
    if (!id.retired && badgeProgress(id, stats).earned) id.name,
  for (final m in cityMemoryMilestones(stats.cityMemory)) cityMemoryBadge(m),
];

/// Saves every badge earned now that wasn't saved yet; returns their stored
/// ids, in shelf order.
typedef AwardBadges = Future<List<String>> Function();

/// The open pack, unless it is the bundled Vake stand-in: badges count only
/// a city's real pack.
OpenPack? _badgePack(Ref ref) => switch (openPackOf(
  ref.read(packRepositoryProvider),
  ref.read(cityStreetsProvider),
)) {
  final open? when !isFixturePack(open.pack) => open,
  _ => null,
};

final awardBadgesProvider = Provider<AwardBadges>(
  (ref) => () async {
    final dao = ref.read(progressDaoProvider);
    final stats = await readBadgeStats(
      dao,
      ref.read(learningDaoProvider),
      ref.read(packStoreProvider),
      open: _badgePack(ref),
    );
    return dao.earn(earnedIds(stats), DateTime.now());
  },
);

/// A badge on Me's shelf by its stored id ([BadgeId] name or a City memory
/// milestone). [earned] is saved, or reached now (the award that saves it
/// may still be running).
typedef BadgeView = ({
  String id,
  BadgeProgress progress,
  bool earned,
  bool retired,
});

/// The shelf: the live badges, retired ones only when earned, then the
/// highest City memory milestone reached and the next one, locked.
final badgesProvider = FutureProvider.autoDispose<List<BadgeView>>((ref) async {
  ref.watch(progressChangesProvider);
  final dao = ref.watch(progressDaoProvider);
  final stats = await readBadgeStats(
    dao,
    ref.watch(learningDaoProvider),
    ref.watch(packStoreProvider),
    open: _badgePack(ref),
  );
  final saved = await dao.earnedBadges();
  final reached = {
    ...cityMemoryMilestones(stats.cityMemory),
    for (final id in saved.keys) ?cityMemoryBadgeTarget(id),
  };
  final top = reached.isEmpty ? null : reached.reduce(max);
  final next = nextCityMemoryMilestone(max(stats.cityMemory, top ?? 0));
  return [
    for (final id in BadgeId.values)
      if (!id.retired || saved.containsKey(id.name))
        if (badgeProgress(id, stats) case final progress)
          (
            id: id.name,
            progress: progress,
            earned: saved.containsKey(id.name) || progress.earned,
            retired: id.retired,
          ),
    if (top != null)
      (
        id: cityMemoryBadge(top),
        progress: (value: top, target: top),
        earned: true,
        retired: false,
      ),
    (
      id: cityMemoryBadge(next.target),
      progress: next,
      earned: false,
      retired: false,
    ),
  ];
});

/// The earned badges Me shows as New on this visit, marked seen as they are
/// taken. The tab shell invalidates it each time the Me tab opens.
final newBadgesProvider = FutureProvider.autoDispose<Set<String>>(
  (ref) => ref.read(progressDaoProvider).takeUnseenBadges(DateTime.now()),
);
