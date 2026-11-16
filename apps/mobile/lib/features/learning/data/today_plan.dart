import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/course/data/course_data.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// New streets in course order, from the start district outward, until the
/// curriculum queue replaces it (docs/learning/PLAN.md M1 step 5).
final newCandidatesProvider = FutureProvider<List<String>>((ref) async {
  final plan = await ref.watch(coursePlanProvider.future);
  return [
    for (final unit in plan?.units ?? const <CourseUnit>[])
      for (final street in unit.streets) CardType.p.item(street.id),
  ];
});

/// The open city's cards. A card whose street left the pack is skipped; one
/// keyed by another part of a street still counts as that street's card.
final cityCardsProvider = FutureProvider.autoDispose<List<CardState>>((
  ref,
) async {
  final dao = ref.watch(learningDaoProvider);
  final streets = await ref.watch(cityStreetsProvider.future);
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
