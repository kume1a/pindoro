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
int crossingCount(NamedStreet street, Iterable<NamedStreet> others) =>
    crossingsAlong(street, others).length;

/// A street [street] meets and where, once per name.
typedef Crossing = ({NamedStreet street, LatLng at});

/// Streets with another name whose lines cross or touch [street], in order
/// from its first end to its second ([streetEnds]).
List<Crossing> crossingsAlong(
  NamedStreet street,
  Iterable<NamedStreet> others,
) {
  final lines = street.geometry;
  final points = lines.expand((l) => l).toList();
  if (points.isEmpty) return const [];
  final proj = LocalProjection(points.first);
  final box = Bbox.of(points).grown(_touchM);
  // Each street is simplified on its own, so where one ends on another only
  // the ending street keeps a vertex at the junction: check both ways.
  final ends = [
    for (final l in lines)
      if (l.isNotEmpty) ...[l.first, l.last],
  ];
  LatLng? touching(Iterable<LatLng> ps, MultiPolyline ls) {
    for (final p in ps) {
      if (pointToPolylineDistance(p, ls).distanceMeters <= _touchM) return p;
    }
    return null;
  }

  final found = <String, Crossing>{};
  for (final other in others) {
    if (other.name == street.name || found.containsKey(other.name)) continue;
    final otherPoints = other.geometry.expand((l) => l);
    if (!box.intersects(Bbox.of(otherPoints))) continue;
    final at =
        touching(otherPoints, lines) ??
        touching(ends, other.geometry) ??
        _crossingPoint(lines, other.geometry, proj);
    if (at != null) found[other.name] = (street: other, at: at);
  }
  final (first, second) = streetEnds(street);
  final (ax, ay) = proj.project(first);
  final (bx, by) = proj.project(second);
  double along(LatLng p) {
    final (x, y) = proj.project(p);
    return (x - ax) * (bx - ax) + (y - ay) * (by - ay);
  }

  return found.values.toList()
    ..sort((a, b) => along(a.at).compareTo(along(b.at)));
}

/// [street]'s two ends: the line ends farthest apart.
(LatLng, LatLng) streetEnds(NamedStreet street) {
  final ends = [
    for (final l in street.geometry)
      if (l.isNotEmpty) ...[l.first, l.last],
  ];
  var best = (ends.first, ends.last);
  var bestM = -1.0;
  for (var i = 0; i < ends.length; i++) {
    for (var j = i + 1; j < ends.length; j++) {
      final m = distanceBetween(ends[i], ends[j]);
      if (m > bestM) (best, bestM) = ((ends[i], ends[j]), m);
    }
  }
  return best;
}

LatLng? _crossingPoint(MultiPolyline a, MultiPolyline b, LocalProjection proj) {
  for (final la in a) {
    for (var i = 1; i < la.length; i++) {
      final p1 = proj.project(la[i - 1]), p2 = proj.project(la[i]);
      for (final lb in b) {
        for (var j = 1; j < lb.length; j++) {
          final q1 = proj.project(lb[j - 1]), q2 = proj.project(lb[j]);
          if (_segmentsCross(p1, p2, q1, q2)) {
            final t =
                _cross(q1, q2, p1) / (_cross(q1, q2, p1) - _cross(q1, q2, p2));
            return proj.unproject((
              p1.$1 + t * (p2.$1 - p1.$1),
              p1.$2 + t * (p2.$2 - p1.$2),
            ));
          }
        }
      }
    }
  }
  return null;
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
