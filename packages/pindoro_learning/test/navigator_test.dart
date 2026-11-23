import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

import 'road_net.dart';

final _t0 = DateTime.utc(2026, 11, 21, 9);

/// Junction at row [r] (0 north) and column [c] (0 west), 300 m apart.
int g(int r, int c) => 100 + 10 * r + c;

/// A 5 × 5 grid of residential streets: rows `r0`… west to east, columns `c0`… north to south.
RoadNet _grid({int? row0Limit}) {
  final net = RoadNet();
  for (var k = 0; k < 5; k++) {
    net
      ..street('r$k', 'რიგი $k', 'Row $k')
      ..street('c$k', 'სვეტი $k', 'Column $k');
  }
  for (var r = 0; r < 5; r++) {
    for (var c = 0; c < 5; c++) {
      net.junction(g(r, c), 300.0 * c, -300.0 * r);
    }
  }
  var id = 0;
  for (var r = 0; r < 5; r++) {
    for (var c = 0; c < 5; c++) {
      if (c < 4) {
        net.edge(
          ++id,
          g(r, c),
          g(r, c + 1),
          'r$r',
          maxspeed: r == 0 ? row0Limit : null,
        );
      }
      if (r < 4) net.edge(++id, g(r, c), g(r + 1, c), 'c$c');
    }
  }
  return net;
}

LatLng _p(double east, double north) => RoadNet.point(east, north);
LatLng _at(int r, int c) => _p(300.0 * c, -300.0 * r);
double _east(LatLng p) => LocalProjection(RoadNet.origin).project(p).$1;

/// Fixes once a second from [_t0] driving through [points] at [mps], the car stopping
/// [stopS] seconds at the end.
List<DriveFix> _drive(List<LatLng> points, {double mps = 8, int stopS = 4}) {
  final fixes = <DriveFix>[];
  void fix(LatLng p, double heading, double speed) => fixes.add((
    at: p,
    t: _t0.add(Duration(seconds: fixes.length)),
    headingDeg: heading,
    speedMps: speed,
    accuracyM: 5,
  ));
  var carried = 0.0;
  for (var i = 0; i + 1 < points.length; i++) {
    final a = points[i], b = points[i + 1];
    final heading = bearingDegrees(a, b);
    final length = distanceBetween(a, b);
    final proj = LocalProjection(a);
    final (bx, by) = proj.project(b);
    var s = carried;
    for (; s < length; s += mps) {
      fix(proj.unproject((bx * s / length, by * s / length)), heading, mps);
    }
    carried = s - length;
  }
  for (var k = 0; k <= stopS; k++) {
    fix(points.last, fixes.last.headingDeg!, 0);
  }
  return fixes;
}

/// Runs [fixes] through a navigator to [to] at [level]; the prompts in order, the last view.
({
  List<NavPrompt> prompts,
  NavView view,
  List<NavView> views,
  int chimes,
  Navigator nav,
})
_run(
  RoadNet net,
  List<DriveFix> fixes, {
  required int to,
  required DriveLevel level,
  Set<String> silent = const {},
  RoadGraph? graph,
  Route? prefer,
  NavStop? stop,
  List<NavStop> via = const [],
}) {
  final nav = Navigator(
    graph: graph ?? net.graph(),
    cost: NavCost(net.byPart, toleranceKmh: LearningConfig.speedToleranceKmh),
    destination: stop ?? NavStop.junction(to),
    via: via,
    level: level,
    streets: net.byPart,
    junctionNodes: {for (final j in net.at.keys) j: 5000 + j},
    silent: silent,
    prefer: prefer,
  );
  final prompts = <NavPrompt>[];
  final views = <NavView>[];
  var chimes = 0;
  for (final f in fixes) {
    final u = nav.onFix(f);
    prompts.addAll(u.prompts);
    if (u.chime) chimes++;
    views.add(u.view);
  }
  return (
    prompts: prompts,
    view: views.last,
    views: views,
    chimes: chimes,
    nav: nav,
  );
}

List<PromptKind> _kinds(List<NavPrompt> prompts) => [
  for (final p in prompts) p.kind,
];

/// East along row 0 from 50 m past its first junction, right at column 1, down to row 2.
final _rightTurn = [_p(50, 0), _at(0, 1), _at(2, 1)];

