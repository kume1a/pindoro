import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/carry_over.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/route_book.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/streak.dart';
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

/// The open city's placement and home and work neighbourhoods; null before
/// either. Writers invalidate it.
final learnCityProvider = FutureProvider.autoDispose<LearnCityRow?>((
  ref,
) async {
  final city = await ref.watch(settingsProvider.selectAsync((s) => s.cityId));
  return ref.watch(learningDaoProvider).learnCity(city);
});

/// Home, then work: the chunks new streets start in (SPEC §6.3).
final anchorsProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  final city = await ref.watch(learnCityProvider.future);
  return [?city?.homeId, ?city?.workId];
});

/// The open city's P cards by the street they belong to.
final streetCardsProvider = FutureProvider.autoDispose<Map<String, CardState>>((
  ref,
) async {
  final streets = await ref.watch(cityStreetsProvider.future);
  return {
    for (final card in await ref.watch(cityCardsProvider.future))
      if (card.type == CardType.p) streets[itemKey(card.itemId)]!.id: card,
  };
});

/// The open city's cards by item id, keyed by the street they belong to
/// (`N:<street id>` even when the card was made on another of its parts).
final cardsByItemProvider = FutureProvider.autoDispose<Map<String, CardState>>((
  ref,
) async {
  final streets = await ref.watch(cityStreetsProvider.future);
  return {
    for (final card in await ref.watch(cityCardsProvider.future))
      switch (streets[itemKey(card.itemId)]) {
        final street? => card.type.item(street.id),
        null => card.itemId,
      }: card,
  };
});

/// A P card's name and ends cards (SPEC §8 Mastered), from the open city.
final sidesOfProvider = FutureProvider.autoDispose<SidesOf>((ref) async {
  final streets = await ref.watch(cityStreetsProvider.future);
  final curriculum = await ref.watch(curriculumProvider.future);
  final byItem = await ref.watch(cardsByItemProvider.future);
  return (CardState p) =>
      curriculum.sidesOf(streets[itemKey(p.itemId)]!.id, byItem);
});

/// The next [count] new streets in curriculum order, as P items (SPEC §6.3).
final newCandidatesProvider = FutureProvider.autoDispose
    .family<List<String>, int>((ref, count) async {
      final now = ref.watch(clockProvider)();
      final curriculumFuture = ref.watch(curriculumProvider.future);
      final cardsFuture = ref.watch(streetCardsProvider.future);
      final anchors = await ref.watch(anchorsProvider.future);
      final picks = (await curriculumFuture).next(
        cards: await cardsFuture,
        now: now,
        count: count,
        anchors: anchors,
      );
      return [for (final id in picks) CardType.p.item(id)];
    });

typedef AsksCard = bool Function(CardState card);

/// Whether the open pack asks a card. Not a street card whose street left
/// the pack, a route card the pack doesn't ask (a hidden or dropped place) or
/// a recital whose run it lacks: those are never due. A card keyed by another
/// part of a street still counts as that street's card. Saved runs, not
/// [runsProvider], which makes runs as it builds: day marking reads this
/// after every answer.
final asksCardProvider = FutureProvider.autoDispose<AsksCard>((ref) async {
  final dao = ref.watch(learningDaoProvider);
  final pack = await ref.watch(packRepositoryProvider.future);
  final streets = await ref.watch(cityStreetsProvider.future);
  final routes = await ref.watch(routeBookProvider.future);
  final runs = {
    for (final r in await savedRuns(dao, pack.junctionNodes())) r.id,
  };
  return (CardState card) =>
      streets.containsKey(itemKey(card.itemId)) ||
      routes.questions.containsKey(card.itemId) ||
      (card.type == CardType.r && runs.contains(itemKey(card.itemId)));
});

/// The open city's cards that its pack asks ([asksCardProvider]).
final cityCardsProvider = FutureProvider.autoDispose<List<CardState>>((
  ref,
) async {
  final dao = ref.watch(learningDaoProvider);
  final asks = await ref.watch(asksCardProvider.future);
  await ref.watch(carryOverProvider.future);
  return (await dao.cards()).where(asks).toList();
});

