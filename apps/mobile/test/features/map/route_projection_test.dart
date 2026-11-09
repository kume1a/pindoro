import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/features/map/ui/route_projection.dart';
import 'package:pindoro_core/pindoro_core.dart';

void main() {
  const target = LatLng(41.7151, 44.8271);

  test('the target sits at the centre; points round-trip', () {
    for (final zoom in [12.0, 14.5, 17.0]) {
      final p = MapProjection(
        target: target,
        zoom: zoom,
        size: const Size(400, 800),
      );
      expect(p.toScreen(target), const Offset(200, 400));
      const point = LatLng(41.7203, 44.8199);
      final back = p.toLatLng(p.toScreen(point));
      expect(distanceBetween(back, point), lessThan(0.01));
      // North is up, east is right.
      expect(p.toScreen(point).dy, lessThan(400));
      expect(p.toScreen(point).dx, lessThan(200));
    }
  });

  test('a dp at zoom 0 on the equator is the circumference / 512', () {
    const p = MapProjection(target: LatLng(0, 0), zoom: 0, size: Size(1, 1));
    expect(p.metresPerDp(const LatLng(0, 0)), closeTo(78271.5, 0.1));
    // Screen distances match ground distances at zoom 15.
    final z15 = MapProjection(
      target: target,
      zoom: 15,
      size: const Size(400, 800),
    );
    final east = z15.toLatLng(const Offset(300, 400));
    expect(
      distanceBetween(target, east),
      closeTo(100 * z15.metresPerDp(target), 0.5),
    );
  });
}
