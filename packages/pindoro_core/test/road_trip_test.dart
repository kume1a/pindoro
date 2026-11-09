import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';
import 'package:test/test.dart';

import 'road_grid.dart';

/// A point [m] metres east of [p].
LatLng _east(LatLng p, double m) => LocalProjection(p).unproject((m, 0));

void main() {
  final grid = roadGrid(8);
  final graph = grid.graph;
  final streets = grid.streets;
  int j(int r, int c) => r * 8 + c;

  group('pickTrip', () {
    test('B lies on the destination, A on another street, in range', () {
      for (var seed = 0; seed < 10; seed++) {
        final trip = pickTrip(
          graph,
          destinations: [streets['row3']!],
          starts: streets.values,
          minM: 500,
          maxM: 1500,
          random: Random(seed),
        )!;
        expect(trip.to ~/ 8, 3, reason: 'B on row 3');
        expect(trip.from ~/ 8, isNot(3), reason: 'A off row 3');
        final straight = distanceBetween(
          graph.at(trip.from),
          graph.at(trip.to),
        );
        expect(straight, inInclusiveRange(500, 1500));
        expect(trip.best.junctions.first, trip.from);
        expect(trip.best.junctions.last, trip.to);
        expect(trip.destination, streets['row3']);
      }
    });

    test('keeps both ends inside the area', () {
      // The western half of the grid.
      final west = [
        [
          [
            const LatLng(41.69, 44.79),
            const LatLng(41.72, 44.79),
            const LatLng(41.72, 44.8 + 3.5 * gridLon),
            const LatLng(41.69, 44.8 + 3.5 * gridLon),
            const LatLng(41.69, 44.79),
          ],
        ],
      ];
      for (var seed = 0; seed < 10; seed++) {
        final trip = pickTrip(
          graph,
          destinations: streets.values.toList(),
          starts: streets.values,
          minM: 400,
          maxM: 900,
          within: west,
          random: Random(seed),
        )!;
        expect(trip.from % 8, lessThan(4));
        expect(trip.to % 8, lessThan(4));
      }
    });

    test('is null when no start is far enough', () {
      expect(
        pickTrip(
          graph,
          destinations: [streets['row3']!],
          starts: streets.values,
          minM: 5000,
          maxM: 6000,
          random: Random(1),
        ),
        isNull,
      );
    });
  });

  group('RouteDraft', () {
    test('follows a drag along the street junction by junction', () {
      var draft = RouteDraft(graph, j(0, 0), j(0, 3));
      final start = graph.at(j(0, 0));
      draft = draft.follow(_east(start, 120), 40);
      expect(draft.edges, isEmpty, reason: 'still 80 m short of the junction');
      draft = draft.follow(graph.at(j(0, 1)), 40);
      expect(draft.junctions, [j(0, 0), j(0, 1)]);
      draft = draft.follow(graph.at(j(0, 2)), 40, from: graph.at(j(0, 1)));
      expect(draft.end, j(0, 2));
      expect(
        draft.lengthM,
        closeTo(2 * distanceBetween(start, graph.at(j(0, 1))), 1),
      );
    });

    test('a fast move from where the finger was passes every junction', () {
      final draft = RouteDraft(
        graph,
        j(0, 0),
        j(0, 6),
      ).follow(graph.at(j(0, 4)), 40, from: graph.at(j(0, 0)));
      expect(draft.junctions, [for (var c = 0; c <= 4; c++) j(0, c)]);
    });

    test('dragging back along the last street undoes it', () {
      final draft = RouteDraft(graph, j(0, 0), j(0, 6))
          .follow(graph.at(j(0, 3)), 40, from: graph.at(j(0, 0)))
          .follow(graph.at(j(0, 2)), 40, from: graph.at(j(0, 3)));
      expect(draft.end, j(0, 2));
      expect(draft.edges, hasLength(2));
    });

    test('ignores a finger off the road', () {
      final draft = RouteDraft(graph, j(1, 1), j(5, 5));
      final offRoad = LatLng(41.7 + 1.5 * gridLat, 44.8 + 1.5 * gridLon);
      expect(draft.heading(offRoad, 40), isNull);
      expect(draft.follow(offRoad, 40).edges, isEmpty);
    });

    test('stops at B', () {
      final draft = RouteDraft(
        graph,
        j(0, 0),
        j(0, 2),
      ).follow(graph.at(j(0, 5)), 40, from: graph.at(j(0, 0)));
      expect(draft.reached, isTrue);
      expect(draft.end, j(0, 2));
    });

    test('undo, start over and take', () {
      final draft = RouteDraft(graph, j(0, 0), j(2, 2))
          .take(graph.edgesAt(j(0, 0)).first)
          .take(
            graph
                .edgesAt(j(0, 1))
                .firstWhere((e) => e.other(j(0, 1)) == j(1, 1)),
          );
      expect(draft.junctions, [j(0, 0), j(0, 1), j(1, 1)]);
      expect(draft.undo().junctions, [j(0, 0), j(0, 1)]);
      expect(draft.startOver().edges, isEmpty);
      expect(RouteDraft(graph, 0, 1).undo().edges, isEmpty);
    });
  });

  group('turnsAt', () {
    test('a cross arriving eastbound: left is north, right is south', () {
      final draft = RouteDraft(graph, j(2, 1), j(2, 7)).take(
        graph.edgesAt(j(2, 1)).firstWhere((e) => e.other(j(2, 1)) == j(2, 2)),
      );
      final turns = turnsAt(draft);
      expect(
        [for (final t in turns) t.turn],
        [Turn.left, Turn.straight, Turn.right, Turn.back],
      );
      expect(turns[0].edge.other(j(2, 2)), j(3, 2));
      expect(turns[0].heading, CompassPoint.n);
      expect(turns[1].heading, CompassPoint.e);
      expect(turns[1].towardGoal, isTrue);
      expect(turns[3].towardGoal, isFalse);
    });

    test('at A every street is a start, with its heading', () {
      final turns = turnsAt(RouteDraft(graph, j(0, 0), j(7, 7)));
      expect([for (final t in turns) t.turn], everyElement(Turn.start));
      expect(
        {for (final t in turns) t.heading},
        {CompassPoint.n, CompassPoint.e},
      );
    });
  });

  test('routeLegs merges a street into one leg', () {
    final route = graph.shortestRoute(j(0, 0), j(0, 2))!;
    final up = RouteDraft(
      graph,
      j(0, 2),
      j(2, 2),
    ).follow(graph.at(j(2, 2)), 40, from: graph.at(j(0, 2)));
    final legs = routeLegs(
      Route(
        [...route.junctions, ...up.junctions.skip(1)],
        [...route.edges, ...up.edges],
        route.lengthM + up.lengthM,
      ),
    );
    expect(
      [for (final l in legs) (l.streetId, l.heading)],
      [('row0', CompassPoint.e), ('col2', CompassPoint.n)],
    );
    expect(legs.first.lengthM, closeTo(route.lengthM, 1e-6));
  });
}
