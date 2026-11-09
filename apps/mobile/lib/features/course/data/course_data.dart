import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// The open city's course: its pack, its named streets (by any part id) and
/// its units.
typedef CoursePlan = ({
  PackRepository pack,
  Map<String, NamedStreet> streets,
  List<CourseUnit> units,
});

/// The open city's course, built from its pack and its saved start raion;
/// the first open picks and saves the start (pindoro_core `startDistrict`).
/// Null for a city without raions. Kept while the pack stays open: the Path,
/// a lesson and Lesson complete all read it.
final coursePlanProvider = FutureProvider<CoursePlan?>((ref) async {
  final dao = ref.watch(progressDaoProvider);
  final streetsFuture = ref.watch(cityStreetsProvider.future);
  final pack = await ref.watch(packRepositoryProvider.future);
  final streets = await streetsFuture;
  final city = pack.city();
  final districts = pack.districts();
  var start = await dao.courseStart(city.id);
  if (start == null) {
    final lastPlayed = (await dao.lastRoundArea(city.id))?.shapeIn(pack);
    start = startDistrict(
      districts,
      lastPlayed: lastPlayed?.bbox.center,
      cityCenter: city.center,
    );
    if (start == null) return null;
    await dao.saveCourseStart(city.id, start);
  }
  final units = buildCourse(
    districts: districts,
    streets: {...streets.values},
    lengthsByDistrict: pack.lengthsByDistrict(),
    startDistrictId: start,
  );
  return units.isEmpty ? null : (pack: pack, streets: streets, units: units);
});

typedef CourseData = ({
  CoursePlan plan,
  List<UnitProgress> units,

  /// Each lesson's first result, by unit id and lesson number.
  Map<(String, int), LessonResult> firstResults,

  /// Each unit's Pit stop streets (first-try mistakes still in the pack).
  Map<String, List<String>> pitStops,
});

/// Where the open city's course stands.
final courseProvider = FutureProvider.autoDispose<CourseData?>((ref) async {
  ref.watch(progressChangesProvider);
  final plan = await ref.watch(coursePlanProvider.future);
  if (plan == null) return null;
  final dao = ref.watch(progressDaoProvider);
  final cityId = plan.pack.city().id;
  final results = await dao.lessonResultsIn(cityId);
  final pitStops = {
    for (final unit in plan.units)
      unit.id: [
        for (final id in await dao.unitMistakes(
          cityId,
          unit.id,
          throughLesson: unit.pitStopAfter,
        ))
          if (plan.streets[id] case final s?) s.id,
      ],
  };
  final firstResults = <(String, int), LessonResult>{};
  for (final r in results) {
    if (r.kind == LessonKind.lesson) {
      firstResults.putIfAbsent((r.unitId, r.lesson!), () => r);
    }
  }
  return (
    plan: plan,
    units: courseProgress(
      plan.units,
      [
        for (final r in results)
          (
            unitId: r.unitId,
            kind: r.kind,
            lesson: r.lesson,
            perfect: r.perfect,
          ),
      ],
      pitStopSizes: {for (final e in pitStops.entries) e.key: e.value.length},
    ),
    firstResults: firstResults,
    pitStops: pitStops,
  );
});

/// A stop on the path, as the unlock names the one just finished.
typedef StopRef = ({String unitId, StopKind kind, int? lesson});

/// Counts taps on the open Path tab; the Path scrolls to its current stop.
class PathRetap extends Notifier<int> {
  @override
  int build() => 0;

  void tap() => state++;
}

final pathRetapProvider = NotifierProvider<PathRetap, int>(PathRetap.new);

/// The stop whose unlock the Path plays next; it clears it when it starts.
class PathUnlock extends Notifier<StopRef?> {
  @override
  StopRef? build() => null;

  void play(StopRef stop) => state = stop;

  StopRef? take() {
    final stop = state;
    state = null;
    return stop;
  }
}

final pathUnlockProvider = NotifierProvider<PathUnlock, StopRef?>(
  PathUnlock.new,
);

/// The unit a city's course is on (its last open unit), from its pack, its
/// saved [start] raion and its lesson [results].
CourseUnit? currentUnitIn(
  PackRepository pack,
  Map<String, NamedStreet> streets,
  String start,
  List<LessonResult> results,
) {
  final units = courseProgress(
    buildCourse(
      districts: pack.districts(),
      streets: {...streets.values},
      lengthsByDistrict: pack.lengthsByDistrict(),
      startDistrictId: start,
    ),
    [
      for (final r in results)
        (unitId: r.unitId, kind: r.kind, lesson: r.lesson, perfect: r.perfect),
    ],
    pitStopSizes: const {},
  );
  return units.isEmpty ? null : units.lastWhere((u) => u.open).unit;
}
