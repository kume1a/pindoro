import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/features/setup/ui/outline_labels.dart';
import 'package:pindoro_core/pindoro_core.dart';

void main() {
  // A 2 km square in Tbilisi, counter-clockwise from its south-west corner.
  const s = 41.70, w = 44.70, n = s + 2000 / 110540;
  final e = w + 2000 / (111320 * 0.7466);
  final square = [
    const LatLng(s, w),
    LatLng(s, e),
    LatLng(n, e),
    const LatLng(n, w),
    const LatLng(s, w),
  ];

  String edge(OutlineSpot spot) {
    if ((spot.at.lat - s).abs() < 1e-4) return 'south';
    if ((spot.at.lat - n).abs() < 1e-4) return 'north';
    return (spot.at.lon - e).abs() < 1e-4 ? 'east' : 'west';
  }

  Map<String, ({double rotate, bool insideBelow})> byEdge(List<LatLng> ring) {
    final spots = outlineSpots([
      [ring],
    ]);
    expect(spots, hasLength(8), reason: 'two per edge, clear of the corners');
    return {
      for (final spot in spots)
        edge(spot): (rotate: spot.rotate, insideBelow: spot.insideBelow),
    };
  }

  test('names sit on straight stretches, upright, on the inside', () {
    expect(byEdge(square), {
      'south': (rotate: 0.0, insideBelow: false),
      'east': (rotate: 90.0, insideBelow: true),
      'north': (rotate: 0.0, insideBelow: true),
      'west': (rotate: 90.0, insideBelow: false),
    });
  });

  test('a clockwise ring keeps the same sides', () {
    expect(byEdge(square.reversed.toList()), byEdge(square));
  });
}
