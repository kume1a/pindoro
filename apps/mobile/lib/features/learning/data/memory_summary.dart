import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/features/learning/data/cards.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
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

/// How City memory changed over the last [span].
double memorySince(
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
      final core = coreStreets(streets);
      final today = startOfDay(now);
      return (
        city: memorySummary(core, cards, now, sidesOf),
        sinceYesterday: memorySince(
          core,
          cards,
          log,
          now,
          const Duration(days: 1),
        ),
        sinceWeek: memorySince(core, cards, log, now, const Duration(days: 7)),
        firstDay:
            log.every((e) => !e.ts.isBefore(today)) &&
            cards.values.every(
              (c) => !(c.memory?.lastReview.isBefore(today) ?? false),
            ),
      );
    });

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
      final core = coreStreets(streets);
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
