import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:pindoro_core/pindoro_core.dart';

/// Screen ↔ map for MapLibre's north-up camera: [target] at the centre of a
/// [size] viewport and a world of 512 dp tiles at zoom 0. Synchronous, so a
/// drag can snap on every move without asking the platform view.
class MapProjection {
  const MapProjection({
    required this.target,
    required this.zoom,
    required this.size,
  });

  final LatLng target;
  final double zoom;
  final Size size;

  static const double _tile = 512;
  static const double _earthCircumferenceM = 40075016.686;

  double get _world => _tile * math.pow(2, zoom);

  static double _x(double lon) => (lon + 180) / 360;

  static double _y(double lat) {
    final s = math.sin(lat * math.pi / 180);
    return 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi);
  }

  Offset toScreen(LatLng p) => Offset(
    (_x(p.lon) - _x(target.lon)) * _world + size.width / 2,
    (_y(p.lat) - _y(target.lat)) * _world + size.height / 2,
  );

  LatLng toLatLng(Offset o) {
    final x = _x(target.lon) + (o.dx - size.width / 2) / _world;
    final y = _y(target.lat) + (o.dy - size.height / 2) / _world;
    final n = math.pi * (1 - 2 * y);
    final lat = math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi;
    return LatLng(lat, x * 360 - 180);
  }

  /// Ground metres one dp covers at [at].
  double metresPerDp(LatLng at) =>
      _earthCircumferenceM * math.cos(at.lat * math.pi / 180) / _world;
}
