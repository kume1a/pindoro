import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/route_book.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/learning/data/today_plan.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// How well a set of core streets is remembered: City memory over [total]
/// streets and the memory bar's counts (SPEC §8).
typedef MemorySummary = ({
  double memory,
  int total,
  Map<MemoryState, int> counts,
});

/// Where a neighbourhood is in the course: every core street Mastered, the
/// one being taught now, begun, or not begun yet.
enum ChunkStage { mastered, now, started, next }

typedef ChunkProgress = ({
  District chunk,
  MemorySummary memory,
  ChunkStage stage,
  int seen,

  /// The neighbourhood taught before a [ChunkStage.next] one.
  District? after,
});

typedef RaionProgress = ({
  District district,
  MemorySummary memory,

  /// In the order they are taught: Mastered, now, begun, then the rest.
  List<ChunkProgress> chunks,
});

/// The Progress tab (SPEC §8, §16.4).
typedef ProgressOverview = ({
  MemorySummary city,
  double sinceYesterday,
  MemoryHistory history,
  double? recall,
  List<int> forecast,
  DateTime? wholeCityBy,

  /// The neighbourhood being learnt now, then the next [comingCount] - 1 in
  /// teaching order; empty once nothing is left to teach.
  List<ChunkProgress> coming,
  List<RaionProgress> districts,
});

/// How many neighbourhoods "What's coming" lists, the one being learnt
/// first.
const int comingCount = 3;

/// The open city's City memory and its change since yesterday and over the
/// week (Today); [firstDay] while nothing was played before today.
final cityMemoryProvider =
    FutureProvider.autoDispose<
      ({
        MemorySummary city,
        double sinceYesterday,
        double sinceWeek,
        bool firstDay,
      })
    >((ref) async {
      final now = ref.watch(clockProvider)();
      final streets = await ref.watch(cityStreetsProvider.future);
      final cards = await ref.watch(streetCardsProvider.future);
      final sidesOf = await ref.watch(sidesOfProvider.future);
      final log = await ref.watch(learningDaoProvider).log();
      final core = streets.values.where(Curriculum.isCore).toSet();
      final today = startOfDay(now);
      return (
        city: memorySummary(core, cards, now, sidesOf),
        sinceYesterday: _since(core, cards, log, now, const Duration(days: 1)),
        sinceWeek: _since(core, cards, log, now, const Duration(days: 7)),
        firstDay:
            log.every((e) => !e.ts.isBefore(today)) &&
            cards.values.every(
              (c) => !(c.memory?.lastReview.isBefore(today) ?? false),
            ),
      );
    });

final progressProvider = FutureProvider.autoDispose<ProgressOverview>((
  ref,
) async {
  final now = ref.watch(clockProvider)();
  final pack = await ref.watch(packRepositoryProvider.future);
  final streets = await ref.watch(cityStreetsProvider.future);
  final curriculum = await ref.watch(curriculumProvider.future);
  final cards = await ref.watch(streetCardsProvider.future);
  final allCards = await ref.watch(cityCardsProvider.future);
  final sidesOf = await ref.watch(sidesOfProvider.future);
  final anchors = await ref.watch(anchorsProvider.future);
  final settings = await ref.watch(settingsProvider.future);
  final log = await ref.watch(learningDaoProvider).log();

  final core = streets.values.where(Curriculum.isCore).toSet();
  final coreCards = [for (final s in core) ?cards[s.id]];
  final districts = {for (final d in pack.districts()) d.id: d};
  final sequence = [
    for (final id in curriculum.chunkSequence(cards, anchors))
      if (districts.containsKey(id)) id,
  ];
  final learning = districts[sequence.firstOrNull];

  ChunkProgress chunkOf(String id) {
    final streets = curriculum.streetsIn(id).where(Curriculum.isCore);
    final memory = memorySummary(streets, cards, now, sidesOf);
    final seen = streets.where((s) => cards.containsKey(s.id)).length;
    final at = sequence.indexOf(id);
    return (
      chunk: districts[id]!,
      memory: memory,
      seen: seen,
      stage:
          memory.total > 0 &&
              memory.counts[MemoryState.mastered] == memory.total
          ? ChunkStage.mastered
          : id == learning?.id
          ? ChunkStage.now
          : seen > 0
          ? ChunkStage.started
          : ChunkStage.next,
      after: at > 0 ? districts[sequence[at - 1]] : null,
    );
  }

  final chunksByRaion = <String, List<ChunkProgress>>{};
  for (final d in districts.values) {
    final raion = d.parentId;
    if (d.kind != DistrictKind.neighbourhood || raion == null) continue;
    chunksByRaion.putIfAbsent(raion, () => []).add(chunkOf(d.id));
  }
  int taught(ChunkProgress c) => switch (c.stage) {
    ChunkStage.next => sequence.indexOf(c.chunk.id) + 1,
    _ => c.stage.index - ChunkStage.values.length,
  };
  final raions = [
    for (final MapEntry(key: id, value: chunks) in chunksByRaion.entries)
      if (districts[id] case final district?)
        (
          district: district,
          memory: memorySummary(
            core.where((s) => curriculum.raionOf(s.id) == id),
            cards,
            now,
            sidesOf,
          ),
          chunks: chunks..sort((a, b) => taught(a).compareTo(taught(b))),
        ),
  ]..sort((a, b) => _share(b.memory).compareTo(_share(a.memory)));

  final memory = memorySummary(core, cards, now, sidesOf);
  return (
    city: memory,
    sinceYesterday: _since(core, cards, log, now, const Duration(days: 1)),
    history: cityMemoryHistory(
      cards: coreCards,
      log: log,
      now: now,
      isCore: (_) => true,
    ),
    recall: recallRate(log, now),
    forecast: forecast(allCards, now),
    wholeCityBy: wholeCityBy(
      unseenCore: core.where((s) => !cards.containsKey(s.id)).length,
      newPerDay: LearningConfig.newPerDay[settings.minutesPerDay] ?? 0,
      now: now,
    ),
    coming: [for (final id in sequence.take(comingCount)) chunkOf(id)],
    districts: raions,
  );
});

