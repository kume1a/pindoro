import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/carry_over.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/route_book.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// The open pack's curriculum (SPEC §6), built once per pack.
final curriculumProvider = FutureProvider<Curriculum>((ref) async {
  final pack = await ref.watch(packRepositoryProvider.future);
  return curriculumOf(pack, await ref.watch(cityStreetsProvider.future));
});

/// [pack]'s curriculum over its [streets] (SPEC §6).
Curriculum curriculumOf(
  PackRepository pack,
  Map<String, NamedStreet> streets,
) => Curriculum(
  streets: streets.values,
  districts: pack.districts(),
  centre: pack.city().center,
  families: pack.families(),
  chunkNeighbours: pack.chunkNeighbours(),
);

/// The core streets among [streets] (SPEC §6), each once.
Set<NamedStreet> coreStreets(Map<String, NamedStreet> streets) =>
    streets.values.where(Curriculum.isCore).toSet();

/// New streets a day at [minutes] a day (SPEC §13).
int newPerDayAt(int? minutes) => LearningConfig.newPerDay[minutes] ?? 0;

/// The open city's placement and home and work neighbourhoods; null before
/// either. Writers invalidate it.
final learnCityProvider = FutureProvider.autoDispose<LearnCityRow?>((
  ref,
) async {
  final city = await ref.watch(settingsProvider.selectAsync((s) => s.cityId));
  return ref.watch(learningDaoProvider).learnCity(city);
});

/// Start from zero: the open city counts as placed, with nothing known yet.
Future<void> startFromZero(WidgetRef ref) async {
  final city = ref.read(settingsProvider).value?.cityId;
  if (city == null) return;
  await ref
      .read(learningDaoProvider)
      .markPlaced(city, ref.read(clockProvider)());
  ref.invalidate(learnCityProvider);
}

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
  return streetCardsOf(streets, await ref.watch(cityCardsProvider.future));
});

/// The open city's cards by item id, keyed by the street they belong to.
final cardsByItemProvider = FutureProvider.autoDispose<Map<String, CardState>>((
  ref,
) async {
  final streets = await ref.watch(cityStreetsProvider.future);
  return cardsByItemOf(streets, await ref.watch(cityCardsProvider.future));
});

/// The P cards among [cards] by the street of [streets] they belong to: a
/// card made on another part of a street is still that street's.
Map<String, CardState> streetCardsOf(
  Map<String, NamedStreet> streets,
  Iterable<CardState> cards,
) => {
  for (final card in cards)
    if (card.type == CardType.p)
      if (streets[itemKey(card.itemId)] case final street?) street.id: card,
};

/// [cards] by item id, a street card's keyed by its street of [streets]
/// (`N:<street id>` even when the card was made on another of its parts).
Map<String, CardState> cardsByItemOf(
  Map<String, NamedStreet> streets,
  Iterable<CardState> cards,
) => {
  for (final card in cards)
    switch (streets[itemKey(card.itemId)]) {
      final street? => card.type.item(street.id),
      null => card.itemId,
    }: card,
};

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

/// [asks] narrowed to the cards reviewed now: none of a street parked until
/// its road class is taught (`Curriculum.parkedStreets`), worked out over
/// [cards]. Parked cards still count everywhere else.
AsksCard reviewsOf(
  AsksCard asks, {
  required Map<String, NamedStreet> streets,
  required Curriculum curriculum,
  required Iterable<CardState> cards,
}) {
  final parked = curriculum.parkedStreets(
    streetCardsOf(streets, cards.where(asks)),
  );
  return (CardState card) =>
      asks(card) && !parked.contains(streets[itemKey(card.itemId)]?.id);
}

/// The open city's cards reviewed now ([reviewsOf]): what Today plans and
/// forecasts.
final reviewedCardsProvider = FutureProvider.autoDispose<List<CardState>>((
  ref,
) async {
  final streets = await ref.watch(cityStreetsProvider.future);
  final curriculum = await ref.watch(curriculumProvider.future);
  final cards = await ref.watch(cityCardsProvider.future);
  final reviews = reviewsOf(
    (_) => true,
    streets: streets,
    curriculum: curriculum,
    cards: cards,
  );
  return cards.where(reviews).toList();
});
