import 'package:pindoro_core/pindoro_core.dart';
import 'package:test/test.dart';

void main() {
  group('clipToCircle', () {
    const center = LatLng(41.7, 44.75);
    final proj = LocalProjection(center);
    LatLng at(double x, double y) => proj.unproject((x, y));
    double x(LatLng p) => proj.project(p).$1;

    test('cuts a line where it crosses the circle', () {
      final clipped = clipToCircle(
        [
          [at(-300, 0), at(-50, 0), at(300, 0)],
        ],
        center,
        100,
      );
      expect(clipped, hasLength(1));
      expect(clipped.single, hasLength(3));
      expect(x(clipped.single.first), closeTo(-100, 0.01));
      expect(clipped.single[1], at(-50, 0));
      expect(x(clipped.single.last), closeTo(100, 0.01));
    });

    test('splits a line that leaves and comes back', () {
      final clipped = clipToCircle(
        [
          [at(-50, 0), at(-50, 500), at(50, 500), at(50, 0)],
        ],
        center,
        100,
      );
      expect(clipped, hasLength(2));
    });

    test('drops lines outside and keeps lines inside whole', () {
      final inside = [at(-10, 0), at(10, 0)];
      expect(
        clipToCircle(
          [
            inside,
            [at(500, 0), at(600, 0)],
          ],
          center,
          100,
        ),
        [inside],
      );
    });
  });
}
