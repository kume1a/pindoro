import 'dart:math' as math;

const double earthRadiusM = 6371008.8;
const double _rad = math.pi / 180;
const double _mPerDeg = earthRadiusM * _rad;

class LatLng {
  const LatLng(this.lat, this.lon);

  final double lat;
  final double lon;

  @override
  bool operator ==(Object other) =>
      other is LatLng && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() => 'LatLng($lat, $lon)';
}

typedef Polyline = List<LatLng>;
typedef MultiPolyline = List<Polyline>;
typedef Xy = (double x, double y);

/// Equirectangular projection in metres around [origin]; accurate to well
/// under 0.5 m at city scale.
class LocalProjection {
  LocalProjection(this.origin) : _kx = _mPerDeg * math.cos(origin.lat * _rad);

  final LatLng origin;
  final double _kx;

  Xy project(LatLng p) =>
      ((p.lon - origin.lon) * _kx, (p.lat - origin.lat) * _mPerDeg);

  LatLng unproject(Xy xy) =>
      LatLng(origin.lat + xy.$2 / _mPerDeg, origin.lon + xy.$1 / _kx);
}

class Bbox {
  const Bbox(this.minLat, this.minLon, this.maxLat, this.maxLon);

  factory Bbox.of(Iterable<LatLng> points) {
    var minLat = double.infinity, minLon = double.infinity;
    var maxLat = double.negativeInfinity, maxLon = double.negativeInfinity;
    for (final p in points) {
      minLat = math.min(minLat, p.lat);
      minLon = math.min(minLon, p.lon);
      maxLat = math.max(maxLat, p.lat);
      maxLon = math.max(maxLon, p.lon);
    }
    return Bbox(minLat, minLon, maxLat, maxLon);
  }

  final double minLat;
  final double minLon;
  final double maxLat;
  final double maxLon;

  LatLng get center => LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2);

  LatLng clamp(LatLng p) =>
      LatLng(_clamp(p.lat, minLat, maxLat), _clamp(p.lon, minLon, maxLon));

  bool contains(LatLng p) =>
      p.lat >= minLat && p.lat <= maxLat && p.lon >= minLon && p.lon <= maxLon;

  bool intersects(Bbox o) =>
      o.minLat <= maxLat &&
      o.maxLat >= minLat &&
      o.minLon <= maxLon &&
      o.maxLon >= minLon;
}

double _clamp(double v, double lo, double hi) => math.min(hi, math.max(lo, v));

double _length(Xy v) => math.sqrt(v.$1 * v.$1 + v.$2 * v.$2);

double distanceBetween(LatLng a, LatLng b) =>
    _length(LocalProjection(a).project(b));

typedef NearestPoint = ({double distanceMeters, LatLng nearestPoint});

/// Distance to the closest point on any SEGMENT (not vertex) of [lines].
/// The projection is axis-aligned, so clamping into a part's lat/lon bbox
/// gives an exact lower bound for skipping far parts.
NearestPoint pointToPolylineDistance(LatLng point, MultiPolyline lines) {
  final proj = LocalProjection(point);
  var best = double.infinity;
  Xy bestXy = (0, 0);
  for (final line in lines) {
    if (line.isEmpty) continue;
    if (_length(proj.project(Bbox.of(line).clamp(point))) >= best) continue;
    final xy = line.map(proj.project).toList();
    for (var i = 0; i < xy.length; i++) {
      final (ax, ay) = xy[i];
      final (cx, cy) = xy[math.min(i + 1, xy.length - 1)];
      final dx = cx - ax, dy = cy - ay;
      final len2 = dx * dx + dy * dy;
      final t = len2 == 0 ? 0.0 : _clamp(-(ax * dx + ay * dy) / len2, 0, 1);
      final p = (ax + t * dx, ay + t * dy);
      final d = _length(p);
      if (d < best) {
        best = d;
        bestXy = p;
      }
    }
  }
  if (best == double.infinity) {
    throw ArgumentError.value(lines, 'lines', 'empty polyline');
  }
  return (distanceMeters: best, nearestPoint: proj.unproject(bestXy));
}

enum CompassPoint { n, ne, e, se, s, sw, w, nw }

/// Which of the eight compass points [to] lies in, seen from [from].
CompassPoint compassPoint(LatLng from, LatLng to) {
  final (x, y) = LocalProjection(from).project(to);
  final degrees = (math.atan2(x, y) * 180 / math.pi + 360) % 360;
  return CompassPoint.values[((degrees + 22.5) ~/ 45) % 8];
}
