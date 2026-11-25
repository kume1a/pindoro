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
  // A cheap test before the distance to the lines.
  final box = Bbox.of(points).grown(nearM);
  return {
    for (final p in places)
      if (box.contains(p.at) &&
          pointToPolylineDistance(p.at, lines).distanceMeters <= nearM)
        ?featureIdOf(p.id),
  };
}
