import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';
import 'package:test/test.dart';

import 'road_grid.dart';

/// A point [m] metres east of [p].
LatLng _east(LatLng p, double m) => LocalProjection(p).unproject((m, 0));

/// The straight line from [trip]'s A to its street's nearest junction.
double _toStreet(RoadGraph graph, Trip trip) => trip.goals
    .map((g) => distanceBetween(graph.at(trip.from), graph.at(g)))
    .reduce(min);

/// The ids of [roadGrid]'s edges that [drop] picks: a row edge east of
/// (r, c), or a column edge north of it.
Set<int> _gridEdges(int n, bool Function(int r, int c, bool row) drop) {
  final ids = <int>{};
  var id = 0;
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      if (c + 1 < n && drop(r, c, true)) ids.add(id);
      if (c + 1 < n) id++;
      if (r + 1 < n && drop(r, c, false)) ids.add(id);
      if (r + 1 < n) id++;
    }
  }
  return ids;
}

void main() {
  final grid = roadGrid(8);
  final graph = grid.graph;
  final streets = grid.streets;
  int j(int r, int c) => r * 8 + c;

  group('pickTrip', () {
    test('A lies off the destination, in range; the drive ends on it', () {
      for (var seed = 0; seed < 10; seed++) {
        final trip = pickTrip(
          graph,
          destinations: [streets['row3']!],
          starts: streets.values,
          minM: 500,
          maxM: 1500,
          random: Random(seed),
        )!;
        expect(trip.goals, graph.junctionsOfPart('row3'));
        expect(trip.goals, isNot(contains(trip.from)));
        expect(_toStreet(graph, trip), inInclusiveRange(500, 1500));
        expect(trip.best.junctions.first, trip.from);
        expect(trip.goals, contains(trip.best.junctions.last));
        expect(trip.destination, streets['row3']);
      }
    });

    test('keeps A inside the area', () {
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
      }
    });

    group('turns', () {
      // Rows 6 and 7, columns 0 to 2.
      final southWest = [
        [
          [
            LatLng(41.7 + 5.5 * gridLat, 44.79),
            LatLng(41.7 + 7.5 * gridLat, 44.79),
            LatLng(41.7 + 7.5 * gridLat, 44.8 + 2.5 * gridLon),
            LatLng(41.7 + 5.5 * gridLat, 44.8 + 2.5 * gridLon),
            LatLng(41.7 + 5.5 * gridLat, 44.79),
          ],
        ],
      ];
      Trip pick(RoadGraph graph, int seed) => pickTrip(
        graph,
        destinations: [streets['row3']!],
        starts: streets.values,
        minM: 500,
        maxM: 1500,
        within: southWest,
        random: Random(seed),
      )!;

      test('picks a drive that turns onto other streets twice', () {
        // Rows 5 to 7 have no streets across, and only column 0 crosses
        // from row 4 to row 3: from column 1 or 2 the drive turns west on
        // row 4, then south on column 0. From column 0 it runs straight.
        final maze = roadGrid(
          8,
          skip: _gridEdges(8, (r, c, row) => row ? r >= 5 : r == 3 && c > 0),
        ).graph;
        for (var seed = 0; seed < 10; seed++) {
          final trip = pick(maze, seed);
          expect(trip.from % 8, isNot(0), reason: 'seed $seed');
          expect(turnCount(trip.best), 2, reason: 'seed $seed');
        }
      });

      test('falls back to a straight drive when none turns', () {
        final trip = pick(graph, 1);
        expect(turnCount(trip.best), 0);
      });
    });

    test('skips an A only a long loop reaches', () {
      // A 600 m from the destination; the only road there goes 1 km north,
      // then 600 m across to its far end (1.6 km).
      const b = LatLng(41.7, 44.8), a = LatLng(41.7, 44.8072);
      const north = LatLng(41.709, 44.8), northEast = LatLng(41.709, 44.8072);
      const south = LatLng(41.695, 44.8072);
      RoadEdge edge(
        int id,
        int from,
        int to,
        String street,
        LatLng x,
        LatLng y,
      ) => RoadEdge(
        id: id,
        from: from,
        to: to,
        streetId: street,
        lengthM: distanceBetween(x, y),
        line: [x, y],
      );
      final loop = RoadGraph(
        {0: b, 1: north, 2: northEast, 3: a, 4: south},
        [
          edge(0, 0, 1, 'dest', b, north),
          edge(1, 1, 2, 'top', north, northEast),
          edge(2, 2, 3, 'side', northEast, a),
          edge(3, 3, 4, 'start', a, south),
        ],
      );
      NamedStreet street(String id, LatLng x, LatLng y) => NamedStreet([
        Street(
          id: id,
          nameKa: id,
          nameEn: null,
          roadClass: 'residential',
          difficulty: Difficulty.expert,
          lengthM: distanceBetween(x, y),
          midpoint: x,
          bbox: Bbox.of([x, y]),
          geometry: [
            [x, y],
          ],
        ),
      ]);
      expect(
        pickTrip(
          loop,
          destinations: [street('dest', b, north)],
          starts: [street('start', a, south)],
          minM: 500,
          maxM: 700,
          random: Random(1),
        ),
        isNull,
      );
    });

    test('every trip drives at most 1.6 times the straight line', () {
      final holey = roadGrid(8, skip: {for (var i = 0; i < 112; i += 5) i});
      for (var seed = 0; seed < 20; seed++) {
        final trip = pickTrip(
          holey.graph,
          destinations: holey.streets.values.toList(),
          starts: holey.streets.values,
          minM: 500,
          maxM: 1500,
          random: Random(seed),
        );
        if (trip == null) continue;
        expect(
          trip.best.lengthM,
          lessThanOrEqualTo(_toStreet(holey.graph, trip) * TripRules.maxDetour),
        );
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
      var draft = RouteDraft(graph, j(0, 0), {j(0, 3)});
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
      final draft = RouteDraft(graph, j(0, 0), {
        j(0, 6),
      }).follow(graph.at(j(0, 4)), 40, from: graph.at(j(0, 0)));
      expect(draft.junctions, [for (var c = 0; c <= 4; c++) j(0, c)]);
    });

    test('dragging back along the last street undoes it', () {
      final draft = RouteDraft(graph, j(0, 0), {j(0, 6)})
          .follow(graph.at(j(0, 3)), 40, from: graph.at(j(0, 0)))
          .follow(graph.at(j(0, 2)), 40, from: graph.at(j(0, 3)));
      expect(draft.end, j(0, 2));
      expect(draft.edges, hasLength(2));
    });

    test('ignores a finger off the road', () {
      final draft = RouteDraft(graph, j(1, 1), {j(5, 5)});
      final offRoad = LatLng(41.7 + 1.5 * gridLat, 44.8 + 1.5 * gridLon);
      expect(draft.heading(offRoad, 40), isNull);
      expect(draft.follow(offRoad, 40).edges, isEmpty);
    });

    test('stops at the first goal it meets', () {
      final draft = RouteDraft(graph, j(0, 0), {
        j(0, 2),
        j(0, 4),
      }).follow(graph.at(j(0, 5)), 40, from: graph.at(j(0, 0)));
      expect(draft.reached, isTrue);
      expect(draft.end, j(0, 2));
    });

    test('undo drops the whole last street', () {
      final draft = RouteDraft(graph, j(0, 0), {j(7, 7)})
          .follow(graph.at(j(0, 3)), 40, from: graph.at(j(0, 0)))
          .follow(graph.at(j(2, 3)), 40, from: graph.at(j(0, 3)));
      expect(draft.edges, hasLength(5));
      expect(draft.undo().junctions, [for (var c = 0; c <= 3; c++) j(0, c)]);
      expect(draft.undo().undo().edges, isEmpty);
    });

    test('undo, start over and take', () {
      final draft = RouteDraft(graph, j(0, 0), {j(2, 2)})
          .take(graph.edgesAt(j(0, 0)).first)
          .take(
            graph
                .edgesAt(j(0, 1))
                .firstWhere((e) => e.other(j(0, 1)) == j(1, 1)),
          );
      expect(draft.junctions, [j(0, 0), j(0, 1), j(1, 1)]);
      expect(draft.undo().junctions, [j(0, 0), j(0, 1)]);
      expect(draft.startOver().edges, isEmpty);
      expect(RouteDraft(graph, 0, {1}).undo().edges, isEmpty);
    });

    group('driveTo', () {
      LatLng between(int a, int b, double t) {
        final x = graph.at(a), y = graph.at(b);
        return LatLng(x.lat + (y.lat - x.lat) * t, x.lon + (y.lon - x.lon) * t);
      }

      test('drives along the street to the junction nearest the tap', () {
        final draft = RouteDraft(graph, j(0, 0), {
          j(7, 7),
        }).driveTo(between(j(0, 2), j(0, 3), 0.6), 40)!;
        expect(draft.junctions, [for (var c = 0; c <= 3; c++) j(0, c)]);
      });

      test('turns onto the tapped street from the one it is on', () {
        final draft = RouteDraft(graph, j(0, 0), {
          j(7, 7),
        }).driveTo(graph.at(j(2, 3)), 40)!;
        expect(draft.junctions, [
          for (var c = 0; c <= 3; c++) j(0, c),
          j(1, 3),
          j(2, 3),
        ]);
      });

      test("a tap by the route's end takes the street's next junction", () {
        final draft = RouteDraft(graph, j(0, 0), {
          j(7, 7),
        }).driveTo(_east(graph.at(j(0, 0)), 20), 40)!;
        expect(draft.junctions, [j(0, 0), j(0, 1)]);
      });

      test('stops at a goal on the way', () {
        final draft = RouteDraft(graph, j(0, 0), {
          j(0, 2),
        }).driveTo(graph.at(j(0, 5)), 40)!;
        expect(draft.end, j(0, 2));
        expect(draft.reached, isTrue);
        expect(draft.driveTo(graph.at(j(0, 5)), 40), isNull);
      });

      test('is null off the road', () {
        final offRoad = LatLng(41.7 + 1.5 * gridLat, 44.8 + 1.5 * gridLon);
        expect(
          RouteDraft(graph, j(1, 1), {j(7, 7)}).driveTo(offRoad, 40),
          isNull,
        );
      });

      test("is null when the tapped street doesn't meet the route", () {
        final rows = roadGrid(4, skip: _gridEdges(4, (r, c, row) => !row));
        expect(
          RouteDraft(rows.graph, 0, {15}).driveTo(rows.graph.at(9), 40),
          isNull,
        );
      });
    });
  });

  group('turnCount', () {
    Route drive(List<int> corners) {
      var draft = RouteDraft(graph, corners.first, const {});
      for (var i = 1; i < corners.length; i++) {
        draft = draft.follow(
          graph.at(corners[i]),
          40,
          from: graph.at(corners[i - 1]),
        );
      }
      return Route(draft.junctions, draft.edges, draft.lengthM);
    }

    test('counts the bends onto other streets', () {
      expect(turnCount(drive([j(0, 0), j(0, 4)])), 0);
      expect(turnCount(drive([j(0, 0), j(0, 2), j(3, 2)])), 1);
      expect(turnCount(drive([j(0, 0), j(0, 2), j(2, 2), j(2, 5)])), 2);
    });
  });

  group('turnsAt', () {
    test('a cross arriving eastbound: left is north, right is south', () {
      final draft = RouteDraft(graph, j(2, 1), {j(2, 7)}).take(
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
    });

    test('at A every street is a start, with its heading', () {
      final turns = turnsAt(RouteDraft(graph, j(0, 0), {j(7, 7)}));
      expect([for (final t in turns) t.turn], everyElement(Turn.start));
      expect(
        {for (final t in turns) t.heading},
        {CompassPoint.n, CompassPoint.e},
      );
    });
  });

  test('routeLegs merges a street into one leg', () {
    final route = graph.shortestRoute(j(0, 0), {j(0, 2)})!;
    final up = RouteDraft(graph, j(0, 2), {
      j(2, 2),
    }).follow(graph.at(j(2, 2)), 40, from: graph.at(j(0, 2)));
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
