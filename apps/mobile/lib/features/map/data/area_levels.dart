import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart' show PindoroCamera;

/// Districts show below [PindoroCamera.areaDetailZoom]; from it on, the
/// smaller areas inside them (quarters and neighbourhoods).
bool detailAt(double zoom) => zoom >= PindoroCamera.areaDetailZoom;

bool isDetail(District d) => !d.isRaion;

/// The area a tap at [at] picks: the smallest one of the zoom's level that
/// contains it, else the smallest of any level.
District? areaAt(List<District> areas, LatLng at, double zoom) {
  final hits = [
    for (final d in areas)
      if (boundaryContains(d.boundary, at)) d,
  ]..sort((a, b) => a.areaM2.compareTo(b.areaM2));
  final detail = detailAt(zoom);
  return hits.where((d) => isDetail(d) == detail).firstOrNull ??
      hits.firstOrNull;
}

/// The areas not in [picks] for the nearby chips: those of the zoom's level
/// ([detail]) first, then the nearest to [here].
List<District> nearestAreas(
  List<District> areas,
  Set<String> picks,
  LatLng here, {
  required bool detail,
}) {
  final rest =
      [
        for (final d in areas)
          if (!picks.contains(d.id))
            (
              area: d,
              level: isDetail(d) == detail ? 0 : 1,
              m: distanceBetween(here, d.center),
            ),
      ]..sort((a, b) {
        final byLevel = a.level.compareTo(b.level);
        return byLevel != 0 ? byLevel : a.m.compareTo(b.m);
      });
  return [for (final r in rest) r.area];
}
