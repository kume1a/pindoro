import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/cards.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

typedef HomeSavedRound = ({Round round, int answered, int total, DateTime at});

/// The latest finished round in the city: its area, the answers by tier and
/// how many streets a retry would ask.
typedef LastRound = ({
  Round round,
  Area? area,
  Map<Tier, int> tally,
  int missed,
});

typedef HomeData = ({
  PackRepository pack,
  HomeSavedRound? saved,
  LastRound? last,

  /// The areas of recent rounds, most recent first, at most
  /// [recentAreaCount].
  List<District> recent,

  /// City memory when the round Explore was opened after began; null
  /// without one.
  double? before,

  /// Streets the player has learned (a P card), parked ones aside: what "Your
  /// streets" asks.
  int learned,
});

const int recentAreaCount = 2;

/// Explore's data; with [introBefore], also City memory at that moment, where
/// the intro's figure starts. It reloads whenever progress or the chosen city
/// and area change, also while Explore waits under another screen.
final homeProvider = FutureProvider.autoDispose.family<HomeData, DateTime?>((
  ref,
  introBefore,
) async {
  ref.watch(progressChangesProvider);
  final dao = ref.watch(progressDaoProvider);
  final (cityId, area) = await ref.watch(
    settingsProvider.selectAsync((s) => (s.lastCity, s.area)),
  );
  final pack = await ref.watch(packRepositoryProvider.future);
  final city = pack.city();
  final round = await dao.savedRound(
    DateTime.now(),
    cityId: cityId,
    area: area,
  );
  final progress = round == null ? null : await dao.roundProgress(round.id);
  final streets = await ref.watch(cityStreetsProvider.future);
  final byId = {for (final d in pack.districts()) d.id: d};
  final last = await dao.lastFinishedRound(city.id);
  return (
    pack: pack,
    saved: progress == null ? null : _saved(progress, streets),
    last: last == null ? null : _last(await dao.roundProgress(last.id)),
    recent: [
      for (final id in await dao.recentDistrictIds(city.id)) ?byId[id],
    ].take(recentAreaCount).toList(),
    before: introBefore == null ? null : await _memoryAt(ref, introBefore),
    learned: streetCardsOf(
      streets,
      await ref.watch(reviewedCardsProvider.future),
    ).length,
  );
});

Future<double> _memoryAt(Ref ref, DateTime t) async {
  final streets = await ref.watch(cityStreetsProvider.future);
  final cards = await ref.watch(streetCardsProvider.future);
  return cityMemoryAt(
    [for (final s in coreStreets(streets)) ?cards[s.id]],
    await ref.watch(learningDaoProvider).log(),
    t,
  );
}

LastRound _last(RoundProgress progress) => (
  round: progress.round,
  area: parseArea(progress.round.areaJson),
  tally: {
    for (final tier in Tier.values)
      tier: progress.answers.where((a) => a.tier == tier).length,
  },
  missed: progress.retryIds.length,
);

/// The saved round as resuming will play it: streets retired from the pack
/// don't count. Null when nothing is left to answer.
HomeSavedRound? _saved(
  RoundProgress progress,
  Map<String, NamedStreet> streets,
) {
  final playable = {
    for (final id in progress.planned)
      if (streets.containsKey(id)) id,
  };
  final answered = progress.answers.to(playable).length;
  if (answered >= playable.length) return null;
  return (
    round: progress.round,
    answered: answered,
    total: playable.length,
    at: progress.lastActiveAt,
  );
}
