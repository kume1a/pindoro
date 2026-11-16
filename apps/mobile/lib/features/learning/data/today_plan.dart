import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/carry_over.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// The open pack's curriculum (SPEC §6), built once per pack.
final curriculumProvider = FutureProvider<Curriculum>((ref) async {
  final pack = await ref.watch(packRepositoryProvider.future);
  final streets = await ref.watch(cityStreetsProvider.future);
  return Curriculum(
    streets: streets.values,
    districts: pack.districts(),
    centre: pack.city().center,
    families: pack.families(),
    chunkNeighbours: pack.chunkNeighbours(),
  );
});

/// The next new streets in curriculum order, as P items (SPEC §6.3).
final newCandidatesProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  final now = ref.watch(clockProvider)();
  final curriculumFuture = ref.watch(curriculumProvider.future);
  final streetsFuture = ref.watch(cityStreetsProvider.future);
  final cardsFuture = ref.watch(cityCardsProvider.future);
  final settings = await ref.watch(settingsProvider.future);
  final streets = await streetsFuture;
  final picks = (await curriculumFuture).next(
    cards: {
      for (final card in await cardsFuture)
        if (card.type == CardType.p) streets[itemKey(card.itemId)]!.id: card,
    },
    now: now,
    count: LearningConfig.newPerDay[settings.minutesPerDay] ?? 0,
  );
  return [for (final id in picks) CardType.p.item(id)];
});

/// The open city's cards. A card whose street left the pack is skipped; one
/// keyed by another part of a street still counts as that street's card.
final cityCardsProvider = FutureProvider.autoDispose<List<CardState>>((
  ref,
) async {
  final dao = ref.watch(learningDaoProvider);
  final streets = await ref.watch(cityStreetsProvider.future);
  await ref.watch(carryOverProvider.future);
  return [
    for (final card in await dao.cards())
      if (streets.containsKey(itemKey(card.itemId))) card,
  ];
});

/// Reviews due by the end of tomorrow (Today's done state).
final dueTomorrowProvider = FutureProvider.autoDispose<int>((ref) async {
  final now = ref.watch(clockProvider)();
  final cards = await ref.watch(cityCardsProvider.future);
  final endOfTomorrow = nextMidnight(nextMidnight(now));
  return cards.where((c) => isDueBefore(c, endOfTomorrow)).length;
});

/// Today's session over the open city's cards (SPEC §7, §16.2).
final todayPlanProvider = FutureProvider.autoDispose<SessionPlan>((ref) async {
  final dao = ref.watch(learningDaoProvider);
  final now = ref.watch(clockProvider)();
  final streetsFuture = ref.watch(cityStreetsProvider.future);
  final cardsFuture = ref.watch(cityCardsProvider.future);
  final candidatesFuture = ref.watch(newCandidatesProvider.future);
  final settings = await ref.watch(settingsProvider.future);
  final streets = await streetsFuture;
  final cards = await cardsFuture;
  final cardedStreets = {
    for (final card in cards) streets[itemKey(card.itemId)]!.id,
  };
  final candidates = [
    for (final id in await candidatesFuture)
      if (!cardedStreets.contains(itemKey(id))) id,
  ];
  return Planner.plan(
    cards: cards,
    newCandidates: candidates,
    minutesPerDay: settings.minutesPerDay,
    now: now,
    seed: now.year * 10000 + now.month * 100 + now.day,
    introducedToday: introducedToday(cards, now),
    spentTodayS: spentTodayS(await dao.log(since: startOfDay(now)), now),
  );
});
