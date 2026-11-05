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

  test('knowledge comes from the last tier', () {
    expect(knowledgeFrom(null), StreetKnowledge.unknown);
    expect(knowledgeFrom(Tier.perfect), StreetKnowledge.known);
    expect(knowledgeFrom(Tier.great), StreetKnowledge.known);
    expect(knowledgeFrom(Tier.close), StreetKnowledge.missed);
    expect(knowledgeFrom(Tier.miss), StreetKnowledge.missed);
  });

  group('Area', () {
    final pack = _FakePack();

    test('round-trips through JSON', () {
      for (final area in [const WholeCity(), const DistrictArea('osm:r1')]) {
        expect(Area.fromJson(area.toJson()), area);
      }
      expect(const DistrictArea('osm:r1').toJson(), {
        'kind': 'district',
        'district_id': 'osm:r1',
      });
      expect(() => Area.fromJson({'district_id': 'x'}), throwsFormatException);
    });

    test('resolves its shape from the pack', () {
      expect(const WholeCity().shapeIn(pack).areaM2, 504e6);
      expect(const WholeCity().districtId, isNull);
      final vake = const DistrictArea('osm:r1').shapeIn(pack)!;
      expect(vake.name, 'ვაკე');
      expect(vake.areaM2, 32e6);
      expect(vake.boundary, [_square]);
      expect(const DistrictArea('osm:r9').shapeIn(pack), isNull);
    });
  });
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
      const [];

  @override
  List<StreetDistrict> streetDistricts(String streetId) => const [];

  @override
  Map<String, String> streetNames(Iterable<String> ids) => const {};

  @override
  void close() {}
}
