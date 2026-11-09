import 'package:pindoro_core/pindoro_core.dart';
import 'package:test/test.dart';

/// A square district of side 0.01° whose south-west corner is [lat], [lon].
District _district(
  String id, {
  required double lat,
  required double lon,
  DistrictKind kind = DistrictKind.district,
}) {
  final ring = [
    LatLng(lat, lon),
    LatLng(lat + 0.01, lon),
    LatLng(lat + 0.01, lon + 0.01),
    LatLng(lat, lon + 0.01),
    LatLng(lat, lon),
  ];
  return District(
    id: id,
    kind: kind,
    osmRelationId: null,
    nameKa: id,
    nameEn: id,
    center: LatLng(lat + 0.005, lon + 0.005),
    bbox: Bbox(lat, lon, lat + 0.01, lon + 0.01),
    areaM2: 1e6,
    boundary: [
      [ring],
    ],
  );
}

NamedStreet _street(
  String id, {
  double lengthM = 500,
  String roadClass = 'residential',
}) => NamedStreet([
  Street(
    id: id,
    nameKa: 'name $id',
    nameEn: null,
    roadClass: roadClass,
    difficulty: Difficulty.expert,
    lengthM: lengthM,
    midpoint: const LatLng(0, 0),
    bbox: const Bbox(0, 0, 0, 0),
    geometry: const [
      [LatLng(0, 0)],
    ],
  ),
]);

/// [count] streets in [districtId] named `<districtId>-<i>`, longest first.
({List<NamedStreet> streets, Map<String, double> lengths}) _many(
  String districtId,
  int count,
) {
  final streets = [
    for (var i = 0; i < count; i++)
      _street('$districtId-$i', lengthM: 1000.0 - i),
  ];
  return (
    streets: streets,
    lengths: {for (final s in streets) s.id: s.lengthM},
  );
}

LessonOutcome _lesson(String unit, int n, {bool perfect = false}) => (
  unitId: unit,
  kind: LessonKind.lesson,
  lesson: n,
  perfect: perfect,
  passed: false,
);

/// A Final drive trip of [unit].
LessonOutcome _trip(String unit, {bool passed = true}) => (
  unitId: unit,
  kind: LessonKind.finalDrive,
  lesson: null,
  perfect: false,
  passed: passed,
);

/// Every lesson and the Pit stop of [unit] (6 lessons).
List<LessonOutcome> _allLessons(String unit) => [
  for (var n = 1; n <= 6; n++) _lesson(unit, n),
  (
    unitId: unit,
    kind: LessonKind.pitStop,
    lesson: null,
    perfect: false,
    passed: false,
  ),
];