/// [streets]' City memory and memory bar counts over their P [cards].
MemorySummary memorySummary(
  Iterable<NamedStreet> streets,
  Map<String, CardState> cards,
  DateTime now,
  SidesOf sidesOf,
) {
  final carded = [for (final s in streets) ?cards[s.id]];
  return (
    memory: cityMemory(carded, now, isCore: (_) => true),
    total: streets.length,
    counts: memoryCounts(carded, now, sidesOf: sidesOf),
  );
}

double _share(MemorySummary m) => m.total == 0 ? 0 : m.memory / m.total;

/// How City memory changed over the last [span].
double _since(
  Iterable<NamedStreet> core,
  Map<String, CardState> cards,
  List<LogEntry> log,
  DateTime now,
  Duration span,
) {
  final carded = [for (final s in core) ?cards[s.id]];
  return cityMemory(carded, now, isCore: (_) => true) -
      cityMemoryAt(carded, log, now.subtract(span));
}

/// Reloads what the tabs show from the learning tables, after anything that
/// may have written to them (a session, a round, another tab). Learning
/// providers read with futures, so writers invalidate them.
void refreshLearning(WidgetRef ref) => ref
  ..invalidate(learnCityProvider)
  ..invalidate(asksCardProvider)
  ..invalidate(cityCardsProvider)
  ..invalidate(todayPlanProvider)
  ..invalidate(cityMemoryProvider)
  ..invalidate(progressProvider)
  ..invalidate(runsProvider)
  ..invalidate(todayRunProvider)
  ..invalidate(mixUpsYesterdayProvider);

/// City memory per area of the open pack (Explore): a raion and a
/// neighbourhood over the core streets Progress counts for them (by chunk),
/// any other area (or any area of a pack without chunks) over the core
/// streets with a part in it.
final areaMemoryProvider =
    FutureProvider.autoDispose<Map<String, MemorySummary>>((ref) async {
      final now = ref.watch(clockProvider)();
      final pack = await ref.watch(packRepositoryProvider.future);
      final streets = await ref.watch(cityStreetsProvider.future);
      final curriculum = await ref.watch(curriculumProvider.future);
      final cards = await ref.watch(streetCardsProvider.future);
      final sidesOf = await ref.watch(sidesOfProvider.future);
      final core = streets.values.where(Curriculum.isCore).toSet();
      final byCurriculum = <String, List<NamedStreet>>{};
      for (final s in core) {
        for (final id in [Curriculum.chunkOf(s), ?curriculum.raionOf(s.id)]) {
          byCurriculum.putIfAbsent(id, () => []).add(s);
        }
      }
      final parts = pack.partsByDistrict();
      return {
        for (final d in pack.districts())
          d.id: memorySummary(
            byCurriculum[d.id] ??
                [
                  for (final s in core)
                    if (s.parts.any(
                      (p) => parts[d.id]?.contains(p.id) ?? false,
                    ))
                      s,
                ],
            cards,
            now,
            sidesOf,
          ),
      };
    });

