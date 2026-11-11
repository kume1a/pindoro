import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/features/pack/data/pack_store.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// The player's [BadgeStats], read fresh from the database and the installed
/// packs of played cities: an end screen awards right after its play was
/// saved, before any provider reloads. Never loads or downloads a pack.
Future<BadgeStats> readBadgeStats(ProgressDao dao, PackStore store) async {
  final counts = await dao.badgeCounts();
  final raions = [
    for (final city in await dao.recentCityIds())
      ?await readInstalledPack(store, city, (pack, streets) async {
        final ids = {
          for (final d in pack.districts())
            if (d.kind == DistrictKind.district) d.id,
        };
        final known = (await dao.knownIn(pack, streets)).byDistrict;
        final inRaions = [
          for (final MapEntry(:key, :value) in known.entries)
            if (ids.contains(key)) value,
        ];
        return (
          mastered: inRaions
              .where((c) => c.total > 0 && c.known >= c.total)
              .length,
          known: inRaions.where((c) => c.known > 0).length,
        );
      }),
  ];
  final days = (await dao.goalDayRounds()).keys.toSet();
  return (
    pins: counts.pins,
    perfects: counts.perfects,
    bestStreak: streakOf(days, calendarDay(DateTime.now())).best,
    masteredDistricts: raions.fold(0, (sum, r) => sum + r.mastered),
    knownDistricts: raions.fold(0, (most, r) => max(most, r.known)),
    roadTrips: await dao.roadTrips(),
    lateAnswer: counts.lateAnswer,
    pitStopCleared: counts.pitStopCleared,
  );
}

/// Saves every badge earned now that wasn't saved yet; returns those, in
/// shelf order.
typedef AwardBadges = Future<List<BadgeId>> Function();

final awardBadgesProvider = Provider<AwardBadges>(
  (ref) => () async {
    final dao = ref.read(progressDaoProvider);
    final stats = await readBadgeStats(dao, ref.read(packStoreProvider));
    return dao.earn([
      for (final id in BadgeId.values)
        if (badgeProgress(id, stats).earned) id,
    ], DateTime.now());
  },
);

/// A badge on Me's shelf. [earned] is saved, or reached now (the award that
/// saves it may still be running).
typedef BadgeView = ({BadgeId id, BadgeProgress progress, bool earned});

final badgesProvider = FutureProvider.autoDispose<List<BadgeView>>((ref) async {
  ref.watch(progressChangesProvider);
  final dao = ref.watch(progressDaoProvider);
  final stats = await readBadgeStats(dao, ref.watch(packStoreProvider));
  final saved = await dao.earnedBadges();
  return [
    for (final id in BadgeId.values)
      if (badgeProgress(id, stats) case final progress)
        (
          id: id,
          progress: progress,
          earned: saved.containsKey(id) || progress.earned,
        ),
  ];
});

/// The earned badges Me shows as New on this visit, marked seen as they are
/// taken. The tab shell invalidates it each time the Me tab opens.
final newBadgesProvider = FutureProvider.autoDispose<Set<BadgeId>>(
  (ref) => ref.read(progressDaoProvider).takeUnseenBadges(DateTime.now()),
);