void main() {
  final a = _district('a', lat: 41.70, lon: 44.70);
  final b = _district('b', lat: 41.70, lon: 44.75);
  final c = _district('c', lat: 41.70, lon: 44.72);
  final quarter = _district(
    'q',
    lat: 41.70,
    lon: 44.70,
    kind: DistrictKind.quarter,
  );

  group('buildCourse', () {
    test('one unit per raion, the start first, then by distance', () {
      final inA = _many('a', 24);
      final inB = _many('b', 24);
      final inC = _many('c', 24);
      final course = buildCourse(
        districts: [a, b, c, quarter],
        streets: [...inA.streets, ...inB.streets, ...inC.streets],
        lengthsByDistrict: {
          'a': inA.lengths,
          'b': inB.lengths,
          'c': inC.lengths,
          'q': inA.lengths,
        },
        startDistrictId: 'b',
      );
      expect([for (final u in course) u.id], ['b', 'c', 'a']);
      expect([for (final u in course) u.number], [1, 2, 3]);
      expect(course.first.lessons, hasLength(6));
      expect(course.first.lessons.first.streets.map((s) => s.id), [
        'b-0',
        'b-1',
        'b-2',
        'b-3',
      ]);
      expect(course.first.streets, hasLength(24));
    });

    test('a street belongs to the raion holding most of it', () {
      final shared = _street('shared', lengthM: 900);
      final rest = _many('a', 3);
      final course = buildCourse(
        districts: [a, b],
        streets: [shared, ...rest.streets],
        lengthsByDistrict: {
          'a': {...rest.lengths, 'shared': 600},
          'b': {'shared': 300},
        },
        startDistrictId: 'a',
      );
      expect(course.single.id, 'a');
      expect(course.single.streets.map((s) => s.id), contains('shared'));
    });

    test('bigger road classes first, short streets skipped', () {
      final course = buildCourse(
        districts: [a],
        streets: [
          _street('long', lengthM: 3000),
          _street('primary', roadClass: 'primary'),
          _street('trunk', roadClass: 'trunk'),
          _street('tertiary', roadClass: 'tertiary'),
          _street('short', lengthM: 100, roadClass: 'trunk'),
        ],
        lengthsByDistrict: {
          'a': {
            'long': 3000,
            'primary': 500,
            'trunk': 500,
            'tertiary': 500,
            'short': 100,
          },
        },
        startDistrictId: 'a',
      );
      expect(course.single.streets.map((s) => s.id), [
        'trunk',
        'primary',
        'tertiary',
        'long',
      ]);
    });

    test('full lessons only; a raion without one is no unit', () {
      final inA = _many('a', 5);
      final inB = _many('b', 3);
      final course = buildCourse(
        districts: [a, b],
        streets: [...inA.streets, ...inB.streets],
        lengthsByDistrict: {'a': inA.lengths, 'b': inB.lengths},
        startDistrictId: 'b',
      );
      expect(course.single.id, 'a');
      expect(course.single.lessons, hasLength(1));
      expect(course.single.pitStopAfter, 1);
    });
  });

  group('startDistrict', () {
    test('the raion holding the last played area, then the centre', () {
      expect(
        startDistrict(
          [a, b, quarter],
          lastPlayed: const LatLng(41.705, 44.755),
          cityCenter: const LatLng(41.705, 44.705),
        ),
        'b',
      );
      expect(
        startDistrict([a, b], cityCenter: const LatLng(41.705, 44.705)),
        'a',
      );
    });

    test(
      'the nearest raion when none holds the centre; null without raions',
      () {
        expect(
          startDistrict([a, b], cityCenter: const LatLng(41.705, 44.80)),
          'b',
        );
        expect(
          startDistrict([quarter], cityCenter: const LatLng(41.705, 44.705)),
          isNull,
        );
      },
    );
  });

  group('courseProgress', () {
    final inA = _many('a', 24);
    final inB = _many('b', 24);
    final course = buildCourse(
      districts: [a, b],
      streets: [...inA.streets, ...inB.streets],
      lengthsByDistrict: {'a': inA.lengths, 'b': inB.lengths},
      startDistrictId: 'a',
    );

    List<StopState> states(List<UnitProgress> p, int unit) => [
      for (final s in p[unit].stops) s.state,
    ];

    test('a new course: lesson 1 current, the rest locked', () {
      final p = courseProgress(course, const [], pitStopSizes: const {});
      expect(p.first.open, isTrue);
      expect(p.last.open, isFalse);
      expect(
        [for (final s in p.first.stops) s.kind],
        [
          StopKind.lesson,
          StopKind.lesson,
          StopKind.lesson,
          StopKind.pitStop,
          StopKind.lesson,
          StopKind.lesson,
          StopKind.lesson,
          StopKind.finalDrive,
        ],
      );
      expect(states(p, 0), [
        StopState.current,
        ...List.filled(7, StopState.locked),
      ]);
      expect(states(p, 1), List.filled(8, StopState.locked));
      expect(p.current, (unit: 0, stop: 0));
    });

    test('done and Perfect lessons; the Pit stop comes due after lesson 3', () {
      final p = courseProgress(
        course,
        [
          _lesson('a', 1),
          _lesson('a', 2, perfect: true),
          _lesson('a', 3),
          (
            unitId: 'a',
            kind: LessonKind.practice,
            lesson: 4,
            perfect: true,
            passed: false,
          ),
        ],
        pitStopSizes: const {'a': 2},
      );
      expect(states(p, 0).take(5), [
        StopState.done,
        StopState.perfect,
        StopState.done,
        StopState.current,
        StopState.locked,
      ]);
      expect(p.first.lessonsDone, 3);
      expect(p.current, (unit: 0, stop: 3));
    });

    test('the Pit stop is done with a result or with nothing to tune up', () {
      final lessons = [_lesson('a', 1), _lesson('a', 2), _lesson('a', 3)];
      final empty = courseProgress(course, lessons, pitStopSizes: const {});
      expect(empty.first.stops[3].state, StopState.done);
      expect(empty.first.stops[4].state, StopState.current);
      final played = courseProgress(
        course,
        [
          ...lessons,
          (
            unitId: 'a',
            kind: LessonKind.pitStop,
            lesson: null,
            perfect: false,
            passed: false,
          ),
        ],
        pitStopSizes: const {'a': 4},
      );
      expect(played.first.stops[3].state, StopState.done);
    });

    test('the Final drive comes due after lesson 6; the next unit waits', () {
      final p = courseProgress(
        course,
        _allLessons('a'),
        pitStopSizes: const {},
      );
      expect(p.first.stops.last.state, StopState.current);
      expect(p.first.tripsPassed, 0);
      expect(p.last.open, isFalse);
      expect(p.current, (unit: 0, stop: 7));
    });

    test('3 passed trips pass the Final drive and open the next unit', () {
      final p = courseProgress(course, [
        ..._allLessons('a'),
        _trip('a'),
        _trip('a', passed: false),
        _trip('a'),
      ], pitStopSizes: const {});
      expect(p.first.tripsPassed, 2);
      expect(p.first.done, isFalse);
      expect(p.first.stops.last.state, StopState.current);
      final passed = courseProgress(course, [
        ..._allLessons('a'),
        for (var i = 0; i < 3; i++) _trip('a'),
      ], pitStopSizes: const {});
      expect(passed.first.done, isTrue);
      expect(passed.first.stops.last.state, StopState.perfect);
      expect(passed.last.open, isTrue);
      expect(passed.current, (unit: 1, stop: 0));
    });

    test('Jump ahead marks the unit and every one before it done', () {
      final inC = _many('c', 24);
      final three = buildCourse(
        districts: [a, b, c],
        streets: [...inA.streets, ...inB.streets, ...inC.streets],
        lengthsByDistrict: {
          'a': inA.lengths,
          'b': inB.lengths,
          'c': inC.lengths,
        },
        startDistrictId: 'a',
      );
      expect([for (final u in three) u.id], ['a', 'c', 'b']);
      final p = courseProgress(three, [
        _lesson('a', 1, perfect: true),
        for (var i = 0; i < 3; i++) _trip('c'),
      ], pitStopSizes: const {});
      expect([for (final u in p) u.done], [true, true, false]);
      expect([for (final u in p) u.open], [true, true, true]);
      // Played lessons keep their star; skipped stops show a check.
      expect(states(p, 0).first, StopState.perfect);
      expect(states(p, 0).skip(1), everyElement(StopState.done));
      expect(states(p, 1).last, StopState.perfect);
      expect(p[1].lessonsDone, 6);
      expect(p.current, (unit: 2, stop: 0));
    });
  });

  group('placement', () {
    final inA = _many('a', 24);
    final inB = _many('b', 24);
    final inC = _many('c', 24);
    final three = buildCourse(
      districts: [a, b, c],
      streets: [...inA.streets, ...inB.streets, ...inC.streets],
      lengthsByDistrict: {'a': inA.lengths, 'b': inB.lengths, 'c': inC.lengths},
      startDistrictId: 'a',
    );

    test('a lesson is placed with 3 of its 4 streets known', () {
      final lesson1 = [for (final s in three.first.lessons.first.streets) s.id];
      expect(placeLessons(three, lesson1.take(2).toSet()), isEmpty);
      expect(placeLessons(three, lesson1.take(3).toSet()), [('a', 1)]);
      expect(placeLessons(three, lesson1.toSet()), [('a', 1)]);
    });

    test('placed lessons are done, never Perfect, and counted', () {
      final p = courseProgress(three, [
        _placed('a', 1),
        _placed('a', 2),
        _placed('a', 5),
      ], pitStopSizes: const {});
      expect(
        [for (final s in p.first.stops.take(3)) s.state],
        [StopState.done, StopState.done, StopState.current],
      );
      expect(p.first.stops[5].state, StopState.done, reason: 'lesson 5');
      expect(p.first.lessonsDone, 3);
      expect(p.current, (unit: 0, stop: 2));
    });

    test('a fully placed unit is done once the one before it is', () {
      expect([for (final u in three) u.id], ['a', 'c', 'b']);
      final p = courseProgress(three, [
        for (var n = 1; n <= 6; n++) _placed('a', n),
        for (var n = 1; n <= 6; n++) _placed('b', n),
        _placed('c', 1),
      ], pitStopSizes: const {});
      expect([for (final u in p) u.done], [true, false, false]);
      expect(p.first.stops.last.state, StopState.done, reason: 'a check');
      expect(p[1].stops.first.state, StopState.done, reason: 'c is open');
      expect(p[2].open, isFalse);
      expect(p[2].stops.first.state, StopState.locked, reason: 'b is locked');
      expect(p[2].lessonsDone, 0);
      expect(p.current, (unit: 1, stop: 1));

      final cDriven = courseProgress(three, [
        for (var n = 1; n <= 6; n++) _placed('a', n),
        for (var n = 1; n <= 6; n++) _placed('b', n),
        for (var i = 0; i < 3; i++) _trip('c'),
      ], pitStopSizes: const {});
      expect([for (final u in cDriven) u.done], [true, true, true]);
      expect(cDriven.current, isNull);
    });

    test('raionsFrom: the raion holding the point, then by distance', () {
      const inB = LatLng(41.705, 44.755);
      expect(
        [
          for (final d in raionsFrom([a, b, c], inB)) d.id,
        ],
        ['b', 'c', 'a'],
      );
      const westOfA = LatLng(41.705, 44.60);
      expect(
        [
          for (final d in raionsFrom([c, b, a], westOfA)) d.id,
        ],
        ['a', 'c', 'b'],
      );
    });
  });
}

/// A lesson of [unit] marked done by placement.
LessonOutcome _placed(String unit, int n) => (
  unitId: unit,
  kind: LessonKind.placed,
  lesson: n,
  perfect: false,
  passed: false,
);
