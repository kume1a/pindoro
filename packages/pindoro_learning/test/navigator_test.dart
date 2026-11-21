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
}) {
  final nav = Navigator(
    graph: graph ?? net.graph(),
    cost: NavCost(net.byPart, toleranceKmh: LearningConfig.speedToleranceKmh),
    destination: to,
    level: level,
    streets: net.byPart,
    junctionNodes: {for (final j in net.at.keys) j: 5000 + j},
    silent: silent,
  );
  final prompts = <NavPrompt>[];
  final views = <NavView>[];
  var chimes = 0;
  for (final f in fixes) {
    final u = nav.onFix(f);
    if (u.prompt case final p?) prompts.add(p);
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
      to: g(2, 2),
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
      destination: g(2, 1),
      level: DriveLevel.guided,
      streets: net.byPart,
    );
    final fixes = _drive(_rightTurn);
    nav.onFix(fixes.first);
    final t = fixes.first.t;
    expect(nav.onTick(t.add(const Duration(seconds: 5))).view.gpsLostS, isNull);
    expect(nav.onTick(t.add(const Duration(seconds: 11))).view.gpsLostS, 11);
    final lost = nav.onTick(t.add(const Duration(seconds: 60)));
    expect(lost.prompt?.kind, PromptKind.stillFinding);
    expect(nav.onTick(t.add(const Duration(seconds: 61))).prompt, isNull);
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
}