/// What an Explore round of an area at a difficulty can ask (the question
/// selector's pool) and how much of it is in memory.
final roundPoolProvider = FutureProvider.autoDispose
    .family<MemorySummary, (Area, Difficulty)>((ref, key) async {
      final (area, difficulty) = key;
      final now = ref.watch(clockProvider)();
      final pack = await ref.watch(packRepositoryProvider.future);
      final streets = await ref.watch(cityStreetsProvider.future);
      final cards = await ref.watch(streetCardsProvider.future);
      final sidesOf = await ref.watch(sidesOfProvider.future);
      final pool = {
        for (final s in QuestionSelector.candidates(
          area.streetsIn(pack, difficulty.pool),
        ))
          streets[s.id] ?? s,
      };
      return memorySummary(pool, cards, now, sidesOf);
    });

/// Of [m]'s streets, those Known or better.
int knownOf(MemorySummary m) =>
    (m.counts[MemoryState.known] ?? 0) +
    (m.counts[MemoryState.solid] ?? 0) +
    (m.counts[MemoryState.mastered] ?? 0);

/// A raion's gateways (SPEC §6.5): how many its neighbourhoods have, how many
/// of their cards are Solid, and whether any is carded yet.
typedef GatewayCount = ({int solid, int total, bool started});

final gatewaysProvider = FutureProvider.autoDispose
    .family<GatewayCount, String>((ref, raion) async {
      final pack = await ref.watch(packRepositoryProvider.future);
      final book = await ref.watch(routeBookProvider.future);
      final cards = await ref.watch(cardsByItemProvider.future);
      final parents = {for (final d in pack.districts()) d.id: d.parentId};
      final items = [
        for (final c in book.candidates)
          if (c.layer == RouteLayer.gateway && parents[c.chunk] == raion)
            c.itemId,
      ];
      return (
        solid: items.where((id) => cards[id]?.isSolid ?? false).length,
        total: items.length,
        started: items.any(cards.containsKey),
      );
    });

/// Street pairs mixed up yesterday (Today's "Watch out for"), latest first.
final mixUpsYesterdayProvider =
    FutureProvider.autoDispose<List<(NamedStreet, NamedStreet)>>((ref) async {
      final today = startOfDay(ref.watch(clockProvider)());
      final streets = await ref.watch(cityStreetsProvider.future);
      final pairs = await ref
          .watch(learningDaoProvider)
          .confusionsBetween(
            startOfDay(today.subtract(const Duration(hours: 12))),
            today,
          );
      return [
        for (final (a, b) in pairs)
          if ((streets[a], streets[b]) case (final a?, final b?)) (a, b),
      ];
    });

/// The neighbourhood being learnt now on its mini map: its outline and the
/// streets in it the player knows (Today's neighbourhood card); null once
/// nothing is left to teach.
typedef NowLearning = ({
  ChunkProgress chunk,
  District raion,
  ChunkProgress? next,
  List<List<Polyline>> outline,
  List<Polyline> known,
});

final nowLearningProvider = FutureProvider.autoDispose<NowLearning?>((
  ref,
) async {
  final now = ref.watch(clockProvider)();
  final progress = await ref.watch(progressProvider.future);
  final chunk = progress.coming.firstOrNull;
  if (chunk == null) return null;
  final pack = await ref.watch(packRepositoryProvider.future);
  final curriculum = await ref.watch(curriculumProvider.future);
  final cards = await ref.watch(streetCardsProvider.future);
  final raion = pack.districts().where((d) => d.id == chunk.chunk.parentId);
  if (raion.isEmpty) return null;
  return (
    chunk: chunk,
    raion: raion.single,
    next: progress.coming.skip(1).firstOrNull,
    outline: chunk.chunk.boundary,
    known: [
      for (final s in curriculum.streetsIn(chunk.chunk.id))
        if (cards[s.id] case final card? when isKnown(card, now)) ...s.geometry,
    ],
  );
});

/// Core streets not met yet: what the whole-city date counts down.
final unseenCoreProvider = FutureProvider.autoDispose<int>((ref) async {
  final streets = await ref.watch(cityStreetsProvider.future);
  final cards = await ref.watch(streetCardsProvider.future);
  return streets.values
      .toSet()
      .where((s) => Curriculum.isCore(s) && !cards.containsKey(s.id))
      .length;
});
