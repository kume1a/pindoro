import 'package:pindoro_core/pindoro_core.dart';

/// A place tapped on the map's every-place layers (SPEC §16.23 item 132): its OSM id when the
/// tiles carry one, its name and kind as the tiles have them, and its point.
typedef MapPlace = ({String? id, String? name, String kind, LatLng at});

/// The pack id (`osm:n123`) a Protomaps feature id stands for: `type << 44 | osm id`, the type 1
/// for a node, 2 a way, 3 a relation. Null for anything else.
String? osmIdOf(Object? raw) {
  final n = switch (raw) {
    final num n => n.toInt(),
    final String s => int.tryParse(s),
    _ => null,
  };
  if (n == null) return null;
  final type = switch (n >> 44) {
    1 => 'n',
    2 => 'w',
    3 => 'r',
    _ => null,
  };
  return type == null ? null : 'osm:$type${n & ((1 << 44) - 1)}';
}

/// The place nearest [near] among MapLibre's rendered [features] (GeoJSON points with the tiles'
/// `kind` and names); null without one.
MapPlace? mapPlaceAt(List<Object?> features, LatLng near) {
  MapPlace? best;
  var bestM = double.infinity;
  for (final f in features) {
    if (f case {
      'geometry': {
        'type': 'Point',
        'coordinates': [final num lon, final num lat],
      },
      'properties': final Map<Object?, Object?> props,
    }) {
      final at = LatLng(lat.toDouble(), lon.toDouble());
      final m = distanceBetween(near, at);
      if (m >= bestM) continue;
      bestM = m;
      best = (
        id: osmIdOf((f as Map)['id']),
        name: props['name'] as String?,
        kind: props['kind'] as String? ?? '',
        at: at,
      );
    }
  }
  return best;
}
