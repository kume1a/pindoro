import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';

typedef DistrictCount = ({District district, KnownCount count});

typedef HomeSavedRound = ({
  Round round,
  int answered,
  int total,
  int xp,
  DateTime at,
});

typedef HomeCounts = ({KnownCount city, Map<String, KnownCount> byDistrict});

typedef HomeData = ({
  PackRepository pack,
  int totalXp,
  HomeSavedRound? saved,
  KnownCount cityKnown,
  List<DistrictCount> districts,
  List<DistrictCount> recent,
  HomeCounts? before,
});

/// Home's data; with [introBefore], also the counts before that moment, where
/// the intro's numbers start.
final homeProvider = FutureProvider.autoDispose.family<HomeData, DateTime?>((
  ref,
  introBefore,
) async {
  final db = ref.watch(databaseProvider);
  final pack = await ref.watch(packRepositoryProvider.future);
  final city = pack.city();
  final round = await db.savedRound(DateTime.now());
  final progress = round == null ? null : await db.roundProgress(round.id);
  final streets = await ref.watch(cityStreetsProvider.future);
  final partsByDistrict = pack.partsByDistrict();
  Future<HomeCounts> countsAt({DateTime? before}) async => knownCounts(
    streets: streets,
    partsByDistrict: partsByDistrict,
    known: {
      for (final MapEntry(key: id, value: tier) in bestTierPerStreet(
        await db.bestTierByPart(city.id, before: before),
        streets,
      ).entries)
        if (isKnownTier(tier)) id,
    },
  );
  final counts = await countsAt();
  final districts = [
    for (final d in pack.districts())
      (district: d, count: counts.byDistrict[d.id] ?? (known: 0, total: 0)),
  ];
  final byId = {for (final d in districts) d.district.id: d};
  return (
    pack: pack,
    totalXp: await db.totalXp(),
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
      for (final id in await db.recentDistrictIds(city.id)) ?byId[id],
    ].take(2).toList(),
    before: introBefore == null ? null : await countsAt(before: introBefore),
  );
});
