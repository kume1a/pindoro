import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
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
});

/// Home's data; with [introBefore], also the counts before that moment, where
/// the intro's numbers start.
final homeProvider = FutureProvider.autoDispose.family<HomeData, DateTime?>((
  ref,
  introBefore,
) async {
  final dao = ref.watch(progressDaoProvider);
  final pack = await ref.watch(packRepositoryProvider.future);
  final city = pack.city();
  final round = await dao.savedRound(DateTime.now());
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
    saved: progress == null
        ? null
        : (
            round: progress.round,
            answered: progress.answers.length,
            total: progress.planned.length,
            xp: progress.answers.fold(0, (sum, a) => sum + a.xp),
            at:
                progress.answers.lastOrNull?.createdAt ??
                progress.round.startedAt,
          ),
    cityKnown: counts.city,
    districts: districts,
    recent: [
      for (final id in await dao.recentDistrictIds(city.id)) ?byId[id],
    ].take(2).toList(),
    before: introBefore == null ? null : await countsAt(before: introBefore),
  );
});
