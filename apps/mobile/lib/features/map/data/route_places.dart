import 'dart:math';

import 'package:pindoro/features/map/data/map_places.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// How near the route a place stays on Guided's map while it follows the car (item 135).
const double placesNearRouteM = 100;

/// The tile feature ids of the [places] within [nearM] of [lines]: the places Guided's map
/// keeps while it follows the car (SPEC §16.23 item 135).
Set<int> placesNear(
  MultiPolyline lines,
  Iterable<Landmark> places, {
  double nearM = placesNearRouteM,
}) {
  final points = [for (final line in lines) ...line];
  if (points.isEmpty) return const {};
  final box = Bbox.of(points);
  // The box grown by [nearM]: a cheap test before the distance to the lines.
  final dLat = nearM / 111320;
  final dLon = dLat / cos(box.center.lat * pi / 180);
  return {
    for (final p in places)
      if (p.at.lat >= box.minLat - dLat &&
          p.at.lat <= box.maxLat + dLat &&
          p.at.lon >= box.minLon - dLon &&
          p.at.lon <= box.maxLon + dLon &&
          pointToPolylineDistance(p.at, lines).distanceMeters <= nearM)
        ?featureIdOf(p.id),
  };
}
