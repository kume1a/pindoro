import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/pack/data/pack_store.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro/features/progress/data/streak.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

typedef MeCity = ({
  String id,
  String nameKa,
  String nameEn,

  /// City memory (rounded) of the city's core streets.
  KnownCount count,
});

typedef MeData = ({
  /// When play began; null before any.
  DateTime? since,
  int bestStreak,

  /// Streets Known now (SPEC §8), in every city.
  int knownStreets,
  int pins,

  /// Days that counted towards the streak.
  int countedDays,

  /// The chosen city first, then the other played ones.
  List<MeCity> cities,
});

/// Me's numbers. Each city is counted in its own pack: the open one, or its
/// installed pack opened just for the count; a played city whose pack isn't
/// on the phone is left out. It doesn't wait for the open pack: until it
/// loads, the chosen city counts only if it has a pack installed.
final meProvider = FutureProvider.autoDispose<MeData>((ref) async {
  ref.watch(progressChangesProvider);
  final dao = ref.watch(progressDaoProvider);
  final now = ref.watch(clockProvider)();
  final open = openPackOf(
    ref.watch(packRepositoryProvider),
    ref.watch(cityStreetsProvider),
  );
  final streak = await ref.watch(streakProvider.future);
  final cards = {
    for (final c in await ref.watch(learningDaoProvider).cards())
      if (c.type == CardType.p) itemKey(c.itemId): c,
  };

  Future<MeCity> count(
    PackRepository pack,
    Map<String, NamedStreet> streets,
  ) async {
    final city = pack.city();
    final core = streets.values.toSet().where(Curriculum.isCore).toList();
    final memory = cityMemory(
      [for (final s in core) ?cards[s.id]],
      now,
      isCore: (_) => true,
    );
    return (
      id: city.id,
      nameKa: city.nameKa,
      nameEn: city.nameEn,
      count: (known: memory.round(), total: core.length),
    );
  }

  final openId = open?.pack.city().id;
  final cities = await readCityPacks(
    () => ref.read(packStoreProvider),
    [?openId, ...(await dao.recentCityIds()).where((id) => id != openId)],
    open: open,
    count,
  );
  final counts = await dao.badgeCounts();
  return (
    since: await dao.firstPlayedAt(),
    bestStreak: streak.summary.best,
    knownStreets: cards.values.where((c) => isKnown(c, now)).length,
    pins: counts.pins,
    countedDays: counts.goalDays,
    cities: cities,
  );
});
