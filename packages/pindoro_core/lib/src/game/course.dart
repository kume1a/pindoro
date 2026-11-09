import 'dart:math' as math;

import '../geo/geo.dart';
import '../pack/models.dart';
import 'named_street.dart';
import 'question_selector.dart';

abstract final class CourseRules {
  static const int streetsPerLesson = 4;
  static const int lessonsPerUnit = 6;

  /// The unit's Pit stop comes after this lesson (after the last one in a
  /// shorter unit).
  static const int pitStopAfter = 3;
}

/// What a finished lesson result was: a lesson, a practice of a done lesson,
/// or a unit's Pit stop.
enum LessonKind { lesson, practice, pitStop }

/// A lesson: its number in the unit (from 1) and its streets, in course order.
typedef CourseLesson = ({int number, List<NamedStreet> streets});

/// One raion of the course.
class CourseUnit {
  const CourseUnit({
    required this.number,
    required this.district,
    required this.lessons,
  });

  /// From 1, in course order.
  final int number;
  final District district;
  final List<CourseLesson> lessons;

  String get id => district.id;

  int get pitStopAfter => math.min(CourseRules.pitStopAfter, lessons.length);

  List<NamedStreet> get streets => [for (final l in lessons) ...l.streets];
}

const List<String> _classOrder = [
  'motorway',
  'trunk',
  'primary',
  'secondary',
  'tertiary',
];

int _classRank(NamedStreet s) {
  final i = _classOrder.indexOf(s.parts.first.roadClass);
  return i == -1 ? _classOrder.length : i;
}

/// The course of a city: one unit per raion with at least one full lesson,
/// [startDistrictId] first, then the others by distance from it. Each named
/// street of at least [QuestionSelector.minTotalLengthM] belongs to the raion
/// holding most of its length ([lengthsByDistrict]: district → part → metres);
/// a raion teaches its biggest road classes first, then its longest streets.
List<CourseUnit> buildCourse({
  required List<District> districts,
  required Iterable<NamedStreet> streets,
  required Map<String, Map<String, double>> lengthsByDistrict,
  required String startDistrictId,
}) {
  final raions = [
    for (final d in districts)
      if (d.kind == DistrictKind.district) d,
  ]..sort((a, b) => a.id.compareTo(b.id));
  if (raions.isEmpty) return const [];

  final byRaion = <String, List<NamedStreet>>{};
  for (final street in streets) {
    if (street.lengthM < QuestionSelector.minTotalLengthM) continue;
    String? home;
    var homeM = 0.0;
    for (final raion in raions) {
      final lengths = lengthsByDistrict[raion.id];
      if (lengths == null) continue;
      final m = street.parts.fold(0.0, (sum, p) => sum + (lengths[p.id] ?? 0));
      if (m > homeM) (home, homeM) = (raion.id, m);
    }
    if (home != null) byRaion.putIfAbsent(home, () => []).add(street);
  }

  final start = raions.firstWhere(
    (d) => d.id == startDistrictId,
    orElse: () => raions.first,
  );
  final ordered = [...raions]
    ..sort((a, b) {
      if (a == start || b == start) return a == start ? -1 : 1;
      return distanceBetween(
        start.center,
        a.center,
      ).compareTo(distanceBetween(start.center, b.center));
    });

  const perLesson = CourseRules.streetsPerLesson;
  final units = <CourseUnit>[];
  for (final raion in ordered) {
    final taught = (byRaion[raion.id] ?? [])
      ..sort((a, b) {
        final byClass = _classRank(a).compareTo(_classRank(b));
        if (byClass != 0) return byClass;
        final byLength = b.lengthM.compareTo(a.lengthM);
        return byLength != 0 ? byLength : a.id.compareTo(b.id);
      });
    final count = math.min(
      taught.length ~/ perLesson,
      CourseRules.lessonsPerUnit,
    );
    if (count == 0) continue;
    units.add(
      CourseUnit(
        number: units.length + 1,
        district: raion,
        lessons: [
          for (var i = 0; i < count; i++)
            (
              number: i + 1,
              streets: taught.sublist(i * perLesson, (i + 1) * perLesson),
            ),
        ],
      ),
    );
  }
  return units;
}

