import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/features/map/data/geojson.dart';
import 'package:pindoro_core/pindoro_core.dart';

void main() {
  test('masks the world with one hole per area polygon', () {
    const ring = [
      LatLng(41.7, 44.7),
      LatLng(41.8, 44.7),
      LatLng(41.8, 44.8),
      LatLng(41.7, 44.7),
    ];
    final geojson = areaMaskGeoJson(const [
      [ring],
      [ring],
    ]);
    final feature =
        (geojson['features'] as List<Object?>).single! as Map<String, Object?>;
    final rings =
        (feature['geometry']! as Map<String, Object?>)['coordinates']!
            as List<Object?>;
    expect(rings, hasLength(3));
    expect((rings.first! as List<Object?>).first, [-180.0, -85.0]);
    expect((rings[1]! as List<Object?>).first, [
      44.7,
      41.7,
    ], reason: 'GeoJSON is lon, lat');
  });
}
