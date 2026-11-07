import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';

typedef DistrictCount = ({District district, KnownCount count});

typedef HomeSavedRound = ({
  Round round,
  int answered,
  int total,
  int xp,
  DateTime at,
});

typedef HomeData = ({
  PackRepository pack,
  int totalXp,
  HomeSavedRound? saved,
  KnownCount cityKnown,
  List<DistrictCount> districts,
  List<DistrictCount> recent,
  KnownCounts? before,

  /// Streets due in the Pit stop today.
  int pitStopDue,
});

/// Home's data; with [introBefore], also the counts before that moment, where
/// the intro's numbers start. It reloads whenever progress or the chosen city
/// and area change, also while Home waits under another screen.
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
  final partsByDistrict = pack.partsByDistrict();
  Future<KnownCounts> countsAt({DateTime? before}) async => knownCounts(
    streets: streets,
    partsByDistrict: partsByDistrict,
    known: knownStreetIds(
      await dao.bestTierByPart(city.id, before: before),
      streets,
    ),
  );
  final counts = await countsAt();
  final districts = [
    for (final d in pack.districts())
      (district: d, count: counts.byDistrict[d.id] ?? (known: 0, total: 0)),
  ];
  final byId = {for (final d in districts) d.district.id: d};
  return (
    pack: pack,
    totalXp: await dao.totalXp(),
    saved: progress == null ? null : _saved(progress, streets),
    cityKnown: counts.city,
    districts: districts,
    recent: [
      for (final id in await dao.recentDistrictIds(city.id)) ?byId[id],
    ].take(2).toList(),
    before: introBefore == null ? null : await countsAt(before: introBefore),
    pitStopDue: (await dao.pitStop(
      city.id,
    )).dueIn(streets, calendarDay(DateTime.now())).length,
  );
});

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
  final answered = progress.answers
      .where((a) => playable.contains(a.streetId))
      .length;
  if (answered >= playable.length) return null;
  return (
    round: progress.round,
    answered: answered,
    total: playable.length,
    xp: progress.answers.xp,
    at: progress.lastActiveAt,
  );
}
