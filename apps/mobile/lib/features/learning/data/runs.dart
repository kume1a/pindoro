import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/route_book.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// The open pack's road graph with the moves the player reported as legal:
/// recitals and drives are graded on it (SPEC §15). Null for a pack without
/// one; writers of a report invalidate it.
final drivingGraphProvider = FutureProvider.autoDispose<RoadGraph?>((
  ref,
) async {
  final pack = await ref.watch(packRepositoryProvider.future);
  final graph = pack.roadGraph();
  if (graph == null) return null;
  return allowingReports(
    graph,
    await ref.watch(learningDaoProvider).reportedMoves(),
    pack.junctionNodes(),
  );
});

/// The recitals' runs on the open pack (SPEC §16.7), oldest first: the saved
/// ones whose ends the pack has, after saving a new route-book run when none
/// is open and this week's random pair when it is due. Empty for a pack
/// without route items.
final runsProvider = FutureProvider.autoDispose<List<Run>>((ref) async {
  final dao = ref.watch(learningDaoProvider);
  final pack = await ref.watch(packRepositoryProvider.future);
  final book = await ref.watch(routeBookProvider.future);
  final streets = await ref.watch(cityStreetsProvider.future);
  final now = ref.watch(clockProvider)();
  final graph = pack.roadGraph();
  if (graph == null || book.questions.isEmpty) return const [];
  final nodes = pack.junctionNodes();
  final runs = await savedRuns(dao, nodes);
  final cards = {for (final c in await dao.cards()) c.itemId: c};
  final bookRunOpen = openRecitals(
    runs.where((r) => !r.random),
    cards: cards,
    now: now,
  ).isNotEmpty;
  final made = [
    if (!bookRunOpen)
      nextBookRun(
        graph: graph,
        junctionNodes: nodes,
        book: book,
        cards: cards,
        existing: runs,
        now: now,
      ),
    nextRandomRun(
      graph: graph,
      junctionNodes: nodes,
      book: book,
      knownParts: {
        for (final c in cards.values)
          if (c.type == CardType.p && isKnown(c, now))
            ...?streets[itemKey(c.itemId)]?.parts.map((p) => p.id),
      },
      existing: runs,
      gatewayPhase: cards.values.any((c) => c.type == CardType.g),
      now: now,
      seed: now.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay ~/ 7,
    ),
  ].nonNulls.where((r) => runs.every((old) => old.id != r.id)).toList();
  for (final run in made) {
    await dao.saveRun(run);
  }
  return [...runs, ...made];
});

/// The saved runs whose ends the pack's [junctionNodes] have, oldest first.
Future<List<Run>> savedRuns(
  LearningDao dao,
  Map<int, int> junctionNodes,
) async {
  final inPack = junctionNodes.values.toSet();
  return [
    for (final r in await dao.recitalRuns())
      if (inPack.contains(r.fromNode) && inPack.contains(r.toNode)) r,
  ];
}

/// Pack junction ids by OSM node, for a run's ends.
final junctionsByNodeProvider = FutureProvider.autoDispose<Map<int, int>>((
  ref,
) async {
  final pack = await ref.watch(packRepositoryProvider.future);
  return {for (final e in pack.junctionNodes().entries) e.value: e.key};
});

/// A run to drive (V3-10 "Drive this run today", V3-50): the run, its ends
/// and how many of its turns are near due.
typedef RunToDrive = ({Run run, RunEnds ends, int dueTurns});

/// The run Today offers to drive: the route-book run whose recital is due
/// soonest; null before any run has its recital card.
final todayRunProvider = FutureProvider.autoDispose<RunToDrive?>((ref) async {
  final runs = await ref.watch(runsProvider.future);
  final graph = await ref.watch(drivingGraphProvider.future);
  final byNode = await ref.watch(junctionsByNodeProvider.future);
  final streets = await ref.watch(cityStreetsProvider.future);
  final now = ref.watch(clockProvider)();
  final cards = {
    for (final c in await ref.watch(learningDaoProvider).cards()) c.itemId: c,
  };
  if (graph == null) return null;
  final due = [
    for (final r in runs)
      if (!r.random)
        if (cards[CardType.r.item(r.id)]?.dueAt case final at?) (r, at),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  for (final (run, _) in due) {
    if (runEnds(run, graph, byNode, streets) case final ends?) {
      return (
        run: run,
        ends: ends,
        dueTurns: run.items
            .where((id) => cards[id] != null && isNearDue(cards[id]!, now))
            .length,
      );
    }
  }
  return null;
});
