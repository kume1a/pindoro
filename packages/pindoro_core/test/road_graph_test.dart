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

/// The cheapest legal cost from [from] to [to] by plain Dijkstra over
/// (edge, junction) states, U-turns penalised: the reference for A*.
double? _edgeDijkstra(RoadGraph graph, int from, int to) {
  final dist = <(int, int), double>{(-1, from): 0};
  final done = <(int, int)>{};
  while (true) {
    (int, int)? next;
    for (final MapEntry(:key, :value) in dist.entries) {
      if (!done.contains(key) && (next == null || value < dist[next]!)) {
        next = key;
      }
    }
    if (next == null) return null;
    final (edgeId, j) = next;
    if (j == to) return dist[next];
    done.add(next);
    final approach = edgeId < 0
        ? null
        : graph.edges.firstWhere((e) => e.id == edgeId);
    for (final e in graph.legalExits(j, approach: approach)) {
      final key = (e.id, e.other(j));
      final d =
          dist[next]! +
          e.lengthM +
          (e.id == edgeId ? RoutingConfig.uTurnPenaltyM : 0);
      if (d < (dist[key] ?? double.infinity)) dist[key] = d;
    }
  }
}

void main() {
  group('shortestRoute', () {
    test('drives the grid corner to corner along the streets', () {
      final grid = roadGrid(4).graph;
      final route = grid.shortestRoute(0, {15})!;
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
        final route = grid.shortestRoute(from, {to});
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

    test('takes a priced detour round a slow street, costed by the price', () {
      final grid = roadGrid(4).graph;
      double slowRow0(RoadEdge e) => e.lengthM * (e.streetId == 'row0' ? 5 : 1);
      expect(grid.shortestRoute(0, {3})!.junctions, [0, 1, 2, 3]);
      final detour = grid.shortestRoute(0, {3}, costOf: slowRow0)!;
      expect(detour.junctions, [0, 4, 5, 6, 7, 3]);
      expect(
        detour.costM,
        closeTo(detour.edges.fold(0.0, (sum, e) => sum + slowRow0(e)), 1e-6),
      );
    });

    test('is null between parts that never meet', () {
      // Drop every edge of column 0 and row 0 around junction 0.
      final grid = roadGrid(3, skip: {0, 1}).graph;
      expect(grid.shortestRoute(0, {8}), isNull);
      expect(grid.shortestRoute(4, {4})!.edges, isEmpty);
      expect(grid.connected(0, 8), isFalse);
      expect(grid.connected(1, 8), isTrue);
    });

    test('on one-ways and restrictions, costs what a plain search over '
        '(edge, junction) costs', () {
      final random = Random(11);
      for (var round = 0; round < 30; round++) {
        final grid = roadGrid(5).graph;
        final edges = [
          for (final e in grid.edges)
            RoadEdge(
              id: e.id,
              from: e.from,
              to: e.to,
              streetId: e.streetId,
              lengthM: e.lengthM,
              line: e.line,
              oneway: Oneway.values[random.nextInt(3)],
            ),
        ];
        final restrictions = [
          for (var i = 0; i < 6; i++)
            if (edges[random.nextInt(edges.length)] case final e)
              for (final to in grid.edgesAt(e.to).where((t) => t.id != e.id))
                if (random.nextInt(3) == 0)
                  (fromEdge: e.id, via: e.to, toEdge: to.id, only: false),
        ];
        final graph = RoadGraph(
          grid.junctions,
          edges,
          restrictions: restrictions,
        );
        final from = random.nextInt(25), to = random.nextInt(25);
        final expected = _edgeDijkstra(graph, from, to);
        final route = graph.shortestRoute(from, {to});
        expect(
          route?.costM,
          expected == null ? isNull : closeTo(expected, 1e-6),
          reason: 'round $round',
        );
        if (route == null) continue;
        for (final (i, e) in route.edges.indexed) {
          final approach = i == 0 ? null : route.edges[i - 1];
          expect(
            graph.legalExits(route.junctions[i], approach: approach),
            contains(e),
            reason: 'round $round, step $i',
          );
        }
      }
    });

    test('ends at the nearest of several goals', () {
      final grid = roadGrid(4).graph;
      final route = grid.shortestRoute(0, {15, 2, 12})!;
      expect(route.junctions.last, 2);
      expect(route.edges, hasLength(2));
    });

    test('keeps to the edges allowed', () {
      final grid = roadGrid(4).graph;
      // Row 0 and column 3 only: around the corner, never across.
      final route = grid.shortestRoute(1, {
        7,
      }, allow: (e) => e.streetId == 'row0' || e.streetId == 'col3')!;
      expect(route.junctions, [1, 2, 3, 7]);
      expect(
        grid.shortestRoute(1, {9}, allow: (e) => e.streetId == 'row0'),
        isNull,
      );
    });
  });

  test('edgeNear is the nearest edge in range, as a brute-force scan', () {
    final grid = roadGrid(6, skip: {3, 8, 21, 40}).graph;
    final random = Random(3);
    for (var round = 0; round < 200; round++) {
      final p = LatLng(
        41.7 + random.nextDouble() * 5 * gridLat,
        44.8 + random.nextDouble() * 5 * gridLon,
      );
      const withinM = 40.0;
      final nearestM = grid.edges
          .map((e) => pointToPolylineDistance(p, [e.line]).distanceMeters)
          .reduce(min);
      final edge = grid.edgeNear(p, withinM);
      if (nearestM > withinM) {
        expect(edge, isNull, reason: 'round $round');
      } else {
        expect(
          pointToPolylineDistance(p, [edge!.line]).distanceMeters,
          closeTo(nearestM, 1e-9),
          reason: 'round $round',
        );
      }
    }
  });

  test(
    'edgesNear holds every edge in range, a bent one too, in edge order',
    () {
      final grid = roadGrid(6, skip: {3, 8, 21, 40}).graph;
      final a = grid.at(0), b = grid.at(1);
      // A loop out to 300 m north of a short chord.
      final bent = RoadEdge(
        id: 999,
        from: 0,
        to: 1,
        streetId: null,
        lengthM: 2 * 300 + distanceBetween(a, b) + 10,
        line: [a, LatLng(a.lat + 300 / 111320, a.lon), b],
      );
      final graph = RoadGraph(grid.junctions, [...grid.edges, bent]);
      final random = Random(5);
      for (var round = 0; round < 300; round++) {
        final p = LatLng(
          41.7 - 4 * gridLat + random.nextDouble() * 12 * gridLat,
          44.8 - 4 * gridLon + random.nextDouble() * 12 * gridLon,
        );
        final withinM = 5 + random.nextDouble() * 400;
        final near = graph.edgesNear(p, withinM);
        expect(
          near.map((e) => e.id),
          orderedEquals([...near.map((e) => e.id)]..sort()),
        );
        for (final e in graph.edges) {
          if (pointToPolylineDistance(p, [e.line]).distanceMeters <= withinM) {
            expect(near, contains(e), reason: 'round $round, edge ${e.id}');
          }
        }
      }
    },
  );

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

  test(
    'a pack row reads its lanes, given by the junction they drive toward',
    () {
      final row = {
        'id': 3,
        'from_junction': 1,
        'to_junction': 2,
        'street_id': 's',
        'length_m': 140.5,
        'oneway': 1,
        'geometry': encodePolyline6(const [
          LatLng(41.7, 44.8),
          LatLng(41.701, 44.801),
        ]),
      };
      final older = RoadEdge.fromRow(row);
      expect((older.lanes, older.lanesBack), (null, null));
      expect(older.lanesInto(2), isNull);

      final edge = RoadEdge.fromRow({
        ...row,
        'lanes': 'left|through;right|right',
        'lanes_back': 'left|through',
      });
      expect(edge.lanes, 'left|through;right|right');
      expect(edge.lanesBack, 'left|through');
      expect(edge.lanesInto(2), 'left|through;right|right');
      expect(edge.lanesInto(1), 'left|through');
      expect(edge.lanesInto(7), isNull);

      final reported = RoadGraph(
        {1: const LatLng(41.7, 44.8), 2: const LatLng(41.701, 44.801)},
        [edge],
      ).allowing(twoWay: {3}).edges.single;
      expect(reported.oneway, Oneway.both);
      expect(reported.lanesInto(1), 'left|through');
      expect(reported.lanesInto(2), 'left|through;right|right');
    },
  );
}
