import 'package:pindoro_core/pindoro_core.dart';
import 'package:test/test.dart';
import 'road_grid.dart';

/// A point [m] metres east of [p].
LatLng _east(LatLng p, double m) => LocalProjection(p).unproject((m, 0));

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
  final graph = roadGrid(8).graph;
  int j(int r, int c) => r * 8 + c;

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

    test('never follows a one-way against its direction', () {
      final grid = roadGrid(8).graph;
      // Row 0 one-way westwards: from junction (0, c + 1) to (0, c) only.
      final oneway = RoadGraph(grid.junctions, [
        for (final e in grid.edges)
          RoadEdge(
            id: e.id,
            from: e.from,
            to: e.to,
            streetId: e.streetId,
            lengthM: e.lengthM,
            line: e.line,
            oneway: e.streetId == 'row0' ? Oneway.backward : Oneway.both,
          ),
      ]);
      final east = RouteDraft(oneway, j(0, 0), {
        j(0, 3),
      }).follow(oneway.at(j(0, 3)), 40, from: oneway.at(j(0, 0)));
      expect(east.edges, isEmpty);
      final west = RouteDraft(oneway, j(0, 3), {
        j(0, 0),
      }).follow(oneway.at(j(0, 0)), 40, from: oneway.at(j(0, 3)));
      expect(west.reached, isTrue);
      expect(
        RouteDraft(oneway, j(0, 0), {j(0, 3)}).driveTo(oneway.at(j(0, 2)), 40),
        isNull,
        reason: 'a tap ahead on the one-way finds no legal drive along it',
      );
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
}
