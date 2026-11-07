import 'package:pindoro_core/pindoro_core.dart';

typedef Properties = Map<String, dynamic>;

List<double> _coord(LatLng p) => [p.lon, p.lat];

List<List<double>> _ring(Polyline ring) => [for (final p in ring) _coord(p)];

Map<String, dynamic> _collection(
  Iterable<(Map<String, dynamic> geometry, Properties properties)> features,
) => {
  'type': 'FeatureCollection',
  'features': [
    for (final (geometry, properties) in features)
      {'type': 'Feature', 'properties': properties, 'geometry': geometry},
  ],
};

Map<String, dynamic> pointsGeoJson(
  List<LatLng> points, {
  Properties properties = const {},
}) => labelledPointsGeoJson([for (final p in points) (p, properties)]);

/// One point feature per position, each with its own properties.
Map<String, dynamic> labelledPointsGeoJson(
  Iterable<(LatLng at, Properties properties)> points,
) => _collection([
  for (final (p, properties) in points)
    ({'type': 'Point', 'coordinates': _coord(p)}, properties),
]);

Map<String, dynamic> linesGeoJson(MultiPolyline lines) => _collection([
  if (lines.isNotEmpty)
    (
      {
        'type': 'MultiLineString',
        'coordinates': [for (final line in lines) _ring(line)],
      },
      const <String, dynamic>{},
    ),
]);

/// One feature per polygon (outer ring, then holes) with its properties.
Map<String, dynamic> polygonsGeoJson(
  Iterable<(List<Polyline> polygon, Properties properties)> polygons,
) => _collection([
  for (final (polygon, properties) in polygons)
    (
      {
        'type': 'Polygon',
        'coordinates': [for (final ring in polygon) _ring(ring)],
      },
      properties,
    ),
]);

const Polyline _world = [
  LatLng(-85, -180),
  LatLng(-85, 180),
  LatLng(85, 180),
  LatLng(85, -180),
  LatLng(-85, -180),
];

/// The world with every area polygon cut out; filled, it dims all but the
/// area. Holes in the area (enclaves outside it) come back as their own
/// polygons so they dim too, and a polygon lying inside a bigger one cuts no
/// second hole: overlapping holes would dim their overlap.
Map<String, dynamic> areaMaskGeoJson(List<List<Polyline>> boundary) {
  final outer = [for (final polygon in boundary) polygon.first];
  return polygonsGeoJson([
    (
      [
        _world,
        for (final (i, ring) in outer.indexed)
          if (!_insideBigger(ring, outer, i)) ring,
      ],
      const {},
    ),
    for (final polygon in boundary)
      for (final hole in polygon.skip(1)) ([hole], const {}),
  ]);
}

/// Whether most of ring [i]'s vertices lie in a ring with a bigger bbox.
/// Most, not all: a neighbourhood often shares edges with its district, and
/// a vertex on an edge counts either way.
bool _insideBigger(Polyline ring, List<Polyline> rings, int i) {
  double size(Polyline r) {
    final b = Bbox.of(r);
    return (b.maxLat - b.minLat) * (b.maxLon - b.minLon);
  }

  final own = size(ring);
  for (final (j, other) in rings.indexed) {
    if (j == i || size(other) <= own) continue;
    final inside = ring.where((p) => polygonContains([other], p)).length;
    if (inside * 2 > ring.length) return true;
  }
  return false;
}
