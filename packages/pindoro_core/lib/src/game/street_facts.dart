import 'dart:math';

import '../geo/geo.dart';
import 'named_street.dart';

/// Facts about a street for its intro card: its road type, how many streets
/// it crosses, which way it lies from the centre.
enum RoadType { mainRoad, street, sideStreet }

RoadType roadTypeOf(String roadClass) => switch (roadClass) {
  'motorway' || 'trunk' || 'primary' => RoadType.mainRoad,
  'secondary' || 'tertiary' => RoadType.street,
  _ => RoadType.sideStreet,
};

/// A line within this of another touches it (a shared junction node).
const double _touchM = 3;

/// Streets with another name whose lines cross or touch [street].
int crossingCount(NamedStreet street, Iterable<NamedStreet> others) {
  final lines = street.geometry;
  final points = lines.expand((l) => l).toList();
  if (points.isEmpty) return 0;
  final proj = LocalProjection(points.first);
  final box = _grown(Bbox.of(points), _touchM);
  // Each street is simplified on its own, so where one ends on another only
  // the ending street keeps a vertex at the junction: check both ways.
  final ends = [
    for (final l in lines)
      if (l.isNotEmpty) ...[l.first, l.last],
  ];
  bool touches(Iterable<LatLng> ps, MultiPolyline ls) =>
      ps.any((p) => pointToPolylineDistance(p, ls).distanceMeters <= _touchM);
  final names = <String>{};
  for (final other in others) {
    if (other.name == street.name || names.contains(other.name)) continue;
    final otherPoints = other.geometry.expand((l) => l);
    if (!box.intersects(Bbox.of(otherPoints))) continue;
    final meets =
        touches(otherPoints, lines) ||
        touches(ends, other.geometry) ||
        _linesCross(lines, other.geometry, proj);
    if (meets) names.add(other.name);
  }
  return names.length;
}

Bbox _grown(Bbox b, double m) {
  final dLat = m / 111320;
  final dLon = dLat / cos(b.center.lat * pi / 180);
  return Bbox(
    b.minLat - dLat,
    b.minLon - dLon,
    b.maxLat + dLat,
    b.maxLon + dLon,
  );
}

bool _linesCross(MultiPolyline a, MultiPolyline b, LocalProjection proj) {
  for (final la in a) {
    for (var i = 1; i < la.length; i++) {
      final p1 = proj.project(la[i - 1]), p2 = proj.project(la[i]);
      for (final lb in b) {
        for (var j = 1; j < lb.length; j++) {
          if (_segmentsCross(
            p1,
            p2,
            proj.project(lb[j - 1]),
            proj.project(lb[j]),
          )) {
            return true;
          }
        }
      }
    }
  }
  return false;
}

double _cross(Xy o, Xy a, Xy b) =>
    (a.$1 - o.$1) * (b.$2 - o.$2) - (a.$2 - o.$2) * (b.$1 - o.$1);

bool _segmentsCross(Xy p1, Xy p2, Xy q1, Xy q2) =>
    _cross(p1, p2, q1) * _cross(p1, p2, q2) < 0 &&
    _cross(q1, q2, p1) * _cross(q1, q2, p2) < 0;

/// Within this of the city centre a street is "in the city centre".
const double centreRadiusM = 1000;

/// Which way [street] lies from the city centre; null within [centreRadiusM].
CompassPoint? directionFromCentre(NamedStreet street, LatLng cityCenter) {
  final mid = street.parts.first.midpoint;
  return distanceBetween(cityCenter, mid) < centreRadiusM
      ? null
      : compassPoint(cityCenter, mid);
}
