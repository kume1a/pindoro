import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/features/map/ui/route_layers.dart';
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

  test('fit puts the points inside the padded area', () {
    const size = Size(400, 800);
    const padding = EdgeInsets.fromLTRB(32, 280, 32, 180);
    const a = LatLng(41.7203, 44.7699), b = LatLng(41.7101, 44.7902);
    final camera = MapProjection.fit([a, b], size: size, padding: padding);
    final p = MapProjection(
      target: camera.target,
      zoom: camera.zoom,
      size: size,
    );
    final inner = padding.deflateRect(Offset.zero & size).inflate(0.5);
    expect(inner.contains(p.toScreen(a)), isTrue);
    expect(inner.contains(p.toScreen(b)), isTrue);
    // One side touches the padded area's edge: it is as close as it fits.
    final xs = [p.toScreen(a).dx, p.toScreen(b).dx]..sort();
    expect(xs.first, closeTo(padding.left, 0.5));
    expect(xs.last, closeTo(size.width - padding.right, 0.5));
    // A single point keeps the zoom cap.
    expect(
      MapProjection.fit([a], size: size, padding: padding, maxZoom: 16).zoom,
      16,
    );
  });

  test('the distance chip grows inwards near an edge', () {
    expect(chipAnchor(20, 390), 'bottom-left');
    expect(chipAnchor(195, 390), 'bottom');
    expect(chipAnchor(370, 390), 'bottom-right');
  });
}
