import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/hold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/cards.dart';
import 'package:pindoro/features/learning/data/drive_history.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/route_book.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/learning/data/today_plan.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Everything a session reads before its first step.
typedef SessionInputs = ({
  SessionPlan? plan,
  Map<String, NamedStreet> streets,
  PackRepository pack,
  Curriculum curriculum,
  RouteBook routes,
  List<Run> runs,
  RoadGraph? graph,
  AsksCard asks,

  /// The streets of the player's routes; null when not read again.
  List<String>? yours,
  List<CardState> cards,
  List<(String, String)> confusions,
  List<LogEntry> log,
  LearnCityRow? learnCity,
  Settings settings,

  /// Each suspended leech's top confusion, by item id.
  Map<String, NamedStreet> contrasts,
});

/// A session's inputs: today's plan when [planned] ([more]: Learn 10 more's, which keeps the
/// routes read for the day, so [SessionInputs.yours] is null then).
Future<SessionInputs> loadSession(
  Ref ref, {
  required bool planned,
  required bool more,
}) async {
  // Every read starts before the first await: the screen can go meanwhile.
  final dao = ref.read(learningDaoProvider);
  final planFuture = planned
      ? ref.hold((more ? learnMorePlanProvider : todayPlanProvider).future)
      : null;
  final streetsFuture = ref.read(cityStreetsProvider.future);
  final packFuture = ref.read(packRepositoryProvider.future);
  final curriculumFuture = ref.read(curriculumProvider.future);
  final routesFuture = ref.read(routeBookProvider.future);
  final runsFuture = ref.hold(runsProvider.future);
  final graphFuture = ref.hold(drivingGraphProvider.future);
  final asksFuture = ref.hold(asksCardProvider.future);
  final yoursFuture = more ? null : ref.hold(yourRouteItemsProvider.future);
  final settingsFuture = ref.read(settingsProvider.future);
  final plan = await planFuture;
  final streets = await streetsFuture;
  final pack = await packFuture;
  final curriculum = await curriculumFuture;
  final routes = await routesFuture;
  final runs = await runsFuture;
  final graph = await graphFuture;
  final asks = await asksFuture;
  final yours = (await yoursFuture)?.streets;
  final cards = await dao.cards();
  final confusions = await dao.confusionPairs();
  final log = await dao.log();
  final learnCity = await dao.learnCity(pack.city().id);
  final settings = await settingsFuture;
  final contrasts = <String, NamedStreet>{};
  for (final c in cards.where((c) => c.phase == CardPhase.suspended)) {
    final top = streets[await dao.topConfusion(itemKey(c.itemId)) ?? ''];
    if (top != null) contrasts[c.itemId] = top;
  }
  return (
    plan: plan,
    streets: streets,
    pack: pack,
    curriculum: curriculum,
    routes: routes,
    runs: runs,
    graph: graph,
    asks: asks,
    yours: yours,
    cards: cards,
    confusions: confusions,
    log: log,
    learnCity: learnCity,
    settings: settings,
    contrasts: contrasts,
  );
}
