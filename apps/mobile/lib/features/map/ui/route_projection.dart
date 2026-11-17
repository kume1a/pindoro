import 'dart:math' as math;
import 'package:flutter/painting.dart' show EdgeInsets, Offset, Size;

import 'package:pindoro_core/pindoro_core.dart';

/// Screen ↔ map for MapLibre's camera: [target] at the centre of a [size]
/// viewport, the screen's top facing [bearing] (degrees clockwise from north)
/// and a world of 512 dp tiles at zoom 0. Synchronous, so a drag can snap on
/// every move without asking the platform view.
class MapProjection {
  const MapProjection({
    required this.target,
    required this.zoom,
    required this.size,
    this.bearing = 0,
  });

  final LatLng target;
  final double zoom;
  final Size size;
  final double bearing;

  static const double _tile = 512;
  static const double _earthCircumferenceM = 40075016.686;

  double get _world => _tile * math.pow(2, zoom);

  static double _x(double lon) => (lon + 180) / 360;

  static double _y(double lat) {
    final s = math.sin(lat * math.pi / 180);
    return 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi);
  }

  Offset toScreen(LatLng p) =>
      _turn(
        Offset(
          (_x(p.lon) - _x(target.lon)) * _world,
          (_y(p.lat) - _y(target.lat)) * _world,
        ),
        bearing,
      ) +
      size.center(Offset.zero);

  LatLng toLatLng(Offset o) {
    final northUp = _turn(o - size.center(Offset.zero), -bearing);
    final x = _x(target.lon) + northUp.dx / _world;
    final y = _y(target.lat) + northUp.dy / _world;
    final n = math.pi * (1 - 2 * y);
    final lat = math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi;
    return LatLng(lat, x * 360 - 180);
  }

  /// A north-up offset as a screen whose top faces [bearing] shows it.
  static Offset _turn(Offset o, double bearing) {
    if (bearing == 0) return o;
    final b = bearing * math.pi / 180;
    final (cos, sin) = (math.cos(b), math.sin(b));
    return Offset(o.dx * cos + o.dy * sin, o.dy * cos - o.dx * sin);
  }

  /// The camera that fits [points] inside [size] less [padding], up to
  /// [maxZoom], the screen's top facing [bearing]. Computed here rather than
  /// with MapLibre's bounds update, which keeps the padding on the camera and
  /// moves its target off the view's centre, where [toScreen] expects it.
  static ({LatLng target, double zoom}) fit(
    List<LatLng> points, {
    required Size size,
    required EdgeInsets padding,
    double maxZoom = 17,
    double bearing = 0,
  }) {
    // World coordinates as the turned screen lays them out.
    final turned = [
      for (final p in points) _turn(Offset(_x(p.lon), _y(p.lat)), bearing),
    ];
    final xs = [for (final p in turned) p.dx];
    final ys = [for (final p in turned) p.dy];
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
    final centre = _turn(
      Offset((minX + maxX) / 2 - dx / world, (minY + maxY) / 2 - dy / world),
      -bearing,
    );
    final (x, y) = (centre.dx, centre.dy);
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
