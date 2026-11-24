import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/hold.dart';
import 'package:pindoro/features/learning/data/drive_places.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/nav_data.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// The setup's suggestion (SPEC §16.23 items 113–114, 121): the level, and the route's turns
/// that are the player's ([silent], [yours] of [turns]); the route planned from here and its key
/// decisions by key.
typedef DriveSuggestion = ({
  DriveLevel level,
  int yours,
  int turns,
  Set<String> silent,

  /// Each turn on the route, in order: whether it is yours (the setup's pips).
  List<bool> pips,
  NavPlan plan,
  Set<String> keys,
});

/// Up to `count` route options to a target from where the phone is through the stops `via`,
/// the quickest first, each with its suggestion.
typedef RouteSuggester =
    List<DriveSuggestion> Function(
      DriveTarget target, {
      int count,
      List<DriveTarget> via,
    });

/// The route options from [here] ([RouteSuggester]), the graph, cards and history read once
/// (Surprise me tries up to [LearningConfig.surpriseTries] targets). Null without a road graph.
Future<RouteSuggester?> routeSuggester(Ref ref, LatLng here) async {
  final graph = await ref.hold(drivingGraphProvider.future);
  if (graph == null) return null;
  final pack = await ref.read(packRepositoryProvider.future);
  final streets = await ref.read(cityStreetsProvider.future);
  final settings = await ref.read(settingsDaoProvider).read();
  final landmarks = await ref.hold(navLandmarksProvider.future);
  final history = await ref.hold(navHistoryProvider.future);
  final byNode = await ref.hold(junctionsByNodeProvider.future);
  final cards = {
    for (final c in await ref.read(learningDaoProvider).cards())
      if (c.type == CardType.j) c.itemId: c,
  };
  final nodes = pack.junctionNodes();
  final districts = pack.districts();
  final now = ref.read(clockProvider)();
  const fsrs = Fsrs();
  DriveSuggestion suggestion(NavPlan plan, int target) {
    final keys = [for (final d in plan.decisions) d.key];
    final s = suggestionFor(
      keys,
      target: target,
      cards: cards,
      history: history,
      districts: districts,
      byNode: byNode,
      graph: graph,
      now: now,
    );
    final pips = [for (final key in keys) s.silent.contains(key)];
    return (
      level: s.level,
      yours: pips.where((mine) => mine).length,
      turns: plan.decisions.length,
      silent: s.silent,
      pips: pips,
      plan: plan,
      keys: {
        for (final d in keyDecisions(
          graph,
          plan.decisions,
          silent: s.silent,
          recall: {
            for (final key in keys.nonNulls)
              if (cards[key]?.memory case final m?)
                key: fsrs.retrievability(m, now),
          },
        ))
          ?d.key,
      },
    );
  }

  return (
    DriveTarget target, {
    int count = LearningConfig.navOptions,
    List<DriveTarget> via = const [],
  }) => [
    for (final plan in plansFrom(
      graph,
      here,
      stopsOf(graph, target),
      via: [for (final v in via) viaStopOf(graph, v)],
      streets: streets,
      landmarks: landmarks,
      junctionNodes: nodes,
      toleranceKmh: settings.speedToleranceKmh,
      count: count,
    ))
      suggestion(plan, target.junction),
  ];
}