/// Reviews due by the end of tomorrow (Today's done state).
final dueTomorrowProvider = FutureProvider.autoDispose<int>((ref) async {
  final now = ref.watch(clockProvider)();
  final cards = await ref.watch(cityCardsProvider.future);
  final endOfTomorrow = nextMidnight(nextMidnight(now));
  return cards.where((c) => isDueBefore(c, endOfTomorrow)).length;
});

/// Today's session over the open city's cards (SPEC §7, §16.2).
final todayPlanProvider = FutureProvider.autoDispose<SessionPlan>(
  (ref) => _plan(ref),
);

/// "Learn 10 more" (SPEC §7): [LearningConfig.learnMoreCount] new streets past
/// the daily number.
final learnMorePlanProvider = FutureProvider.autoDispose<SessionPlan>(
  (ref) => _plan(ref, extraNew: LearningConfig.learnMoreCount),
);

Future<SessionPlan> _plan(Ref ref, {int? extraNew}) async {
  final dao = ref.watch(learningDaoProvider);
  final now = ref.watch(clockProvider)();
  final settings = await ref.watch(settingsProvider.future);
  final streetsFuture = ref.watch(cityStreetsProvider.future);
  final cardsFuture = ref.watch(cityCardsProvider.future);
  final byItemFuture = ref.watch(cardsByItemProvider.future);
  final streetCardsFuture = ref.watch(streetCardsProvider.future);
  final curriculumFuture = ref.watch(curriculumProvider.future);
  final routesFuture = ref.watch(routeBookProvider.future);
  final streakFuture = ref.watch(streakProvider.future);
  final runsFuture = ref.watch(runsProvider.future);
  final candidatesFuture = ref.watch(
    newCandidatesProvider(
      extraNew ?? LearningConfig.newPerDay[settings.minutesPerDay] ?? 0,
    ).future,
  );
  final streets = await streetsFuture;
  final cards = await cardsFuture;
  final cardedStreets = {
    for (final card in cards) ?streets[itemKey(card.itemId)]?.id,
  };
  final candidates = [
    for (final id in await candidatesFuture)
      if (!cardedStreets.contains(itemKey(id))) id,
  ];
  final curriculum = await curriculumFuture;
  final byItem = await byItemFuture;
  final log = await dao.log();
  final today = log.where((e) => !e.ts.isBefore(startOfDay(now))).toList();
  final times = timeEstimates(log);
  final seed = now.year * 10000 + now.month * 100 + now.day;
  final learnMore = extraNew != null;
  final book = await routesFuture;
  final open = learnMore
      ? const <String>[]
      : curriculum.openRoutes(
          book.candidates,
          cards: await streetCardsFuture,
          carded: {for (final c in cards) c.itemId},
          items: byItem,
          now: now,
          phase2Open:
              (await streakFuture).summary.days >=
              LearningConfig.phase2StableDays,
        );
  final places = {
    for (final c in book.candidates)
      if (isPlaceIntro(c)) c.itemId,
  };
  return Planner.plan(
    cards: cards,
    newCandidates: candidates,
    minutesPerDay: settings.minutesPerDay,
    now: now,
    seed: seed,
    introducedToday: introducedToday(cards, now),
    spentTodayS: spentTodayS(log, now),
    extraNew: extraNew,
    openSides: learnMore ? const [] : curriculum.openSides(byItem),
    sidesStartedToday: startedToday(today, now, sideTypes),
    openRoutes: [
      for (final id in open)
        if (!places.contains(id)) id,
    ],
    routesStartedToday: startedToday(today, now, routeTypes),
    openPlaces: [
      for (final id in open)
        if (places.contains(id)) id,
    ],
    placesIntroducedToday: introducedToday(cards, now, types: {CardType.l}),
    openRecitals: learnMore
        ? const []
        : openRecitals(await runsFuture, cards: byItem, now: now),
    recitalsStartedToday: startedToday(today, now, {CardType.r}),
    drills: learnMore
        ? Drills.none
        : planDrills(
            curriculum: curriculum,
            streets: streets.values,
            cards: await streetCardsFuture,
            today: today,
            centre: curriculum.centre,
            now: now,
            seed: seed,
          ),
    tReviewS: times.tReviewS,
    tNewS: times.tNewS,
  );
}
