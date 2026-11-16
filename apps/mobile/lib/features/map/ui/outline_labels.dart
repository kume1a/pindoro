import 'dart:math' as math;

import 'package:pindoro_core/pindoro_core.dart';

/// Where a district's name sits along its outline: the anchor on the line,
/// the clockwise rotation that keeps the text upright and parallel to the
/// line, and whether the district's inside is below the rotated text.
typedef OutlineSpot = ({LatLng at, double rotate, bool insideBelow});

/// Spots every [spacingM] along each outer ring of [boundary] where the ring
/// runs straight for [windowM] (MapLibre only checks line angles for text, so
/// image labels would follow every wiggle of the outline).
List<OutlineSpot> outlineSpots(
  List<List<List<LatLng>>> boundary, {
  double spacingM = 1000,
  double windowM = 600,
}) => [
  for (final polygon in boundary)
    if (polygon.isNotEmpty) ..._ringSpots(polygon.first, spacingM, windowM),
];

List<OutlineSpot> _ringSpots(
  List<LatLng> ring,
  double spacingM,
  double windowM,
) {
  if (ring.length < 4) return const [];
  // Metres east (x) and north (y) of the first point.
  final lat0 = ring.first.lat;
  final kx = 111320 * math.cos(lat0 * math.pi / 180);
  const ky = 110540.0;
  final pts = [
    for (final p in ring)
      math.Point((p.lon - ring.first.lon) * kx, (p.lat - lat0) * ky),
  ];
  final along = [0.0];
  var area = 0.0;
  for (var i = 1; i < pts.length; i++) {
    along.add(along.last + pts[i].distanceTo(pts[i - 1]));
    area += pts[i - 1].x * pts[i].y - pts[i].x * pts[i - 1].y;
  }
  final total = along.last;
  if (total < windowM) return const [];

  math.Point<double> at(double s) {
    final t = s % total;
    var i = 1;
    while (along[i] <= t) {
      i++;
    }
    final f = (t - along[i - 1]) / (along[i] - along[i - 1]);
    return pts[i - 1] + (pts[i] - pts[i - 1]) * f;
  }

  return [
    for (var s = spacingM / 2; s < total; s += spacingM)
      if (_spot(
            at(s),
            at(s - windowM / 2),
            at(s + windowM / 2),
            windowM,
            counterClockwise: area > 0,
          )
          case final spot?)
        (
          at: LatLng(lat0 + spot.at.y / ky, ring.first.lon + spot.at.x / kx),
          rotate: spot.rotate,
          insideBelow: spot.insideBelow,
        ),
  ];
}

({math.Point<double> at, double rotate, bool insideBelow})? _spot(
  math.Point<double> at,
  math.Point<double> from,
  math.Point<double> to,
  double windowM, {
  required bool counterClockwise,
}) {
  final chord = from.distanceTo(to);
  // Bends and corners: the label would leave the line.
  if (chord < 0.9 * windowM) return null;
  final dx = (to.x - from.x) / chord, dy = (to.y - from.y) / chord;
  // Clockwise degrees from east, folded into (-90, 90] so text reads upright.
  var rotate = -math.atan2(dy, dx) * 180 / math.pi;
  if (rotate > 90) rotate -= 180;
  if (rotate <= -90) rotate += 180;
  final r = -rotate * math.pi / 180;
  // The rotated text's "down", and the ring's inside (left of travel when
  // the ring runs counter-clockwise).
  final down = math.Point(math.sin(r), -math.cos(r));
  final inside = counterClockwise ? math.Point(-dy, dx) : math.Point(dy, -dx);
  return (
    at: at,
    rotate: rotate,
    insideBelow: down.x * inside.x + down.y * inside.y > 0,
  );
}
