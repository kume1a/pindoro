import 'package:pindoro_core/pindoro_core.dart';
import 'package:test/test.dart';

void main() {
  test('difficulty pools are cumulative', () {
    expect(Difficulty.easy.pool, {Difficulty.easy});
    expect(Difficulty.medium.pool, {Difficulty.easy, Difficulty.medium});
    expect(Difficulty.hard.pool, {
      Difficulty.easy,
      Difficulty.medium,
      Difficulty.hard,
    });
    expect(Difficulty.expert.pool, Difficulty.values.toSet());
  });

  test('compassPoint names the direction from one point to another', () {
    const pin = LatLng(41.7, 44.75);
    expect(compassPoint(pin, const LatLng(41.71, 44.75)), CompassPoint.n);
    expect(compassPoint(pin, const LatLng(41.7, 44.76)), CompassPoint.e);
    expect(compassPoint(pin, const LatLng(41.69, 44.74)), CompassPoint.sw);
    expect(compassPoint(pin, const LatLng(41.71, 44.737)), CompassPoint.nw);
  });

  test('polygonContains respects holes', () {
    const outer = [
      LatLng(0, 0),
      LatLng(0, 10),
      LatLng(10, 10),
      LatLng(10, 0),
      LatLng(0, 0),
    ];
    const hole = [
      LatLng(4, 4),
      LatLng(4, 6),
      LatLng(6, 6),
      LatLng(6, 4),
      LatLng(4, 4),
    ];
    expect(polygonContains([outer], const LatLng(5, 5)), isTrue);
    expect(polygonContains([outer, hole], const LatLng(5, 5)), isFalse);
    expect(polygonContains([outer, hole], const LatLng(2, 2)), isTrue);
    expect(polygonContains([outer], const LatLng(11, 5)), isFalse);
  });

  group('knowledge', () {
    test('comes from the best tier', () {
      expect(knowledgeFrom(null), StreetKnowledge.unknown);
      expect(knowledgeFrom(Tier.perfect), StreetKnowledge.known);
      expect(knowledgeFrom(Tier.great), StreetKnowledge.known);
      expect(knowledgeFrom(Tier.close), StreetKnowledge.missed);
      expect(knowledgeFrom(Tier.miss), StreetKnowledge.missed);
    });

    // a1 and a2 are parts of one street; a3 shares its name 5.5 km away.
    final streets = streetsByPartId([
      _street('a1', 'A', 300, [
        [_p(41.70, 44.70), _p(41.70, 44.703)],
      ]),
      _street('a2', 'A', 200, [
        [_p(41.701, 44.70), _p(41.701, 44.702)],
      ]),
      _street('a3', 'A', 200, [
        [_p(41.75, 44.70), _p(41.75, 44.702)],
      ]),
      _street('b', 'B', 200, [
        [_p(41.72, 44.70), _p(41.72, 44.702)],
      ]),
    ]);

    test('is per street: a later miss never un-knows it', () {
      final best = bestTierPerStreet({
        'a2': Tier.great,
        'a1': Tier.miss,
        'b': Tier.close,
        'retired': Tier.perfect,
      }, streets);
      expect(best, {'a1': Tier.great, 'b': Tier.close});
    });

    test('a same-name street elsewhere stays unknown', () {
      final best = bestTierPerStreet({'a1': Tier.perfect}, streets);
      expect(best.containsKey('a3'), isFalse);
    });

    test('newlyKnown counts a street once and skips ones known before', () {
      expect(
        newlyKnown(
          knownBefore: {'A'},
          roundAnswers: [
            (street: 'A', tier: Tier.perfect),
            (street: 'B', tier: Tier.great),
            (street: 'B', tier: Tier.perfect),
            (street: 'C', tier: Tier.close),
          ],
        ),
        {'B'},
      );
    });

    test('knownCounts per city and district', () {
      final counts = knownCounts(
        streets: streets,
        partsByDistrict: {
          'd1': {'a1', 'a2', 'b'},
          'd2': {'a3'},
        },
        known: {'a1'},
      );
      expect(counts.city, (known: 1, total: 3));
      expect(counts.byDistrict['d1'], (known: 1, total: 2));
      expect(counts.byDistrict['d2'], (known: 0, total: 1));
    });
  });

  group('NamedStreet', () {
    final long = _street('l', 'A', 900, [
      [_p(41.70, 44.70), _p(41.70, 44.71)],
    ]);
    // About 220 m north of the long part.
    final short = _street('s', 'A', 200, [
      [_p(41.702, 44.70), _p(41.702, 44.701)],
    ], roadClass: 'primary');

    test('groups nearby parts by name, longest first', () {
      final groups = groupByName([short, _street('b', 'B', 10, []), long]);
      expect(groups.map((g) => g.name), ['A', 'B']);
      expect(groups.first.parts.map((p) => p.id), ['l', 's']);
      expect(groups.first.id, 'l');
      expect(groups.first.lengthM, 1100);
    });

    test('same-name parts far apart are different streets', () {
      final suburb = _street('far', 'A', 300, [
        [_p(41.75, 44.70), _p(41.75, 44.701)],
      ]);
      final groups = groupByName([long, suburb, short]);
      expect(groups.map((g) => g.parts.map((p) => p.id).toList()), [
        ['far'],
        ['l', 's'],
      ]);
    });

    test('a part bridging two groups joins them', () {
      final middle = _street('m', 'A', 100, [
        [_p(41.704, 44.70), _p(41.706, 44.70)],
      ]);
      final north = _street('n', 'A', 100, [
        [_p(41.709, 44.70), _p(41.71, 44.70)],
      ]);
      // long and north are ~1 km apart; middle is within 500 m of both.
      expect(groupByName([long, north]), hasLength(2));
      expect(groupByName([long, north, middle]).single.parts, hasLength(3));
    });

    test('scores against the nearest part with its road class', () {
      final street = groupByName([long, short]).single;
      // 25 m north of the short primary part: within primary's 30 m Perfect.
      const pin = LatLng(41.702225, 44.7005);
      final n = street.nearest(pin);
      expect(n.part.id, 's');
      expect(
        scoreAnswer(n.distanceM, n.part.roadClass, Difficulty.medium).tier,
        Tier.perfect,
      );
    });

    test('a street keeps one geometry list across reads', () {
      final street = groupByName([long, short]).single;
      expect(identical(street.geometry, street.geometry), isTrue);
    });
  });

  group('Area', () {
    final pack = _FakePack();

    test('round-trips through JSON', () {
      final areas = [
        const DistrictsArea({'osm:r2', 'osm:r1'}),
        const CircleArea(LatLng(41.7, 44.75), 2000),
        const RectArea(Bbox(41.69, 44.7, 41.72, 44.78)),
      ];
      for (final area in areas) {
        expect(Area.fromJson(area.toJson()), area);
      }
      expect(areas.first.toJson(), {
        'kind': 'districts',
        'ids': ['osm:r1', 'osm:r2'],
      });
    });

    test('unreadable JSON is a FormatException, never a TypeError', () {
      for (final bad in [
        {
          'kind': 'districts',
          'ids': [1],
        },
        {
          'kind': 'districts',
          'ids': ['osm:r1', null],
        },
        {'kind': 'rect', 'min_lat': 41.69},
      ]) {
        expect(() => Area.fromJson(bad), throwsFormatException, reason: '$bad');
      }
    });

    test('a rectangle around a centre has the asked sides', () {
      final rect = RectArea.around(const LatLng(41.7, 44.75), 2600, 3000);
      expect(rect.bounds.center.lat, closeTo(41.7, 1e-9));
      expect(rect.bounds.widthM, closeTo(2600, 0.5));
      expect(rect.bounds.heightM, closeTo(3000, 0.5));
    });

    test('reads the M1 one-district form and rejects the rest', () {
      expect(
        Area.fromJson({'kind': 'district', 'district_id': 'osm:r1'}),
        const DistrictsArea({'osm:r1'}),
      );
      expect(() => Area.fromJson({'kind': 'city'}), throwsFormatException);
    });

    test('resolves district shapes from the pack', () {
      final vake = const DistrictsArea({'osm:r1'}).shapeIn(pack)!;
      expect(vake.boundary, [_square]);
      expect(const DistrictsArea({'osm:r1', 'osm:r9'}).shapeIn(pack), isNull);
    });

    test('a circle is a closed 64-point ring of its radius', () {
      const circle = CircleArea(LatLng(41.7, 44.75), 1000);
      final ring = circle.shapeIn(pack).boundary.single.single;
      expect(ring, hasLength(65));
      expect(ring.first, ring.last);
      for (final p in ring) {
        expect(distanceBetween(circle.center, p), closeTo(1000, 1));
      }
    });
  });

  group('in-area rule', () {
    // 1 km east-west line at lat 41.7 starting at lon 44.7.
    final line = [_p(41.7, 44.7), _p(41.7, 44.7120566)];

    test('lengthInside measures the part inside a shape', () {
      const rect = RectArea(Bbox(41.69, 44.7, 41.71, 44.7060283));
      expect(lengthInside([line], rect.contains), closeTo(500, 25));
      const circle = CircleArea(LatLng(41.7, 44.7), 300);
      expect(lengthInside([line], circle.contains), closeTo(300, 25));
    });

    test('a part counts with 150 m inside or 30 % of its length', () {
      final pack = _FakePack(
        streetRows: [
          _street('mostly-out', 'A', 1000, [line]),
          _street('short-in', 'B', 120, [
            [_p(41.7, 44.7), _p(41.7, 44.7014468)],
          ]),
        ],
      );
      // Circle of 100 m around the line's start: 100 m of 'mostly-out'
      // (10 %, < 150 m) and all of 'short-in' (100 %).
      const circle = CircleArea(LatLng(41.7, 44.7), 100);
      expect(
        circle.streetsIn(pack, Difficulty.values.toSet()).map((s) => s.id),
        ['short-in'],
      );
      const wider = CircleArea(LatLng(41.7, 44.7), 200);
      expect(
        wider.streetsIn(pack, Difficulty.values.toSet()).map((s) => s.id),
        ['mostly-out', 'short-in'],
      );
    });
  });
}