/// Where a city's course starts until the player picks: the raion holding
/// [lastPlayed] (the last Free play area), else the one holding the city
/// centre, else the one whose centre is nearest it. Null without raions.
String? startDistrict(
  List<District> districts, {
  LatLng? lastPlayed,
  required LatLng cityCenter,
}) {
  final raions = [
    for (final d in districts)
      if (d.kind == DistrictKind.district) d,
  ];
  if (raions.isEmpty) return null;
  for (final at in [?lastPlayed, cityCenter]) {
    for (final d in raions) {
      if (boundaryContains(d.boundary, at)) return d.id;
    }
  }
  raions.sort(
    (a, b) => distanceBetween(
      cityCenter,
      a.center,
    ).compareTo(distanceBetween(cityCenter, b.center)),
  );
  return raions.first.id;
}

enum StopKind { lesson, pitStop, finalDrive }

enum StopState { locked, current, done, perfect }

/// A stop on the path; [lesson] is the lesson's number for a lesson stop.
typedef CourseStop = ({StopKind kind, int? lesson, StopState state});

/// A finished lesson result, as the path reads it.
typedef LessonOutcome = ({
  String unitId,
  LessonKind kind,
  int? lesson,
  bool perfect,
});

typedef UnitProgress = ({
  CourseUnit unit,
  bool open,
  List<CourseStop> stops,
  int lessonsDone,
});

extension StopDone on CourseStop {
  bool get done => state == StopState.done || state == StopState.perfect;
}

/// Each unit's stops in path order: lessons up to [CourseUnit.pitStopAfter],
/// the Pit stop, the other lessons, the Final drive. A done stop shows done
/// (Perfect when its lesson's first result had no mistakes); in an open unit
/// the first stop that isn't done is current once the one before it is done.
/// The Pit stop is done with a result, or once the lessons before it are done
/// and [pitStopSizes] (unit id → streets to tune up) has nothing for it. The
/// Final drive stays locked until road trips exist; the next unit opens when
/// a unit's last lesson is done. Practice never changes a stop.
List<UnitProgress> courseProgress(
  List<CourseUnit> course,
  Iterable<LessonOutcome> results, {
  required Map<String, int> pitStopSizes,
}) {
  final lessons = <(String, int), bool>{};
  final pitStops = <String>{};
  for (final r in results) {
    switch (r.kind) {
      case LessonKind.lesson:
        lessons.putIfAbsent((r.unitId, r.lesson!), () => r.perfect);
      case LessonKind.pitStop:
        pitStops.add(r.unitId);
      case LessonKind.practice:
    }
  }

  var open = true;
  return [
    for (final unit in course)
      () {
        final unitOpen = open;
        bool lessonDone(int n) => lessons.containsKey((unit.id, n));
        final pitDone =
            pitStops.contains(unit.id) ||
            (List.generate(unit.pitStopAfter, (i) => i + 1).every(lessonDone) &&
                (pitStopSizes[unit.id] ?? 0) == 0);
        final plan = <({StopKind kind, int? lesson, bool done, bool perfect})>[
          for (final l in unit.lessons) ...[
            (
              kind: StopKind.lesson,
              lesson: l.number,
              done: lessonDone(l.number),
              perfect: lessons[(unit.id, l.number)] ?? false,
            ),
            if (l.number == unit.pitStopAfter)
              (
                kind: StopKind.pitStop,
                lesson: null,
                done: pitDone,
                perfect: false,
              ),
          ],
          (
            kind: StopKind.finalDrive,
            lesson: null,
            done: false,
            perfect: false,
          ),
        ];
        // Only the first stop that isn't done can be current.
        var canBeCurrent = unitOpen;
        final stops = <CourseStop>[
          for (final s in plan)
            () {
              final state = s.done
                  ? (s.perfect ? StopState.perfect : StopState.done)
                  : canBeCurrent && s.kind != StopKind.finalDrive
                  ? StopState.current
                  : StopState.locked;
              if (!s.done) canBeCurrent = false;
              return (kind: s.kind, lesson: s.lesson, state: state);
            }(),
        ];
        open = lessonDone(unit.lessons.last.number);
        return (
          unit: unit,
          open: unitOpen,
          stops: stops,
          lessonsDone: unit.lessons.where((l) => lessonDone(l.number)).length,
        );
      }(),
  ];
}

extension CourseCurrent on List<UnitProgress> {
  /// The current stop: its unit's and its own index.
  ({int unit, int stop})? get current {
    for (final (u, progress) in indexed) {
      final stop = progress.stops.indexWhere(
        (s) => s.state == StopState.current,
      );
      if (stop != -1) return (unit: u, stop: stop);
    }
    return null;
  }
}