void main() {
  test('Guided: prepare, then act, at the turn, then confirm the street; '
      'arrival once stopped', () {
    final net = _grid();
    final run = _run(
      net,
      _drive(_rightTurn),
      to: g(2, 1),
      level: DriveLevel.guided,
    );
    expect(_kinds(run.prompts), [
      PromptKind.prepare,
      PromptKind.action,
      PromptKind.confirmation,
    ]);
    final [prepare, action, confirm] = run.prompts;
    expect(prepare.decision!.junction, g(0, 1));
    expect(prepare.decision!.turn, Turn.right);
    expect(prepare.distanceM, closeTo(LearningConfig.prepareM, 8));
    expect(action.distanceM, isNull);
    expect(confirm.street!.nameEn, 'Column 1');
    final [passed] = run.nav.passed;
    expect(passed.junction, g(0, 1));
    expect(passed.ok, isTrue);
    expect(passed.help, NavHelp.guided);
    expect(
      passed.key,
      RouteIds.junction(5000 + g(0, 1), 5000 + g(0, 0), 5000 + g(1, 1)),
    );
    expect(run.view.arrived, isTrue);
    expect(run.view.stopped, isTrue);
  });

  test('the screens see the approach from the prepare point, the street just '
      'turned onto until the voice confirms it, and the metres left', () {
    final net = _grid();
    final run = _run(
      net,
      _drive(_rightTurn),
      to: g(2, 1),
      level: DriveLevel.guided,
    );
    expect(run.views.first.leftM, closeTo(250 + 600, 5));
    expect(run.views.first.street!.nameEn, 'Row 0');
    final approach = run.views.firstWhere((v) => v.prepareM != null);
    expect(approach.prepareM, closeTo(LearningConfig.prepareM, 8));
    expect(approach.next!.turn, Turn.right);
    expect(approach.then, isNull);
    final turned = [for (final v in run.views) ?v.turned];
    expect(turned.first.street.nameEn, 'Column 1');
    expect(turned.first.headingDeg, closeTo(180, 1));
    expect(turned, hasLength(LearningConfig.confirmDelayS));
    expect(run.view.leftM, lessThan(LearningConfig.navArriveM));
    expect(run.view.leftS, lessThan(5));
  });

  test('a decision close after the next one shows as "then"', () {
    // Slow along row 0, so the plan leaves it at once: right, then left at row 1.
    final net = _grid(row0Limit: 5);
    final run = _run(
      net,
      _drive([_p(10, 0), _at(0, 1), _at(1, 1), _at(1, 2)], mps: 35),
      to: g(1, 2),
      level: DriveLevel.guided,
    );
    final withThen = run.views.firstWhere((v) => v.then != null);
    expect(withThen.next!.junction, g(0, 1));
    expect(withThen.then!.junction, g(1, 1));
    expect(withThen.then!.turn, Turn.left);
  });

  test('Coached cues a decision that isn\'t silent, prepare only, and '
      'confirms it; a silent one gets nothing', () {
    final net = _grid();
    final cued = _run(
      net,
      _drive(_rightTurn),
      to: g(2, 1),
      level: DriveLevel.coached,
    );
    expect(_kinds(cued.prompts), [PromptKind.prepare, PromptKind.confirmation]);
    expect(cued.nav.passed.single.help, NavHelp.cue);

    final key = cued.nav.passed.single.key!;
    final quiet = _run(
      net,
      _drive(_rightTurn),
      to: g(2, 1),
      level: DriveLevel.coached,
      silent: {key},
    );
    expect(quiet.prompts, isEmpty);
    expect(quiet.nav.passed.single.help, NavHelp.none);
    expect(quiet.nav.passed.single.ok, isTrue);
  });

  test('Quiet: a turn that loses the good path starts a recovery, which '
      'ends 10 s back on a good path', () {
    final net = _grid();
    // Straight on at column 1 instead of right, then down column 2 and back along row 2.
    final run = _run(
      net,
      _drive([_p(50, 0), _at(0, 2), _at(2, 2), _at(2, 1)]),
      to: g(2, 1),
      level: DriveLevel.quiet,
    );
    expect(run.prompts.first.kind, PromptKind.recovery);
    expect(run.prompts.first.decision!.junction, g(0, 2));
    final wrong = run.nav.passed.first;
    expect(wrong.junction, g(0, 1));
    expect(wrong.ok, isFalse);
    expect(wrong.planned, isTrue);
    expect(wrong.help, NavHelp.none);
    expect(run.nav.recoveries, 1);
    final good = run.views.map((v) => v.goodS).nonNulls;
    expect(good.first, 0);
    expect(good.last, greaterThanOrEqualTo(LearningConfig.recoveryHoldS - 1));
    expect(run.view.recovering, isFalse);
    expect(run.view.arrived, isTrue);
    // The recovery ended before the next turn: silent again, but too soon after it to credit.
    expect(run.nav.passed[1].help, NavHelp.none);
    expect(run.nav.passed[1].recentHelp, isTrue);
  });

  test('Guided: a wrong turn says the new route, with no recovery', () {
    final net = _grid();
    final run = _run(
      net,
      _drive([_p(50, 0), _at(0, 2), _at(2, 2), _at(2, 1)]),
      to: g(2, 1),
      level: DriveLevel.guided,
    );
    expect(run.prompts.map((p) => p.kind), contains(PromptKind.recovery));
    expect(run.nav.recoveries, 0);
    expect(run.nav.passed.first.ok, isFalse);
    expect(run.nav.passed.first.help, NavHelp.guided);
    expect(run.views.any((v) => v.recovering), isFalse);
    final newRoute = run.views.firstWhere((v) => v.newRoute);
    expect(newRoute.next!.junction, g(0, 2));
    expect(run.view.newRoute, isFalse);
  });

  test('Quiet: another good way plans again in silence', () {
    final net = _grid();
    final plan = planNav(
      net.graph(),
      NavCost(net.byPart, toleranceKmh: 14),
      from: g(0, 1),
      to: NavStop.junction(g(2, 2)),
      approach: net
          .graph()
          .edgesAt(g(0, 0))
          .firstWhere((e) => e.other(g(0, 0)) == g(0, 1)),
      streets: net.byPart,
    )!;
    // Equal-length ways: drive the one the plan didn't take.
    final eastFirst = plan.route.junctions[1] == g(0, 2);
    final other = eastFirst
        ? [_p(50, 0), _at(0, 1), _at(2, 1), _at(2, 2)]
        : [_p(50, 0), _at(0, 2), _at(2, 2)];
    final run = _run(net, _drive(other), to: g(2, 2), level: DriveLevel.quiet);
    expect(run.prompts, isEmpty);
    expect(run.nav.recoveries, 0);
    expect(run.nav.passed.where((p) => p.ok == false), isEmpty);
    expect(run.view.arrived, isTrue);
  });

  test('the route picked at setup is the one guided, not the quickest', () {
    final net = _grid();
    final graph = net.graph();
    final approach = graph
        .edgesAt(g(0, 0))
        .firstWhere((e) => e.other(g(0, 0)) == g(0, 1));
    final quickest = planNav(
      graph,
      NavCost(net.byPart, toleranceKmh: 14),
      from: g(0, 1),
      to: NavStop.junction(g(2, 2)),
      approach: approach,
      streets: net.byPart,
    )!;
    // Equal-length ways: pick the one the quickest plan didn't take.
    final picked = quickest.route.junctions[1] == g(0, 2)
        ? [g(0, 1), g(1, 1), g(2, 1), g(2, 2)]
        : [g(0, 1), g(0, 2), g(1, 2), g(2, 2)];
    final edges = [
      for (var i = 0; i + 1 < picked.length; i++)
        graph
            .edgesAt(picked[i])
            .firstWhere((e) => e.other(picked[i]) == picked[i + 1]),
    ];
    final run = _run(
      net,
      _drive([_p(50, 0), for (final j in picked) net.at[j]!]),
      to: g(2, 2),
      level: DriveLevel.guided,
      prefer: Route(picked, edges, edges.fold(0, (s, e) => s + e.lengthM)),
    );
    // South first turns at column 1; east first goes straight on there, turning at column 2.
    final first = run.prompts.firstWhere((p) => p.kind == PromptKind.action);
    expect(first.decision?.junction, picked[1] == g(1, 1) ? g(0, 1) : g(0, 2));
    expect(run.view.newRoute, isFalse);
    expect(run.view.arrived, isTrue);
  });

  test('two recoveries within 5 minutes switch Quiet to Coached, said once', () {
    final net = _grid();
    // Wanted: right at column 1 down to row 4; driven straight on twice first.
    final run = _run(
      net,
      _drive([_p(50, 0), _at(0, 3), _at(4, 3), _at(4, 1)]),
      to: g(4, 1),
      level: DriveLevel.quiet,
    );
    expect(run.nav.recoveries, 2);
    expect(
      _kinds(run.prompts).where((k) => k == PromptKind.guard),
      hasLength(1),
    );
    expect(run.view.level, DriveLevel.coached);
  });

  test('over the limit plus the tolerance chimes after 3 s, again after 30 s; '
      'a camera ahead is said once, also at Off', () {
    final net = _grid(row0Limit: 40);
    final graph = net.graph(
      cameras: [
        (
          id: 7,
          edgeId: net.edges
              .firstWhere((e) => e.from == g(0, 2) && e.to == g(0, 3))
              .id,
          at: _p(800, 5),
          maxspeedKmh: 40,
          directionDeg: 90,
        ),
        (
          id: 8,
          edgeId: net.edges
              .firstWhere((e) => e.from == g(0, 2) && e.to == g(0, 3))
              .id,
          at: _p(820, -5),
          maxspeedKmh: 40,
          directionDeg: 270,
        ),
      ],
    );
    // 72 km/h along row 0 for about 55 s.
    final run = _run(
      net,
      _drive([_p(10, 0), _at(0, 4)], mps: 20),
      to: g(0, 4),
      level: DriveLevel.off,
      graph: graph,
    );
    expect(run.chimes, 2);
    expect(
      run.views.indexWhere((v) => v.over),
      LearningConfig.overspeedHoldS,
      reason: 'over from the first fix, warned 3 s later',
    );
    expect(run.views.any((v) => v.camera), isTrue);
    expect(run.view.camera, isFalse, reason: 'passed');
    expect(run.view.limitKmh, 40);
    expect(run.prompts.map((p) => (p.kind, p.limitKmh)), [
      (PromptKind.camera, 40),
    ]);
  });

  test('GPS lost: the line after 10 s, "Still finding you" once at 60 s', () {
    final net = _grid();
    final nav = Navigator(
      graph: net.graph(),
      cost: NavCost(net.byPart, toleranceKmh: 14),
      destination: NavStop.junction(g(2, 1)),
      level: DriveLevel.guided,
      streets: net.byPart,
    );
    final fixes = _drive(_rightTurn);
    nav.onFix(fixes.first);
    final t = fixes.first.t;
    expect(nav.onTick(t.add(const Duration(seconds: 5))).view.gpsLostS, isNull);
    expect(nav.onTick(t.add(const Duration(seconds: 11))).view.gpsLostS, 11);
    final lost = nav.onTick(t.add(const Duration(seconds: 60)));
    expect(_kinds(lost.prompts), [PromptKind.stillFinding]);
    expect(nav.onTick(t.add(const Duration(seconds: 61))).prompts, isEmpty);
  });

  Navigator plainNav(RoadNet net) => Navigator(
    graph: net.graph(),
    cost: NavCost(net.byPart, toleranceKmh: 14),
    destination: NavStop.junction(g(2, 1)),
    level: DriveLevel.guided,
    streets: net.byPart,
  );

  test('no fix yet: lost from the first tick, and stopped, so End drive '
      'stays within reach', () {
    final nav = plainNav(_grid());
    final first = nav.onTick(_t0);
    expect(first.view.gpsLostS, isNull);
    expect(first.view.stopped, isTrue);
    final later = nav.onTick(_t0.add(const Duration(seconds: 11)));
    expect(later.view.gpsLostS, 11);
    expect(later.view.stopped, isTrue);
    final still = nav.onTick(_t0.add(const Duration(seconds: 60)));
    expect(_kinds(still.prompts), [PromptKind.stillFinding]);
    expect(nav.onTick(_t0.add(const Duration(seconds: 61))).prompts, isEmpty);
  });

  test('lost while moving: moving until lost a minute, then stopped', () {
    final nav = plainNav(_grid());
    final fixes = _drive(_rightTurn).take(5).toList();
    fixes.forEach(nav.onFix);
    final t = fixes.last.t;
    expect(
      nav.onTick(t.add(const Duration(seconds: 11))).view.stopped,
      isFalse,
    );
    expect(nav.onTick(t.add(const Duration(seconds: 60))).view.stopped, isTrue);
  });

  test('the screens keep the heading driven: a stopped fix\'s 0 (a '
      'platform\'s "none") or null leaves it', () {
    final fixes = [
      for (final (i, f) in _drive(_rightTurn).indexed)
        if (f.speedMps == 0)
          (
            at: f.at,
            t: f.t,
            headingDeg: i.isEven ? 0.0 : null,
            speedMps: 0.0,
            accuracyM: f.accuracyM,
          )
        else
          f,
    ];
    final run = _run(_grid(), fixes, to: g(2, 1), level: DriveLevel.guided);
    expect(run.view.stopped, isTrue);
    expect(run.view.headingDeg, closeTo(180, 1));
  });

  test('the map\'s car sits on its road, the road ahead straight up, '
      'whatever the GPS drifts', () {
    final fixes = [
      for (final f in _drive([_p(50, 8), _p(550, 8)]))
        (
          at: f.at,
          t: f.t,
          headingDeg: 75.0,
          speedMps: f.speedMps,
          accuracyM: f.accuracyM,
        ),
    ];
    final run = _run(_grid(), fixes, to: g(0, 4), level: DriveLevel.guided);
    final road = run.views[10].onRoad!;
    final (east, north) = LocalProjection(RoadNet.origin).project(road.at);
    expect(north, closeTo(0, 0.5));
    final (fixEast, _) = LocalProjection(RoadNet.origin).project(fixes[10].at);
    expect(east, closeTo(fixEast, 1));
    expect(road.headingDeg, closeTo(90, 1));
    expect(run.views.first.onRoad, isNull);
    // Short of the plan's first junction, the road there is drawn from the car.
    final toPlan = run.views[10].toPlan;
    expect(toPlan.first, road.at);
    expect(
      LocalProjection(RoadNet.origin).project(toPlan.last).$1,
      closeTo(300, 0.5),
    );
    expect(run.views[40].toPlan, isEmpty);
  });

  test(
    'a GPS-free drive logs each junction with a choice, the wrong turn too',
    () {
      final net = _grid();
      final graph = net.graph();
      final fixes = _drive([_p(50, 0), _at(0, 2), _at(2, 2), _at(2, 1)]);
      final match = matchDrive(graph, fixes);
      final graded = gradeDrive(
        graph,
        match,
        g(2, 1),
        streets: net.byPart,
      ).graded!;
      final nodes = {for (final j in net.at.keys) j: 5000 + j};
      final log = offDriveDecisions(graph, graded, fixes, junctionNodes: nodes);
      final atTurn = log.firstWhere((d) => d.junction == g(0, 1));
      expect(atTurn.ok, isFalse);
      expect(atTurn.planned, isFalse, reason: 'straight on along row 0');
      expect(
        atTurn.key,
        RouteIds.junction(5000 + g(0, 1), 5000 + g(0, 0), 5000 + g(0, 2)),
      );
      final atCorner = log.firstWhere((d) => d.junction == g(0, 2));
      expect(atCorner.planned, isTrue);
      expect(log.every((d) => d.level == DriveLevel.off), isTrue);
      expect(
        log.map((d) => d.at).toList(),
        orderedEquals([...log.map((d) => d.at)]..sort()),
      );
    },
  );

  test('decisions passed in a GPS gap count neither way', () {
    final net = _grid();
    final fixes = _drive(_rightTurn);
    // Drop the 25 s around the turn.
    final gapped = [...fixes.take(20), ...fixes.skip(45)];
    final run = _run(net, gapped, to: g(2, 1), level: DriveLevel.quiet);
    expect(run.nav.passed.single.ok, isNull);
  });

  test('coarse fixes count as none: a wrong turn seen only through them starts '
      'no recovery and is not judged, and the GPS-lost line shows', () {
    final net = _grid();
    final fixes = _drive([_p(50, 0), _at(0, 2), _at(2, 2), _at(2, 1)]);
    // From before column 1 to well down column 2, the phone gives only approximate fixes.
    final coarse = [
      for (final (i, f) in fixes.indexed)
        i >= 20 && i < 110
            ? (
                at: f.at,
                t: f.t,
                headingDeg: f.headingDeg,
                speedMps: f.speedMps,
                accuracyM: LearningConfig.coarseFixM + 1,
              )
            : f,
    ];
    final run = _run(net, coarse, to: g(2, 1), level: DriveLevel.quiet);
    expect(run.prompts.where((p) => p.kind == PromptKind.recovery), isEmpty);
    expect(run.nav.recoveries, 0);
    // Only the turn after them is judged.
    expect(run.nav.passed.map((d) => d.junction), [g(2, 2)]);
    expect(run.views[40].gpsLostS, isNotNull);
    expect(isCoarse(coarse[20]), isTrue);
    expect(gpsGaps(coarse, _t0, coarse.last.t).count, 1);
    final matched = matchDrive(net.graph(), coarse);
    expect(matched.drivenM, lessThan(matchDrive(net.graph(), fixes).drivenM));
  });

  test('prompts due on the same fix all come through: a camera ahead and '
      "Coached's prepare", () {
    final net = _grid();
    final graph = net.graph(
      cameras: [
        (
          id: 9,
          edgeId: net.edges
              .firstWhere((e) => e.from == g(0, 1) && e.to == g(0, 2))
              .id,
          // 300 m ahead (the warning's reach) as the turn comes within 150 m (the prepare's).
          at: _p(450, 5),
          maxspeedKmh: 40,
          directionDeg: 90,
        ),
      ],
    );
    final run = _run(
      net,
      _drive(_rightTurn),
      to: g(2, 1),
      level: DriveLevel.coached,
      graph: graph,
    );
    expect(_kinds(run.prompts), [
      PromptKind.camera,
      PromptKind.prepare,
      PromptKind.confirmation,
    ]);
    expect(run.nav.passed.single.help, NavHelp.cue);
  });

  test('back from a GPS gap further along the plan, the car is still on it; '
      'the turn in the gap is passed, counting neither way', () {
    final net = _grid();
    final graph = net.graph();
    // East to column 3, right, down to row 4: past more than 3 edges in the gap.
    final picked = [
      g(0, 1),
      g(0, 2),
      g(0, 3),
      g(1, 3),
      g(2, 3),
      g(3, 3),
      g(4, 3),
    ];
    final edges = [
      for (var i = 0; i + 1 < picked.length; i++)
        graph
            .edgesAt(picked[i])
            .firstWhere((e) => e.other(picked[i]) == picked[i + 1]),
    ];
    final fixes = _drive([_p(50, 0), for (final j in picked) net.at[j]!]);
    // Lost from 200 m in until half way down row 2 to row 3.
    final gapped = [...fixes.take(20), ...fixes.skip(20 + (850 + 750) ~/ 8)];
    final run = _run(
      net,
      gapped,
      to: g(4, 3),
      level: DriveLevel.quiet,
      graph: graph,
      prefer: Route(picked, edges, edges.fold(0, (s, e) => s + e.lengthM)),
    );
    final passed = run.nav.passed.single;
    expect(passed.junction, g(0, 3));
    expect(passed.ok, isNull);
    expect(run.nav.recoveries, 0);
    expect(run.view.arrived, isTrue);
  });

  test("a stopped car's GPS jitter adds no metres driven", () {
    final fixes = _drive(_rightTurn);
    final stop = fixes.last;
    final jitter = [
      for (var i = 1; i <= 30; i++)
        (
          at: _p(300.0 + (i.isEven ? 3 : -3), -600),
          t: stop.t.add(Duration(seconds: i)),
          headingDeg: null,
          speedMps: 0.0,
          accuracyM: 5.0,
        ),
    ];
    final still = _run(_grid(), fixes, to: g(2, 1), level: DriveLevel.quiet);
    final jittered = _run(
      _grid(),
      [...fixes, ...jitter],
      to: g(2, 1),
      level: DriveLevel.quiet,
    );
    expect(jittered.view.drivenM, closeTo(still.view.drivenM, 1e-6));
  });

  test(
    'a district crossed at a crawl is cued with the heading driven before',
    () {
      final fixes = _drive(_rightTurn);
      final turn = fixes.indexWhere((f) => f.at.lat < _at(0, 1).lat - 1e-4);
      // Into the second district at walking pace just past the turn.
      final crawl = [
        ...fixes.take(turn),
        for (final (i, f) in fixes.skip(turn).indexed)
          (
            at: f.at,
            t: f.t,
            headingDeg: f.headingDeg,
            speedMps: i < 3 ? 1.0 : f.speedMps,
            accuracyM: f.accuracyM,
          ),
      ];
      final net = _grid();
      final nav = Navigator(
        graph: net.graph(),
        cost: NavCost(net.byPart, toleranceKmh: 14),
        destination: NavStop.junction(g(2, 1)),
        level: DriveLevel.guided,
        streets: net.byPart,
        districtAt: (p) => p.lat < _at(0, 1).lat - 1e-4 ? 'South' : 'North',
      );
      final cues = [
        for (final f in crawl)
          ...nav.onFix(f).prompts.where((p) => p.kind == PromptKind.district),
      ];
      expect(cues.single.district, 'South');
      expect(cues.single.headingDeg, isNotNull);
    },
  );

  test("the routes on from the car leave out the plan's own; taking one "
      'follows it at once, saying nothing', () {
    final net = _grid();
    final nav = Navigator(
      graph: net.graph(),
      cost: NavCost(net.byPart, toleranceKmh: 14),
      destination: NavStop.junction(g(2, 2)),
      level: DriveLevel.guided,
      streets: net.byPart,
    );
    final fixes = _drive([_p(50, 0), _at(0, 1)]).take(10).toList();
    final prompts = [for (final f in fixes) ...nav.onFix(f).prompts];
    final rest = nav.onTick(fixes.last.t).view.plan!.route.edges;
    final options = nav.routeOptions();
    expect(options, isNotEmpty);
    for (final o in options) {
      expect(o.route.edges.map((e) => e.id), isNot(rest.map((e) => e.id)));
    }
    final other = options.first;
    nav.takeRoute(other);
    final view = nav.onTick(fixes.last.t).view;
    expect(
      view.plan!.route.edges.map((e) => e.id),
      other.route.edges.map((e) => e.id),
    );
    expect(view.newRoute, isFalse);
    final next = nav.onFix((
      at: _p(130, 0),
      t: fixes.last.t.add(const Duration(seconds: 1)),
      headingDeg: 90,
      speedMps: 8,
      accuracyM: 5,
    ));
    expect(
      [...prompts, ...next.prompts].map((p) => p.kind),
      isNot(contains(PromptKind.recovery)),
    );
    expect(nav.recoveries, 0);
  });

  group('stops on the way', () {
    final net = _grid();
    final graph = net.graph();

    test('driven past, a stop is reached once and the drive goes on to the '
        'destination', () {
      final run = _run(
        net,
        _drive([_p(50, 0), _at(0, 4)]),
        to: g(0, 4),
        via: [NavStop.junction(g(0, 2))],
        graph: graph,
        level: DriveLevel.guided,
      );
      final reached = [
        for (final (i, v) in run.views.indexed)
          if (v.reached != null) (i, v.reached!.junction),
      ];
      expect(reached, hasLength(1));
      expect(reached.single.$2, g(0, 2));
      final before = run.views[10];
      expect(before.viaInM, closeTo(600 - _east(before.at!), 5));
      expect(run.views[reached.single.$1].viaInM, isNull);
      expect(run.nav.via, isEmpty);
      expect(run.view.arrived, isTrue);
    });

    test('stopped beside a stop on a road reaches it, not the destination', () {
      // 20 m south of row 0 between columns 1 and 2: on the right driving east.
      final stop = stopsNear(graph, _p(400, -20)).first;
      final run = _run(
        net,
        _drive([_p(50, 0), _p(400, 0)]),
        to: g(0, 4),
        via: [stop],
        graph: graph,
        level: DriveLevel.guided,
      );
      expect(run.views.where((v) => v.reached != null), hasLength(1));
      expect(run.views[40].side, NavSide.right);
      expect(run.view.arrived, isFalse);
    });

    test('off the plan before the stop, every new plan still goes through it; '
        'stopped at the destination first is no arrival', () {
      final run = _run(
        net,
        _drive([_p(50, 0), _at(0, 3), _at(0, 4)]),
        to: g(0, 4),
        via: [NavStop.junction(g(2, 2))],
        graph: graph,
        level: DriveLevel.guided,
      );
      final plans = {for (final v in run.views) ?v.plan};
      expect(plans.length, greaterThan(1));
      for (final p in plans) {
        expect(p.route.junctions, contains(g(2, 2)));
      }
      expect(run.views.where((v) => v.reached != null), isEmpty);
      expect(run.view.arrived, isFalse);
    });

    test('a stop added on the way: the next plan goes through it', () {
      final nav = Navigator(
        graph: graph,
        cost: NavCost(
          net.byPart,
          toleranceKmh: LearningConfig.speedToleranceKmh,
        ),
        destination: NavStop.junction(g(0, 4)),
        level: DriveLevel.guided,
        streets: net.byPart,
      );
      final fixes = _drive([_p(50, 0), _at(0, 4)]);
      for (final f in fixes.take(10)) {
        nav.onFix(f);
      }
      nav.setVia([NavStop.junction(g(1, 3))]);
      final plans = [
        for (final f in fixes.skip(10).take(5)) ?nav.onFix(f).view.plan,
      ];
      expect(plans.last.route.junctions, contains(g(1, 3)));
      expect(nav.via.single.junction, g(1, 3));
    });
  });

  group('a stop on the road', () {
    // 20 m south of row 0 between columns 1 and 2: on the right driving east.
    final net = _grid();
    final graph = net.graph();
    final stops = stopsNear(graph, _p(400, -20));
    final right = stops.first, left = stops[1];
    final road = right.edge!;

    test(
      'the way left ends at the stop, the place on the right once on its road; '
      'arrival there, not at the junction past it',
      () {
        final run = _run(
          net,
          _drive([_p(50, 0), _p(400, 0)]),
          to: g(0, 2),
          stop: right,
          graph: graph,
          level: DriveLevel.guided,
        );
        expect(run.view.arrived, isTrue);
        final early = run.views[10];
        expect(early.leftM, closeTo(400 - _east(early.at!), 5));
        expect(early.side, isNull);
        expect(run.views[40].side, NavSide.right);
        final past = _run(
          net,
          _drive([_p(50, 0), _at(0, 2)]),
          to: g(0, 2),
          stop: right,
          graph: graph,
          level: DriveLevel.guided,
        );
        expect(past.view.arrived, isFalse);
      },
    );

    test(
      'the left side: every plan arrives driving west, after a wrong way too',
      () {
        final run = _run(
          net,
          _drive([_p(0, -50), _at(1, 0), _at(2, 0)]),
          to: g(0, 1),
          stop: left,
          graph: graph,
          level: DriveLevel.guided,
        );
        final plans = {for (final v in run.views) ?v.plan};
        expect(plans.length, greaterThan(1));
        for (final p in plans) {
          expect(
            (p.route.junctions.last, p.route.edges.last.id),
            (g(0, 1), road.id),
          );
        }
      },
    );

    test(
      'driven past, nothing is judged: the car comes round to it, no recovery',
      () {
        final run = _run(
          net,
          _drive([_p(50, 0), _at(0, 2), _at(1, 2)]),
          to: g(0, 2),
          stop: right,
          graph: graph,
          level: DriveLevel.quiet,
        );
        expect(run.nav.recoveries, 0);
        expect(run.nav.passed.where((p) => p.junction == g(0, 2)), isEmpty);
        final plan = run.view.plan!;
        expect(
          (plan.route.junctions.last, plan.route.edges.last.id),
          (g(0, 2), road.id),
        );
      },
    );

    test('starting on its road short of it: the gap is all that is left, drawn '
        'to the stop', () {
      final run = _run(
        net,
        _drive([_p(320, 0), _p(400, 0)]),
        to: g(0, 2),
        stop: right,
        graph: graph,
        level: DriveLevel.guided,
      );
      final view = run.views[1];
      expect(view.plan!.route.edges, isEmpty);
      expect(view.leftM, closeTo(400 - _east(view.at!), 2));
      expect(_east(view.toPlan.last), closeTo(400, 1));
      expect(run.view.arrived, isTrue);
    });
  });
}
