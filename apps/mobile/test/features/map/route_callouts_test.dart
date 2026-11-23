import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/features/map/data/route_callouts.dart';
import 'package:pindoro_core/pindoro_core.dart';

void main() {
  const o = LatLng(41.7, 44.8);
  LatLng at(double east, double north) =>
      LocalProjection(o).unproject((east, north));

  test('a route alone: its bubble in its middle; none for no route', () {
    final route = [
      [at(0, 0), at(1000, 0)],
    ];
    expect(
      distanceBetween(calloutAt(route, const [])!, at(500, 0)),
      lessThan(1),
    );
    expect(calloutAt(const [], const []), isNull);
  });

  test('beside others: where it runs farthest from them', () {
    // Both start and end together; the detour bulges 400 m north at 500 m east.
    final straight = [
      [at(0, 0), at(1000, 0)],
    ];
    final detour = [
      [at(0, 0), at(250, 200), at(500, 400), at(750, 200), at(1000, 0)],
    ];
    expect(
      distanceBetween(calloutAt(detour, straight)!, at(500, 400)),
      lessThan(1),
    );
    // A bubble already there: this one keeps clear of it too.
    final clear = calloutAt(detour, straight, placed: [at(500, 400)])!;
    expect(distanceBetween(clear, at(500, 400)), greaterThan(200));
  });
}
