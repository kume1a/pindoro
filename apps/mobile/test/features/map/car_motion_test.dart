import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/features/map/data/car_motion.dart';
import 'package:pindoro_core/pindoro_core.dart';

void main() {
  const o = LatLng(41.7, 44.8);
  final local = LocalProjection(o);
  LatLng at(double east, double north) => local.unproject((east, north));

  test(
    'along the road: the point that far on, heading where the road runs next',
    () {
      // East 100 m, then north.
      final road = [at(0, 0), at(100, 0), at(100, 100)];
      final start = alongRoad(road, 0)!;
      expect(distanceBetween(start.at, at(0, 0)), lessThan(0.5));
      expect(start.headingDeg, closeTo(90, 1));
      final mid = alongRoad(road, 50)!;
      expect(distanceBetween(mid.at, at(50, 0)), lessThan(0.5));
      // Just before the corner it already looks round it.
      final corner = alongRoad(road, 95)!;
      expect(corner.headingDeg, inExclusiveRange(10, 80));
      final past = alongRoad(road, 500)!;
      expect(distanceBetween(past.at, at(100, 100)), lessThan(0.5));
      expect(past.headingDeg, closeTo(0, 1));
      expect(alongRoad([at(0, 0)], 10), isNull);
    },
  );
}
