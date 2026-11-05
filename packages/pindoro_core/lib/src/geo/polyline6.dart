import 'geo.dart';

/// Google polyline algorithm at 1e6 precision, (lat, lon) order.
/// `double.round()` rounds half away from zero, matching @pindoro/geo.
String encodePolyline6(Polyline points) {
  final out = StringBuffer();
  var prevLat = 0, prevLon = 0;
  for (final p in points) {
    final lat = (p.lat * 1e6).round();
    final lon = (p.lon * 1e6).round();
    _encodeValue(lat - prevLat, out);
    _encodeValue(lon - prevLon, out);
    prevLat = lat;
    prevLon = lon;
  }
  return out.toString();
}

void _encodeValue(int v, StringBuffer out) {
  var n = v < 0 ? ~(v << 1) : v << 1;
  while (n >= 0x20) {
    out.writeCharCode((0x20 | (n & 0x1f)) + 63);
    n >>= 5;
  }
  out.writeCharCode(n + 63);
}

Polyline decodePolyline6(String encoded) {
  final points = <LatLng>[];
  var i = 0, lat = 0, lon = 0;
  int next() {
    var result = 0, shift = 0, b = 0;
    do {
      b = encoded.codeUnitAt(i++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    return result & 1 == 1 ? ~(result >> 1) : result >> 1;
  }

  while (i < encoded.length) {
    lat += next();
    lon += next();
    points.add(LatLng(lat / 1e6, lon / 1e6));
  }
  return points;
}