LatLng _p(double lat, double lon) => LatLng(lat, lon);

Street _street(
  String id,
  String name,
  double lengthM,
  MultiPolyline geometry, {
  String roadClass = 'residential',
}) {
  final points = geometry.expand((l) => l).toList();
  return Street(
    id: id,
    nameKa: name,
    nameEn: null,
    roadClass: roadClass,
    difficulty: Difficulty.expert,
    lengthM: lengthM,
    midpoint: points.isEmpty ? const LatLng(0, 0) : points.first,
    bbox: points.isEmpty ? const Bbox(0, 0, 0, 0) : Bbox.of(points),
    geometry: geometry,
  );
}

const _square = [
  [
    LatLng(41.69, 44.7),
    LatLng(41.72, 44.7),
    LatLng(41.72, 44.78),
    LatLng(41.69, 44.7),
  ],
];

class _FakePack implements PackRepository {
  _FakePack({this.streetRows = const []});

  final List<Street> streetRows;

  @override
  City city() => const City(
    id: 'tbilisi',
    nameKa: 'თბილისი',
    nameEn: 'Tbilisi',
    osmRelationId: 1996871,
    center: LatLng(41.7, 44.8),
    bbox: Bbox(41.6, 44.6, 41.8, 45),
    areaM2: 504e6,
    boundary: [_square],
  );

  @override
  List<District> districts() => const [
    District(
      id: 'osm:r1',
      kind: DistrictKind.district,
      osmRelationId: 1,
      nameKa: 'ვაკე',
      nameEn: 'Vake',
      center: LatLng(41.7, 44.75),
      bbox: Bbox(41.69, 44.7, 41.72, 44.78),
      areaM2: 32e6,
      boundary: [_square],
    ),
  ];

  @override
  Map<String, String> meta() => const {};

  @override
  List<Street> streets({String? districtId, Set<Difficulty>? difficulties}) =>
      streetRows;

  @override
  Map<String, Set<String>> partsByDistrict() => const {};

  @override
  Map<String, Map<String, double>> lengthsByDistrict() => const {};

  @override
  void close() {}
}
