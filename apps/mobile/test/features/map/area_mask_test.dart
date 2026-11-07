import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/features/map/data/geojson.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// The mask's polygons, each as its list of rings.
List<List<Object?>> _polygons(Map<String, dynamic> geojson) => [
  for (final f in geojson['features'] as List<Object?>)
    ((f! as Map<String, Object?>)['geometry']!
            as Map<String, Object?>)['coordinates']!
        as List<Object?>,
];

Polyline _square(double lat, double lon, double d) => [
  LatLng(lat, lon),
  LatLng(lat, lon + d),
  LatLng(lat + d, lon + d),
  LatLng(lat + d, lon),
  LatLng(lat, lon),
];

void main() {
  test('masks the world with one hole per area polygon', () {
    const ring = [
      LatLng(41.7, 44.7),
      LatLng(41.8, 44.7),
      LatLng(41.8, 44.8),
      LatLng(41.7, 44.7),
    ];
    final rings = _polygons(
      areaMaskGeoJson(const [
        [ring],
        [ring],
      ]),
    ).single;
    expect(rings, hasLength(3));
    expect((rings.first! as List<Object?>).first, [-180.0, -85.0]);
    expect((rings[1]! as List<Object?>).first, [
      44.7,
      41.7,
    ], reason: 'GeoJSON is lon, lat');
  });

  test('an enclave in the area stays dimmed', () {
    final polygons = _polygons(
      areaMaskGeoJson([
        [_square(41.7, 44.7, 0.1), _square(41.74, 44.74, 0.02)],
      ]),
    );
    expect(polygons, hasLength(2), reason: 'the world, then the enclave');
    expect(polygons.first, hasLength(2), reason: 'world + the outer ring');
    expect(polygons.last, hasLength(1));
  });

  test('an area inside a bigger picked one cuts no second hole', () {
    final rings = _polygons(
      areaMaskGeoJson([
        [_square(41.7, 44.7, 0.1)],
        [_square(41.72, 44.72, 0.02)],
      ]),
    ).single;
    expect(rings, hasLength(2), reason: 'the world + the district');
  });
}
