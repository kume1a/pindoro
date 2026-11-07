import 'dart:ui' show Color;

import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:pindoro_core/pindoro_core.dart';

/// A colour as MapLibre layer properties take it: `#rrggbb`.
String hexColor(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

extension BboxToMapLibre on Bbox {
  ml.LatLngBounds get toMapLibre => ml.LatLngBounds(
    southwest: ml.LatLng(minLat, minLon),
    northeast: ml.LatLng(maxLat, maxLon),
  );
}

extension LatLngToMapLibre on LatLng {
  ml.LatLng get toMapLibre => ml.LatLng(lat, lon);
}

extension LatLngFromMapLibre on ml.LatLng {
  LatLng get toCore => LatLng(latitude, longitude);
}
