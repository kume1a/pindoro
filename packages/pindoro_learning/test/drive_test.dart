import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

import 'road_net.dart';
import 'vake_fixture.dart';

/// A point of a test drive, where the car waits [pauseS] seconds.
typedef _Stop = ({LatLng at, int pauseS});

_Stop _go(LatLng at, [int pauseS = 0]) => (at: at, pauseS: pauseS);

/// Fixes once a second driving through [stops] at [mps], each moved up to [noiseM] in a random
/// direction and its heading up to 5° off ([seed]ed), with the device's speed.
List<DriveFix> _drive(
  List<_Stop> stops, {
  double mps = 8,
  double noiseM = 0,
  int seed = 0,
}) {
  final random = Random(seed);
  final start = DateTime.utc(2026, 11, 16, 9);
  final fixes = <DriveFix>[];
  void fix(LatLng p, double heading, double speed) {
    final angle = random.nextDouble() * 2 * pi;
    final r = noiseM * sqrt(random.nextDouble());
    final at = LocalProjection(p).unproject((r * sin(angle), r * cos(angle)));
    fixes.add((
      at: at,
      t: start.add(Duration(seconds: fixes.length)),
      headingDeg: (heading + (random.nextDouble() - 0.5) * 10 + 360) % 360,
      speedMps: speed,
    ));
  }

  var carried = 0.0;
  for (var i = 0; i + 1 < stops.length; i++) {
    final a = stops[i].at, b = stops[i + 1].at;
    final heading = bearingDegrees(a, b);
    for (var k = 0; k < stops[i].pauseS; k++) {
      fix(a, heading, 0);
    }
    final length = distanceBetween(a, b);
    final proj = LocalProjection(a);
    final (bx, by) = proj.project(b);
    var s = carried;
    for (; s < length; s += mps) {
      fix(proj.unproject((bx * s / length, by * s / length)), heading, mps);
    }
    carried = s - length;
  }
  fix(stops.last.at, fixes.last.headingDeg!, 0);
  return fixes;
}

/// Junction at row [r] (0 north) and column [c] (0 west), 100 m apart.
int j(int r, int c) => 100 + 10 * r + c;
int h(int r, int c) => 1000 + 10 * r + c;
int v(int r, int c) => 2000 + 10 * r + c;

RoadNet _grid() {
  final net = RoadNet();
  for (var k = 0; k < 3; k++) {
    net
      ..street('r$k', 'რიგი $k', 'Row $k')
      ..street('c$k', 'სვეტი $k', 'Column $k');
  }
  for (var r = 0; r < 3; r++) {
    for (var c = 0; c < 3; c++) {
      net.junction(j(r, c), 100.0 * c, -100.0 * r);
    }
  }
  for (var r = 0; r < 3; r++) {
    for (var c = 0; c < 3; c++) {
      if (c < 2) net.edge(h(r, c), j(r, c), j(r, c + 1), 'r$r');
      if (r < 2) net.edge(v(r, c), j(r, c), j(r + 1, c), 'c$c');
    }
  }
  return net;
}

LatLng _p(double east, double north) => RoadNet.point(east, north);

void main() {
  group('synthetic grid', () {
    final graph = _grid().graph();

    test('a drive along streets matches their edges', () {
      final m = matchDrive(
        graph,
        _drive([_go(_p(0, 0)), _go(_p(200, 0)), _go(_p(200, -200))]),
      );
      expect(m.path.edges.map((e) => e.id), [
        h(0, 0),
        h(0, 1),
        v(0, 2),
        v(1, 2),
      ]);
      expect(m.path.junctions.first, j(0, 0));
      expect(m.uTurns, isEmpty);
      expect(m.drivenM, closeTo(400, 30));
    });

    test('turning back halfway along a street is a U-turn there', () {
      final m = matchDrive(
        graph,
        _drive([
          _go(_p(0, -100)),
          _go(_p(170, -100)),
          _go(_p(100, -100)),
          _go(_p(100, -200)),
        ]),
      );
      expect(m.path.edges.map((e) => e.id), [
        h(1, 0),
        h(1, 1),
        h(1, 1),
        v(1, 1),
      ]);
      expect(m.uTurns, hasLength(1));
      expect(distanceBetween(m.uTurns.single, _p(170, -100)), lessThan(25));
      final graded = RecitalGrader.score(
        graph,
        m.path,
        from: m.path.junctions.first,
        to: m.path.junctions.last,
      );
      expect(graded.drivable, isTrue);
      expect(graded.decisions.any((d) => !d.correct), isTrue);
    });

    test('a long stop away from junctions is a hesitation; one at a junction '
        'and at the start or end is not', () {
      final m = matchDrive(
        graph,
        _drive([
          _go(_p(0, 0), 20),
          _go(_p(50, 0), 15),
          _go(_p(100, 0), 15),
          _go(_p(200, 0), 20),
          _go(_p(200, -100)),
        ]),
      );
      expect(m.hesitations, hasLength(1));
      expect(distanceBetween(m.hesitations.single, _p(50, 0)), lessThan(1));
    });

    test('a short stop is not a hesitation', () {
      final m = matchDrive(
        graph,
        _drive([_go(_p(0, 0)), _go(_p(50, 0), 8), _go(_p(200, 0))]),
      );
      expect(m.hesitations, isEmpty);
    });

    test('no fix near a road: an empty path', () {
      final m = matchDrive(graph, _drive([_go(_p(0, 500)), _go(_p(200, 500))]));
      expect(m.path.edges, isEmpty);
    });
  });

  group('Vake fixture', () {
    late RoadGraph graph;

    setUpAll(() => graph = Vake.load().graph);

    test('a recorded drive replays as its matched path (PLAN M6 accept)', () {
      final random = Random(6);
      final ids = graph.junctions.keys.toList()..sort();
      var tried = 0;
      while (tried < 5) {
        final a = ids[random.nextInt(ids.length)];
        final b = ids[random.nextInt(ids.length)];
        final route = graph.shortestRoute(a, {b});
        if (route == null || route.lengthM < 800 || route.lengthM > 2500) {
          continue;
        }
        tried++;
        final fixes = _drive(
          [for (final p in route.lines.expand((l) => l)) _go(p)],
          noiseM: 5,
          seed: tried,
        );
        final m = matchDrive(graph, fixes);
        expect(
          m.path.edges.map((e) => e.id),
          route.edges.map((e) => e.id),
          reason: 'route $a → $b',
        );
        final graded = RecitalGrader.score(graph, m.path, from: a, to: b);
        expect(graded.tier, Tier.perfect, reason: 'route $a → $b');
      }
    });
  });
}
