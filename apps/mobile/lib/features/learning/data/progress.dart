import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
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
  ({DateTime start, List<double> values}) history,
  double? recall,
  List<int> forecast,
  DateTime? wholeCityBy,
  District? learning,
  List<RaionProgress> districts,
});

/// The open city's City memory and its change since yesterday and over the
/// week (Today).
final cityMemoryProvider =
    FutureProvider.autoDispose<
      ({MemorySummary city, double sinceYesterday, double sinceWeek})
    >((ref) async {
      final now = ref.watch(clockProvider)();
      final streets = await ref.watch(cityStreetsProvider.future);
      final cards = await ref.watch(streetCardsProvider.future);
      final log = await ref.watch(learningDaoProvider).log();
      final core = streets.values.where(Curriculum.isCore).toSet();
      return (
        city: _summary(core, cards, now),
        sinceYesterday: _since(core, cards, log, now, const Duration(days: 1)),
        sinceWeek: _since(core, cards, log, now, const Duration(days: 7)),
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
  final anchors = await ref.watch(anchorsProvider.future);
  final settings = await ref.watch(settingsProvider.future);
  final log = await ref.watch(learningDaoProvider).log();

  final core = streets.values.where(Curriculum.isCore).toSet();
  final coreCards = [for (final s in core) ?cards[s.id]];
  final districts = {for (final d in pack.districts()) d.id: d};
  final sequence = curriculum.chunkSequence(cards, anchors);
  final learning = districts[sequence.firstOrNull];

  ChunkProgress chunkOf(String id) {
    final streets = curriculum.streetsIn(id).where(Curriculum.isCore);
    final memory = _summary(streets, cards, now);
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
          memory: _summary(
            core.where((s) => curriculum.raionOf(s.id) == id),
            cards,
            now,
          ),
          chunks: chunks..sort((a, b) => taught(a).compareTo(taught(b))),
        ),
  ]..sort((a, b) => _share(b.memory).compareTo(_share(a.memory)));

  final memory = _summary(core, cards, now);
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
    forecast: forecast(cards.values, now),
    wholeCityBy: wholeCityBy(
      unseenCore: core.where((s) => !cards.containsKey(s.id)).length,
      newPerDay: LearningConfig.newPerDay[settings.minutesPerDay] ?? 0,
      now: now,
    ),
    learning: learning,
    districts: raions,
  );
});

MemorySummary _summary(
  Iterable<NamedStreet> streets,
  Map<String, CardState> cards,
  DateTime now,
) {
  final carded = [for (final s in streets) ?cards[s.id]];
  return (
    memory: cityMemory(carded, now, isCore: (_) => true),
    total: streets.length,
    counts: memoryCounts(carded, now),
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

/// Core streets not met yet: what the whole-city date counts down.
final unseenCoreProvider = FutureProvider.autoDispose<int>((ref) async {
  final streets = await ref.watch(cityStreetsProvider.future);
  final cards = await ref.watch(streetCardsProvider.future);
  return streets.values
      .toSet()
      .where((s) => Curriculum.isCore(s) && !cards.containsKey(s.id))
      .length;
});
