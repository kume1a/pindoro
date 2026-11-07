import 'package:pindoro_core/pindoro_core.dart';

List<double> _coord(LatLng p) => [p.lon, p.lat];

Map<String, dynamic> _collection(List<Map<String, dynamic>> geometries) => {
  'type': 'FeatureCollection',
  'features': [
    for (final g in geometries)
      {'type': 'Feature', 'properties': <String, dynamic>{}, 'geometry': g},
  ],
};

Map<String, dynamic> pointsGeoJson(List<LatLng> points) => _collection([
  for (final p in points) {'type': 'Point', 'coordinates': _coord(p)},
]);

Map<String, dynamic> linesGeoJson(MultiPolyline lines) => _collection([
  if (lines.isNotEmpty)
    {
      'type': 'MultiLineString',
      'coordinates': [
        for (final line in lines) [for (final p in line) _coord(p)],
      ],
    },
]);

/// The world with every area polygon cut out; filled, it dims all but the area.
Map<String, dynamic> areaMaskGeoJson(List<List<Polyline>> boundary) =>
    _collection([
      {
        'type': 'Polygon',
        'coordinates': [
          const [
            [-180.0, -85.0],
            [180.0, -85.0],
            [180.0, 85.0],
            [-180.0, 85.0],
            [-180.0, -85.0],
          ],
          for (final polygon in boundary)
            [for (final p in polygon.first) _coord(p)],
        ],
      },
    ]);
