import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';
import 'package:test/test.dart';

import 'road_grid.dart';

/// Shortest distances from [from] by plain Dijkstra over a list (no heap).
Map<int, double> _dijkstra(RoadGraph graph, int from) {
  final dist = <int, double>{from: 0};
  final done = <int>{};
  while (true) {
    int? next;
    for (final MapEntry(:key, :value) in dist.entries) {
      if (!done.contains(key) && (next == null || value < dist[next]!)) {
        next = key;
      }
    }
    if (next == null) return dist;
    done.add(next);
    for (final e in graph.edgesAt(next)) {
      final d = dist[next]! + e.lengthM;
      if (d < (dist[e.other(next)] ?? double.infinity)) dist[e.other(next)] = d;
    }
  }
}

void main() {
  group('shortestRoute', () {
    test('drives the grid corner to corner along the streets', () {
      final grid = roadGrid(4).graph;
      final route = grid.shortestRoute(0, 15)!;
      expect(route.junctions.first, 0);
      expect(route.junctions.last, 15);
      expect(route.edges, hasLength(6));
      expect(route.lengthM, closeTo(_dijkstra(grid, 0)[15]!, 1e-6));
      // Each line runs from the junction before it.
      for (final (i, line) in route.lines.indexed) {
        expect(line.first, grid.at(route.junctions[i]));
        expect(line.last, grid.at(route.junctions[i + 1]));
      }
    });

    test('equals a brute-force search on grids with missing streets', () {
      final random = Random(7);
      for (var round = 0; round < 20; round++) {
        final skip = {for (var i = 0; i < 12; i++) random.nextInt(60)};
        final grid = roadGrid(6, skip: skip).graph;
        final from = random.nextInt(36), to = random.nextInt(36);
        final expected = _dijkstra(grid, from)[to];
        final route = grid.shortestRoute(from, to);
        if (expected == null) {
          expect(route, isNull);
        } else {
          expect(
            route!.lengthM,
            closeTo(expected, 1e-6),
            reason: 'round $round',
          );
          expect(
            route.edges.fold(0.0, (sum, e) => sum + e.lengthM),
            closeTo(route.lengthM, 1e-6),
          );
        }
      }
    });

    test('is null between parts that never meet', () {
      // Drop every edge of column 0 and row 0 around junction 0.
      final grid = roadGrid(3, skip: {0, 1}).graph;
      expect(grid.shortestRoute(0, 8), isNull);
      expect(grid.shortestRoute(4, 4)!.edges, isEmpty);
      expect(grid.connected(0, 8), isFalse);
      expect(grid.connected(1, 8), isTrue);
    });
  });

  test('the junctions on a street part', () {
    final grid = roadGrid(3).graph;
    expect(grid.junctionsOfPart('row1'), {3, 4, 5});
    expect(grid.junctionsOfPart('col2'), {2, 5, 8});
    expect(grid.junctionsOfPart('elsewhere'), isEmpty);
  });

  test('a pack row decodes its line on first use', () {
    final line = [const LatLng(41.7, 44.8), const LatLng(41.701, 44.801)];
    final edge = RoadEdge.fromRow({
      'id': 3,
      'from_junction': 1,
      'to_junction': 2,
      'street_id': 's',
      'length_m': 140.5,
      'geometry': encodePolyline6(line),
    });
    expect(edge.line, line);
    expect(edge.lineFrom(2), line.reversed);
    expect(edge.other(1), 2);
  });
}
