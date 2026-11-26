import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/cards.dart';
import 'package:pindoro/features/learning/data/drive_history.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/route_book.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/streak.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Reviews due by the end of tomorrow (Today's done state).
final dueTomorrowProvider = FutureProvider.autoDispose<int>((ref) async {
  final now = ref.watch(clockProvider)();
  final cards = await ref.watch(reviewedCardsProvider.future);
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
  final learnMore = extraNew != null;
  final dao = ref.watch(learningDaoProvider);
  final now = ref.watch(clockProvider)();
  final settings = await ref.watch(settingsProvider.future);
  final streetsFuture = ref.watch(cityStreetsProvider.future);
  final cardsFuture = ref.watch(cityCardsProvider.future);
  final reviewedFuture = ref.watch(reviewedCardsProvider.future);
  final byItemFuture = ref.watch(cardsByItemProvider.future);
  final streetCardsFuture = ref.watch(streetCardsProvider.future);
  final curriculumFuture = ref.watch(curriculumProvider.future);
  final routesFuture = ref.watch(routeBookProvider.future);
  // Learn 10 more opens no routes or recitals, so it waits on neither.
  final streakFuture = learnMore ? null : ref.watch(streakProvider.future);
  final runsFuture = learnMore ? null : ref.watch(runsProvider.future);
  final candidatesFuture = ref.watch(
    newCandidatesProvider(
      extraNew ?? newPerDayAt(settings.minutesPerDay),
    ).future,
  );
  final streets = await streetsFuture;
  final cards = await cardsFuture;
  final reviewed = await reviewedFuture;
  final cardedStreets = {
    for (final card in cards) ?streets[itemKey(card.itemId)]?.id,
  };
  final candidates = [
    for (final id in await candidatesFuture)
      if (!cardedStreets.contains(itemKey(id))) id,
  ];
  final curriculum = await curriculumFuture;
  final byItem = await byItemFuture;
  final streetCards = await streetCardsFuture;
  final coreStreetCards = [
    for (final s in coreStreets(streets)) ?streetCards[s.id],
  ];
  final log = await dao.log();
  final today = log.where((e) => !e.ts.isBefore(startOfDay(now))).toList();
  final times = timeEstimates(log);
  final seed = now.year * 10000 + now.month * 100 + now.day;
  final book = await routesFuture;
  final open = learnMore
      ? const <String>[]
      : curriculum.openRoutes(
          book.candidates,
          cards: streetCards,
          carded: {for (final c in cards) c.itemId},
          items: byItem,
          now: now,
          phase2Open:
              (await streakFuture!).summary.days >=
              LearningConfig.phase2StableDays,
        );
  final places = {
    for (final c in book.candidates)
      if (isPlaceIntro(c)) c.itemId,
  };
  final mine = learnMore
      ? null
      : await ref.watch(yourRouteItemsProvider.future);
  final first = yourRoutesFirst(
    newCandidates: candidates,
    openRoutes: [
      for (final id in open)
        if (!places.contains(id)) id,
    ],
    mineRoutes: mine?.routes ?? const {},
    mineStreets: [
      for (final id in mine?.streets ?? const <String>[])
        if (!cardedStreets.contains(id)) CardType.p.item(id),
    ],
    cap: mine == null || mine.routes.isEmpty
        ? 0
        : (yourRoutesShareOf(coreStreetCards, log, now) *
                  newPerDayAt(settings.minutesPerDay))
              .round(),
  );
  return Planner.plan(
    cards: reviewed,
    newCandidates: first.newCandidates,
    minutesPerDay: settings.minutesPerDay,
    now: now,
    seed: seed,
    introducedToday: introducedToday(cards, now),
    spentTodayS: spentTodayS(log, now),
    extraNew: extraNew,
    openSides: learnMore
        ? const []
        : curriculum.openSides(cardsByItemOf(streets, reviewed)),
    sidesStartedToday: startedToday(today, now, sideTypes),
    openRoutes: first.openRoutes,
    routesStartedToday: startedToday(today, now, routeTypes),
    openPlaces: [
      for (final id in open)
        if (places.contains(id)) id,
    ],
    placesIntroducedToday: introducedToday(cards, now, types: {CardType.l}),
    openRecitals: learnMore
        ? const []
        : openRecitals(await runsFuture!, cards: byItem, now: now),
    recitalsStartedToday: startedToday(today, now, {CardType.r}),
    drills: learnMore
        ? Drills.none
        : planDrills(
            curriculum: curriculum,
            streets: streets.values,
            cards: streetCardsOf(streets, reviewed),
            today: today,
            centre: curriculum.centre,
            now: now,
            seed: seed,
          ),
    tReviewS: times.tReviewS,
    tNewS: times.tNewS,
  );
}
