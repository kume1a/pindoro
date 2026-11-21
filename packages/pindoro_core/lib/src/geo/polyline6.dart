import 'geo.dart';

/// Google polyline algorithm at 1e6 precision, (lat, lon) order.
/// `double.round()` rounds half away from zero, matching @pindoro/geo.
String encodePolyline6(Polyline points) {
  final deltas = <int>[];
  var prevLat = 0, prevLon = 0;
  for (final p in points) {
    final lat = (p.lat * 1e6).round();
    final lon = (p.lon * 1e6).round();
    deltas
      ..add(lat - prevLat)
      ..add(lon - prevLon);
    prevLat = lat;
    prevLon = lon;
  }
  return encodeInts(deltas);
}

/// Throws [FormatException] on a truncated string, as @pindoro/geo does.
Polyline decodePolyline6(String encoded) {
  final values = decodeInts(encoded);
  if (values.length.isOdd) {
    throw FormatException('truncated polyline6', encoded, encoded.length);
  }
  final points = <LatLng>[];
  var lat = 0, lon = 0;
  for (var i = 0; i < values.length; i += 2) {
    lat += values[i];
    lon += values[i + 1];
    points.add(LatLng(lat / 1e6, lon / 1e6));
  }
  return points;
}

/// Signed integers in the polyline algorithm's text form (Dart-only: the drive log's track).
String encodeInts(Iterable<int> values) {
  final out = StringBuffer();
  for (final v in values) {
    var n = v < 0 ? ~(v << 1) : v << 1;
    while (n >= 0x20) {
      out.writeCharCode((0x20 | (n & 0x1f)) + 63);
      n >>= 5;
    }
    out.writeCharCode(n + 63);
  }
  return out.toString();
}

/// The integers [encodeInts] wrote; throws [FormatException] on a truncated string.
List<int> decodeInts(String encoded) {
  final values = <int>[];
  var i = 0;
  while (i < encoded.length) {
    var result = 0, shift = 0, b = 0;
    do {
      if (i >= encoded.length) {
        throw FormatException('truncated polyline6', encoded, i);
      }
      b = encoded.codeUnitAt(i++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    values.add(result & 1 == 1 ? ~(result >> 1) : result >> 1);
  }
  return values;
}
