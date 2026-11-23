import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

import 'road_net.dart';

/// A side street ([sideClass]) straight from 1 to 2 (600 m), and the main road round it: 1 → 3
/// (secondary, 100 m), 3 → 4 (primary, 600 m, signed [mainLimit]), 4 → 2 (secondary, 100 m).
RoadNet _bypass({int? mainLimit, String sideClass = 'residential'}) {
  final net = RoadNet()
    ..street('side', 'გვერდითი', 'Side', roadClass: sideClass)
    ..street('west', 'დასავლეთი', 'West', roadClass: 'secondary')
    ..street('main', 'მთავარი', 'Main', roadClass: 'primary')
    ..street('east', 'აღმოსავლეთი', 'East', roadClass: 'secondary')
    ..junction(1, 0, 0)
    ..junction(2, 600, 0)
    ..junction(3, 0, -100)
    ..junction(4, 600, -100);
  net
    ..edge(10, 1, 2, 'side')
    ..edge(11, 1, 3, 'west')
    ..edge(12, 3, 4, 'main', maxspeed: mainLimit)
    ..edge(13, 4, 2, 'east');
  return net;
}

/// Row street west to east through 1, 2, 3; Column crossing it at 2 (4 north, 5 south); Bend
/// leaving 3 up to the north-east, Lane straight on from 3.
RoadNet _cross() {
  final net = RoadNet()
    ..street('row', 'რიგი', 'Row')
    ..street('col', 'სვეტი', 'Column')
    ..street('lane', 'შესახვევი', 'Lane')
    ..junction(1, 0, 0)
    ..junction(2, 100, 0)
    ..junction(3, 200, 0)
    ..junction(4, 100, 100)
    ..junction(5, 100, -100)
    ..junction(6, 270, 70)
    ..junction(7, 300, 0);
  net
    ..edge(20, 1, 2, 'row')
    ..edge(21, 2, 3, 'row')
    ..edge(22, 2, 4, 'col')
    ..edge(23, 2, 5, 'col')
    ..edge(24, 3, 6, 'row')
    ..edge(25, 3, 7, 'lane');
  return net;
}

Route _along(RoadGraph graph, List<int> junctions) {
  final edges = [
    for (var i = 0; i + 1 < junctions.length; i++)
      graph
          .edgesAt(junctions[i])
          .firstWhere((e) => e.other(junctions[i]) == junctions[i + 1]),
  ];
  return Route(junctions, edges, edges.fold(0, (sum, e) => sum + e.lengthM));
}

