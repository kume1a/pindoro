import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/features/course/data/course_data.dart';
import 'package:pindoro/features/pack/data/pack_store.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro/features/progress/data/streak.dart';
import 'package:pindoro_core/pindoro_core.dart';

typedef MeCity = ({
  String id,
  String nameKa,
  String nameEn,
  KnownCount count,

  /// The unit its course is on; null before its Path first opened.
  CourseUnit? unit,
});

typedef MeData = ({
  int totalXp,

  /// When the first round started; null before any.
  DateTime? since,
  int bestStreak,
  int lessonsDone,
  int roadTrips,

  /// The chosen city first, then the other played ones.
  List<MeCity> cities,
});

/// Me's numbers. Each city is counted in its own pack: the open one, or its
/// installed pack opened just for the count; a played city whose pack isn't
/// on the phone is left out.
final meProvider = FutureProvider.autoDispose<MeData>((ref) async {
  ref.watch(progressChangesProvider);
  final dao = ref.watch(progressDaoProvider);
  final open = await ref.watch(packRepositoryProvider.future);
  final openStreets = await ref.watch(cityStreetsProvider.future);
  final streak = await ref.watch(streakProvider.future);

  Future<MeCity> count(
    PackRepository pack,
    Map<String, NamedStreet> streets,
  ) async {
    final city = pack.city();
    return (
      id: city.id,
      nameKa: city.nameKa,
      nameEn: city.nameEn,
      count: (await dao.knownIn(pack, streets)).city,
      unit: switch (await dao.courseStart(city.id)) {
        final start? => currentUnitIn(
          pack,
          streets,
          start,
          await dao.lessonResultsIn(city.id),
        ),
        _ => null,
      },
    );
  }

  final cities = [await count(open, openStreets)];
  for (final id in await dao.recentCityIds()) {
    if (id == open.city().id) continue;
    final file = ref.read(packStoreProvider).newest(id);
    if (file == null) continue;
    final pack = SqlitePackRepository.open(file.path);
    try {
      cities.add(await count(pack, streetsByPartId(pack.streets())));
    } finally {
      pack.close();
    }
  }
  return (
    totalXp: await dao.totalXp(),
    since: await dao.firstPlayedAt(),
    bestStreak: streak.summary.best,
    lessonsDone: await dao.lessonsDone(),
    roadTrips: await dao.roadTrips(),
    cities: cities,
  );
});
