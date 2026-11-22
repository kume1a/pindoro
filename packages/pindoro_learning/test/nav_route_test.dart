import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

import 'road_net.dart';

/// A residential side street straight from 1 to 2 (600 m), and the main road round it: 1 → 3
/// (secondary, 100 m), 3 → 4 (primary, 600 m, signed [mainLimit]), 4 → 2 (secondary, 100 m).
RoadNet _bypass({int? mainLimit}) {
  final net = RoadNet()
    ..street('side', 'გვერდითი', 'Side')
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
        to: 2,
        streets: net.byPart,
      )!;
      expect(plan.route.junctions, [1, 3, 4, 2]);
      // 200 m at 55 km/h and 600 m at 65 km/h.
      expect(plan.seconds, closeTo(200 / (55 / 3.6) + 600 / (65 / 3.6), 0.1));
    });

    test('a low sign on the main road sends it down the side street', () {
      final net = _bypass(mainLimit: 10);
      final plan = planNav(
        net.graph(),
        NavCost(net.byPart, toleranceKmh: 14),
        from: 1,
        to: 2,
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
}