void main() {
  group('speeds', () {
    final net = _bypass();
    final side = net.edges.firstWhere((e) => e.id == 10);
    final main = net.edges.firstWhere((e) => e.id == 12);

    test('a sign is the limit, else the law by road class', () {
      expect(speedLimitKmh(_bypass(mainLimit: 40).edges[2], 'primary'), 40);
      expect(speedLimitKmh(main, 'primary'), LearningConfig.limitTownKmh);
      expect(speedLimitKmh(main, 'motorway'), LearningConfig.limitMotorwayKmh);
      expect(
        speedLimitKmh(side, 'living_street'),
        LearningConfig.limitLivingStreetKmh,
      );
    });

    test('a class drives at its typical speed, at most the limit plus the '
        'tolerance', () {
      expect(navSpeedKmh(side, 'residential', 14), 25);
      expect(navSpeedKmh(main, 'primary', 14), 65);
      expect(navSpeedKmh(main, 'motorway', 14), 110);
      expect(navSpeedKmh(main, 'primary', 0), 60);
      expect(navSpeedKmh(_bypass(mainLimit: 40).edges[2], 'primary', 14), 54);
      expect(navSpeedKmh(main, null, 14), LearningConfig.navConnectorKmh);
    });
  });

  group('routing', () {
    test('prefers the main road where the shortest drive takes the side '
        'street', () {
      final net = _bypass();
      final graph = net.graph();
      expect(graph.shortestRoute(1, {2})!.junctions, [1, 2]);
      final plan = planNav(
        graph,
        NavCost(net.byPart, toleranceKmh: 14),
        from: 1,
        to: const NavStop.junction(2),
        streets: net.byPart,
      )!;
      expect(plan.route.junctions, [1, 3, 4, 2]);
      // 200 m at 55 km/h and 600 m at 65 km/h.
      expect(plan.seconds, closeTo(200 / (55 / 3.6) + 600 / (65 / 3.6), 0.1));
    });

    test('the route options: the quickest first, then a clearly different '
        'way not much slower; one far slower is left out', () {
      List<List<int>> options(RoadNet net) => [
        for (final p in planNavOptions(
          net.graph(),
          NavCost(net.byPart, toleranceKmh: 14),
          from: 1,
          to: const NavStop.junction(2),
          streets: net.byPart,
        ))
          p.route.junctions,
      ];
      expect(options(_bypass(sideClass: 'tertiary')), [
        [1, 3, 4, 2],
        [1, 2],
      ]);
      expect(options(_bypass()), [
        [1, 3, 4, 2],
      ], reason: 'the residential side street takes 1.9 times as long');
    });

    test('a low sign on the main road sends it down the side street', () {
      final net = _bypass(mainLimit: 10);
      final plan = planNav(
        net.graph(),
        NavCost(net.byPart, toleranceKmh: 14),
        from: 1,
        to: const NavStop.junction(2),
        streets: net.byPart,
      )!;
      expect(plan.route.junctions, [1, 2]);
    });

    test('a price is never below the length, so A* stays exact', () {
      final net = _bypass();
      final cost = NavCost(net.byPart, toleranceKmh: 20);
      for (final e in net.edges) {
        expect(cost.cost(e), greaterThanOrEqualTo(e.lengthM));
      }
    });
  });

  group('decisions', () {
    final net = _cross();
    final graph = net.graph(signals: {2});
    final nodes = {for (final j in net.at.keys) j: 9000 + j};
    List<NavDecision> along(List<int> junctions) => navDecisions(
      graph,
      _along(graph, junctions),
      approach: graph.edgesAt(1).firstWhere((e) => e.id == 20),
      streets: net.byPart,
      junctionNodes: nodes,
      landmarks: [
        (
          id: 'park',
          name: 'პარკი',
          nameEn: 'Park',
          kind: 'park',
          at: RoadNet.point(110, 20),
          personal: false,
          junction: null,
          onLeft: true,
        ),
      ],
    );

    test('straight through a crossroads on the same street is none', () {
      expect(along([2, 3, 7]).map((d) => d.junction), isNot(contains(2)));
    });

    test('a turn onto another street is one, with its turn, street, key, '
        'landmark and lights', () {
      final [d] = along([2, 4]);
      expect(d.junction, 2);
      expect(d.turn, Turn.left);
      expect(d.newStreet, isTrue);
      expect(d.street!.nameEn, 'Column');
      expect(d.atM, 0);
      expect(d.key, RouteIds.junction(9002, 9001, 9004));
      expect(d.landmark!.id, 'park');
      expect(d.signals, isTrue);
    });

    test('a bend with a straight side road is one, the same street or not', () {
      final ds = along([2, 3, 6]);
      expect(ds.map((d) => d.junction), [3]);
      expect(ds.single.newStreet, isFalse);
      expect(ds.single.atM, closeTo(100, 1));
      expect(ds.single.landmark, isNull);
      expect(ds.single.signals, isFalse);
    });

    test('a way on with no other legal way is none', () {
      final oneWayNet = _cross();
      final g = RoadGraph(oneWayNet.at, [
        for (final e in oneWayNet.edges)
          if (e.id != 22 && e.id != 23 && e.id != 25) e,
      ]);
      final route = _along(g, [2, 3, 6]);
      expect(
        navDecisions(
          g,
          route,
          approach: g.edgesAt(1).single,
          streets: oneWayNet.byPart,
        ),
        isEmpty,
      );
    });
  });

  group('the map and the lanes', () {
    final net = _cross();
    final graph = net.graph();
    NavPlan plan(List<int> junctions) {
      final route = _along(graph, junctions);
      return NavPlan(route, navDecisions(graph, route, streets: net.byPart), 0);
    }

    double east(LatLng p) => LocalProjection(RoadNet.origin).project(p).$1;

    test('a slice runs between its metres along the route, over junctions', () {
      final line = plan([1, 2, 3]).slice(50, 150);
      expect(east(line.first), closeTo(50, 0.5));
      expect(east(line.last), closeTo(150, 0.5));
      expect(line.map(east), contains(closeTo(100, 0.5)));
      expect(plan([1, 2, 3]).slice(400, 500), isEmpty);
    });

    test('the turn arrow runs from before the decision to just after it', () {
      final p = plan([1, 2, 3, 7]);
      final d = p.decisions.single;
      expect(d.junction, 3);
      final arrow = turnArrow(p, d);
      expect(
        east(arrow.first),
        closeTo(200 - LearningConfig.navArrowBeforeM, 0.5),
      );
      expect(
        east(arrow.last),
        closeTo(200 + LearningConfig.navArrowAfterM, 0.5),
      );
    });

    RoadGraph laned(String lanes) {
      final n = _cross();
      final edges = [
        for (final e in n.edges)
          e.id == 21
              ? RoadEdge(
                  id: e.id,
                  from: e.from,
                  to: e.to,
                  streetId: e.streetId,
                  lengthM: e.lengthM,
                  line: e.line,
                  lanes: lanes,
                )
              : e,
      ];
      return RoadGraph(n.at, edges);
    }

    NavDecision at3(RoadGraph g, int to) {
      final route = _along(g, [1, 2, 3, to]);
      return navDecisions(g, route, streets: net.byPart).single;
    }

    test('the lanes that go the way light their arrow', () {
      final g = laned('slight_left|through;slight_left|through');
      final straight = navLanes(at3(g, 7))!;
      expect(straight.map((l) => l.arrowsDeg), [
        [-45.0],
        [0.0, -45.0],
        [0.0],
      ]);
      expect(straight.map((l) => l.use), [null, 0.0, 0.0]);
      expect(navLanes(at3(g, 6))!.map((l) => l.use), [-45.0, -45.0, null]);
    });

    test('no lanes when none are mapped or none goes the way', () {
      expect(navLanes(at3(graph, 7)), isNull);
      expect(navLanes(at3(laned('left|left'), 7)), isNull);
    });
  });

  group('stops on the way', () {
    final net = _cross();
    final graph = net.graph();
    final cost = NavCost(net.byPart, toleranceKmh: 14);

    test('through a stop: one route of both legs, the stop metres along it, '
        'the time of both and the decisions of both', () {
      // From 1 to 7 through 4: up Column, back down it and on along Row.
      final plan = planNav(
        graph,
        cost,
        from: 1,
        to: const NavStop.junction(7),
        via: const [NavStop.junction(4)],
        streets: net.byPart,
      )!;
      expect(plan.route.junctions, [1, 2, 4, 2, 3, 7]);
      expect(plan.viaM, [closeTo(200, 0.5)]);
      expect(plan.seconds, closeTo(cost.secondsOf(plan.route), 1e-6));
      // Onto Column at 2, and back at 2 onto Row after the stop.
      expect(plan.decisions.where((d) => d.junction == 2), hasLength(2));
      final direct = planNav(
        graph,
        cost,
        from: 1,
        to: const NavStop.junction(7),
      )!;
      expect(direct.route.junctions, [1, 2, 3, 7]);
      expect(direct.viaM, isEmpty);
    });

    test('a stop on a road: its metres along the route, the next leg going on '
        'from the end of its road', () {
      // 20 m south of Row between 2 and 3: on the right driving east.
      final stop = stopsNear(graph, RoadNet.point(150, -20)).first;
      final plan = planNav(
        graph,
        cost,
        from: 1,
        to: const NavStop.junction(5),
        via: [stop],
      )!;
      expect(plan.route.junctions, [1, 2, 3, 2, 5]);
      expect(plan.viaM, [closeTo(150, 0.5)]);
    });

    test('the options all go through the stop', () {
      final options = planNavOptions(
        graph,
        cost,
        from: 1,
        to: const NavStop.junction(7),
        via: const [NavStop.junction(4)],
      );
      expect(options, isNotEmpty);
      for (final o in options) {
        expect(o.route.junctions, contains(4));
        expect(o.via, [const NavStop.junction(4)]);
      }
    });
  });

  group('stops on the road', () {
    final net = _cross();
    final graph = net.graph();
    final cost = NavCost(net.byPart, toleranceKmh: 14);
    double east(LatLng p) => LocalProjection(RoadNet.origin).project(p).$1;
    NavPlan to(NavStop stop, {int from = 1}) =>
        planNav(graph, cost, from: from, to: stop, streets: net.byPart)!;

    test(
      'a place beside a two-way road: a stop each way, the right side first',
      () {
        // 20 m south of Row between 1 and 2: on the right driving east.
        final stops = stopsNear(graph, RoadNet.point(50, -20));
        expect(
          [for (final s in stops) (s.edge!.id, s.toward, s.side)],
          [(20, 2, NavSide.right), (20, 1, NavSide.left)],
        );
        expect(stops.first.alongM, closeTo(50, 0.5));
        expect(east(stops.first.at!), closeTo(50, 0.5));
        expect(stops.first.junctionNear, 1);
      },
    );

    test(
      'on the road line it has no side; a one-way gives its way; none out of '
      'reach',
      () {
        final on = stopsNear(graph, RoadNet.point(50, -3));
        expect([for (final s in on) (s.toward, s.side)], [(null, null)]);
        final oneway = RoadNet()
          ..street('row', 'რიგი', 'Row')
          ..junction(1, 0, 0)
          ..junction(2, 100, 0);
        oneway.edge(20, 1, 2, 'row', oneway: Oneway.backward);
        expect(
          [
            for (final s in stopsNear(oneway.graph(), RoadNet.point(50, -20)))
              (s.toward, s.side),
          ],
          [(1, NavSide.left)],
        );
        expect(stopsNear(graph, RoadNet.point(50, -1000)), isEmpty);
      },
    );

    test('a plan ends at the stop: its metres, time and line', () {
      final right = stopsNear(graph, RoadNet.point(50, -20)).first;
      final plan = to(right);
      expect(plan.route.junctions, [1, 2]);
      expect(plan.endM, closeTo(50, 0.5));
      final row = plan.route.edges.single;
      expect(plan.seconds, closeTo(cost.seconds(row) / 2, 0.01));
      expect(east(plan.lines.single.last), closeTo(50, 0.5));
    });

    test('the left side comes round to arrive driving west', () {
      final left = stopsNear(graph, RoadNet.point(50, -20))[1];
      final plan = to(left);
      expect(plan.route.junctions.last, 1);
      expect(plan.route.edges.last.id, 20);
      expect(plan.endM, closeTo(plan.route.lengthM - 50, 0.5));
    });

    test(
      'both sides offered, the right first; one side when asked for one',
      () {
        final stops = stopsNear(graph, RoadNet.point(50, -20));
        List<NavSide?> sides({int count = LearningConfig.navOptions}) => [
          for (final p in planStopOptions(
            graph,
            cost,
            from: 1,
            stops: stops,
            streets: net.byPart,
            count: count,
          ))
            p.stop!.side,
        ];
        expect(sides(), [NavSide.right, NavSide.left]);
        expect(sides(count: 1), [NavSide.right]);
      },
    );

    test('a stop on the line is reached driving either way, the quicker', () {
      final on = stopsNear(graph, RoadNet.point(50, -3)).single;
      expect(to(on).route.junctions, [1, 2]);
      expect(to(on, from: 3).route.junctions, [3, 2, 1]);
      expect(to(on, from: 3).endM, closeTo(150, 0.5));
    });
  });
}
