import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/features/map/data/map_places.dart';
import 'package:pindoro/features/map/data/route_places.dart';
import 'package:pindoro_core/pindoro_core.dart';

void main() {
  const o = LatLng(41.7, 44.8);
  LatLng at(double east, double north) =>
      LocalProjection(o).unproject((east, north));
  Landmark place(String id, LatLng p) => Landmark(
    id: id,
    kind: 'cafe',
    nameKa: id,
    nameEn: id,
    brand: null,
    salience: 0,
    at: p,
  );

  test('a pack id and its tile feature id go both ways', () {
    expect(featureIdOf('osm:n123'), 1 << 44 | 123);
    expect(osmIdOf(featureIdOf('osm:w45')), 'osm:w45');
    expect(featureIdOf('junction:7'), isNull);
  });

  test('only the places within 100 m of the route stay, by their tile ids', () {
    final route = [
      [at(0, 0), at(1000, 0)],
    ];
    final kept = placesNear(route, [
      place('osm:n1', at(500, 60)),
      place('osm:n2', at(500, 140)),
      place('osm:n3', at(1080, 0)),
      place('osm:n4', at(-300, 0)),
    ]);
    expect(kept, {featureIdOf('osm:n1'), featureIdOf('osm:n3')});
    expect(placesNear(const [], [place('osm:n1', at(0, 0))]), isEmpty);
  });
}
