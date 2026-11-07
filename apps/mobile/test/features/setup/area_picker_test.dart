import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/features/setup/data/area_tree.dart';
import 'package:pindoro/features/setup/ui/area_map.dart';
import 'package:pindoro_core/pindoro_core.dart';

District _area(
  String id,
  DistrictKind kind,
  double lat0,
  double lon0,
  double size,
) => District(
  id: id,
  kind: kind,
  osmRelationId: null,
  nameKa: id,
  nameEn: null,
  center: LatLng(lat0 + size / 2, lon0 + size / 2),
  bbox: Bbox(lat0, lon0, lat0 + size, lon0 + size),
  areaM2: size * size,
  boundary: [
    [
      [
        LatLng(lat0, lon0),
        LatLng(lat0, lon0 + size),
        LatLng(lat0 + size, lon0 + size),
        LatLng(lat0 + size, lon0),
        LatLng(lat0, lon0),
      ],
    ],
  ],
);

void main() {
  final west = _area('west', DistrictKind.district, 41.7, 44.7, 0.1);
  final east = _area('east', DistrictKind.district, 41.7, 44.8, 0.1);
  final quarter = _area('quarter', DistrictKind.quarter, 41.72, 44.72, 0.04);
  final corner = _area(
    'corner',
    DistrictKind.neighbourhood,
    41.73,
    44.73,
    0.01,
  );
  final outside = _area(
    'outside',
    DistrictKind.neighbourhood,
    41.9,
    44.95,
    0.01,
  );
  final areas = [west, east, quarter, corner, outside];

  test('a tap picks a district zoomed out, the smallest neighbourhood in', () {
    const inCorner = LatLng(41.735, 44.735);
    expect(areaAt(areas, inCorner, 10)?.id, 'west');
    expect(areaAt(areas, inCorner, 13)?.id, 'corner');
    expect(areaAt(areas, const LatLng(41.75, 44.85), 13)?.id, 'east');
    expect(areaAt(areas, const LatLng(42, 45), 13), isNull);
  });

  test('neighbourhoods group under their district, else the nearest', () {
    final groups = {
      for (final g in groupByDistrict(areas))
        g.district.id: [for (final p in g.parts) p.id],
    };
    expect(groups, {
      'west': ['quarter', 'corner'],
      'east': ['outside'],
    });
  });

  test('a district takes its areas in; a tap inside it narrows the pick', () {
    final tree = AreaTree(areas);
    var picked = {'corner', 'outside'};
    bool tap(String id) {
      final step = tree.toggle(picked, id);
      picked = step.picked;
      return step.narrowed;
    }

    expect(tap('west'), isFalse);
    expect(picked, {'outside', 'west'});
    expect(tap('quarter'), isTrue);
    expect(picked, {'outside', 'quarter'});
    expect(tap('quarter'), isFalse);
    expect(picked, {'outside'});
    expect(tree.normalise({'west', 'corner', 'east'}), {'west', 'east'});
  });

  test('street counts join the areas without counting a street twice', () {
    const byArea = {
      'west': {'a', 'b'},
      'quarter': {'b', 'c'},
    };
    expect(streetCount(byArea, ['west', 'quarter', 'unknown']), 3);
  });
}
