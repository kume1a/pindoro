import 'package:pindoro_core/pindoro_core.dart';
import 'package:test/test.dart';

import 'road_grid.dart';

void main() {
  final streets = roadGrid(5).streets;
  final others = streets.values.where((s) => s.id != 'row2');

  test('a street crosses every column once, in order from its first end', () {
    final row = streets['row2']!;
    final crossings = crossingsAlong(row, others);
    final (first, _) = streetEnds(row);
    final order = [for (final c in crossings) c.street.id];
    expect(
      order,
      first.lon < row.parts.first.midpoint.lon
          ? ['col0', 'col1', 'col2', 'col3', 'col4']
          : ['col4', 'col3', 'col2', 'col1', 'col0'],
    );
    expect(crossingCount(row, others), 5);
    expect(
      distanceBetween(crossings[2].at, row.parts.first.midpoint),
      lessThan(1),
      reason: 'col2 meets row2 at the grid centre',
    );
  });

  test('a street\'s ends are its farthest-apart line ends', () {
    final row = streets['row0']!;
    final (a, b) = streetEnds(row);
    expect(distanceBetween(a, b), closeTo(row.lengthM, 1));
  });

  test('bearings run clockwise from north', () {
    const from = LatLng(41.7, 44.8);
    expect(bearingDegrees(from, const LatLng(41.71, 44.8)), closeTo(0, 0.1));
    expect(bearingDegrees(from, const LatLng(41.7, 44.81)), closeTo(90, 0.1));
    expect(compassPointOf(200), CompassPoint.s);
    expect(compassPointOf(350), CompassPoint.n);
  });

  test('the heading along a line follows its nearest segment', () {
    const bend = [
      [LatLng(41.7, 44.8), LatLng(41.71, 44.8), LatLng(41.71, 44.81)],
    ];
    expect(headingAlong(bend, const LatLng(41.705, 44.8001)), closeTo(0, 0.1));
    expect(headingAlong(bend, const LatLng(41.7101, 44.806)), closeTo(90, 0.1));
  });
}
