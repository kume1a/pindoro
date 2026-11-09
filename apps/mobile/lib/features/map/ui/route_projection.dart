import 'dart:math' as math;
import 'package:flutter/painting.dart' show EdgeInsets, Offset, Size;

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

  /// The camera that fits [points] inside [size] less [padding], up to
  /// [maxZoom]. Computed here rather than with MapLibre's bounds update,
  /// which keeps the padding on the camera and moves its target off the
  /// view's centre, where [toScreen] expects it.
  static ({LatLng target, double zoom}) fit(
    List<LatLng> points, {
    required Size size,
    required EdgeInsets padding,
    double maxZoom = 17,
  }) {
    final xs = [for (final p in points) _x(p.lon)];
    final ys = [for (final p in points) _y(p.lat)];
    final (minX, maxX) = (xs.reduce(math.min), xs.reduce(math.max));
    final (minY, maxY) = (ys.reduce(math.min), ys.reduce(math.max));
    final width = math.max(1.0, size.width - padding.horizontal);
    final height = math.max(1.0, size.height - padding.vertical);
    final fits = [
      if (maxX > minX) math.log(width / ((maxX - minX) * _tile)) / math.ln2,
      if (maxY > minY) math.log(height / ((maxY - minY) * _tile)) / math.ln2,
    ];
    final zoom = fits.fold(maxZoom, math.min);
    final world = _tile * math.pow(2, zoom);
    // The bounds' centre sits at the padded area's centre.
    final dx = padding.left + width / 2 - size.width / 2;
    final dy = padding.top + height / 2 - size.height / 2;
    final x = (minX + maxX) / 2 - dx / world;
    final y = (minY + maxY) / 2 - dy / world;
    final n = math.pi * (1 - 2 * y);
    return (
      target: LatLng(
        math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi,
        x * 360 - 180,
      ),
      zoom: zoom,
    );
  }

  /// Ground metres one dp covers at [at].
  double metresPerDp(LatLng at) =>
      _earthCircumferenceM * math.cos(at.lat * math.pi / 180) / _world;
}
