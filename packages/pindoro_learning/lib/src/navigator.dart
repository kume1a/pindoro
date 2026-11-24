import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'constants.dart';
import 'drive.dart';
import 'drive_log.dart';
import 'nav_cost.dart';
import 'nav_level.dart';
import 'nav_plan.dart';
import 'nav_position.dart';
import 'nav_speed.dart';
import 'nav_stop.dart';
import 'nav_view.dart';
import 'recital.dart';
import 'route_questions.dart';

NavPrompt _prompt(
  PromptKind kind, {
  NavDecision? decision,
  double? distanceM,
  NamedStreet? street,
  String? district,
  double? headingDeg,
  int? limitKmh,
}) => (
  kind: kind,
  decision: decision,
  distanceM: distanceM,
  street: street,
  district: district,
  headingDeg: headingDeg,
  limitKmh: limitKmh,
);

/// Navigation to [destination] fed one fix at a time (SPEC §16.23 items 112–117, 127): where the
/// car is on the plan, the next decision and its prompts by level, a silent new plan after a
/// move that keeps a good path, recovery after one that doesn't, the frustration guard, district
/// cues, speed and camera warnings, stops and arrival, through the stops on the way [via] in
/// order (item 134). Times come from the fixes, so it replays.
class Navigator {
  Navigator({
    required this.graph,
    required this.cost,
    required NavStop destination,
    required DriveLevel level,
    List<NavStop> via = const [],
    this.streets = const {},
    this.landmarks = const [],
    this.junctionNodes = const {},
    Set<String> silent = const {},
    this.districtAt,
    Route? prefer,
  }) : _prefer = prefer,
       _destination = destination,
       _via = [...via],
       _level = level,
       _silent = silent,
       _speed = SpeedWatch(graph, cost, streets);

  final RoadGraph graph;
  final NavCost cost;
  NavStop _destination;
  NavStop get destination => _destination;

  /// The stops on the way not reached yet, in order.
  List<NavStop> _via;
  List<NavStop> get via => List.unmodifiable(_via);

  /// The stop the route goes to next: the first on the way, else the destination.
  NavStop get _goal => _via.firstOrNull ?? _destination;

  /// By part id.
  final Map<String, NamedStreet> streets;
  final List<RouteLandmark> landmarks;
  final Map<int, int> junctionNodes;

  /// The silent-eligible decisions, by key: Coached says nothing at them.
  Set<String> _silent;

  /// The district a point lies in (its id), for cues and the screen; the app names it.
  final String? Function(LatLng at)? districtAt;

  final SpeedWatch _speed;

  /// The route picked at setup (SPEC §16.23 item 129): the first plan follows it from where the
  /// car joins it; once off it, the quickest way is planned as ever.
  Route? _prefer;

  /// The decisions passed so far, in order.
  final List<PassedDecision> passed = [];

  DriveLevel _level;
  bool _rescued = false;

  /// The car on its plan; null until a plan is made from where the car is.
  PlanPosition? _pos;
  NavPlan? get _plan => _pos?.plan;
  int _nextDecision = 0;
  int _offFixes = 0;
  final Map<int, Set<PromptKind>> _said = {};

  bool _recovering = false;
  DateTime? _goodSince;
  DateTime? _lastRecoveryAt;
  final List<DateTime> _recoveries = [];
  int _recoveriesAtCoached = 0;

  /// Seconds the drive lost against its plans (the detours' extra time).
  double _lostS = 0;
  bool _guarded = false;

  /// The street to confirm, once the car is clear of the [others] ways on from where it turned.
  ({DateTime at, NamedStreet street, double headingDeg, List<RoadEdge> others})?
  _confirm;
  ({DateTime at, NamedStreet street, double headingDeg})? _turned;
  final Map<int, double> _prepareFrom = {};
  NavPlan? _newRoutePlan;
  String? _district;
  DateTime? _cueAt;
  double _cueAtM = 0;
  double _drivenM = 0;
  DateTime? _slowSince;
  bool _arrived = false;
  DriveFix? _last;
  DateTime? _stillSaidFor;

  /// The last heading taken while moving: a stopped or crawling fix's heading is noise (or a
  /// platform's 0 for none), so the screens keep this one.
  double? _headingDeg;

  /// The first tick, from which a drive with no fix yet counts as GPS lost.
  DateTime? _firstTick;

  /// Whether the last fix was on the plan.
  bool _onPlan = false;

  DriveLevel get level => _level;
  int get recoveries => _recoveries.length;

  /// A level chosen while stopped (item 116), at once.
  void setLevel(DriveLevel level) => _level = level;

  /// A destination changed (items 116, 134), with its route's [silent] decisions and the stops
  /// on the way when given: the next fix plans the way there.
  void setDestination(
    NavStop to, {
    Set<String> silent = const {},
    List<NavStop>? via,
  }) {
    _destination = to;
    _silent = silent;
    if (via != null) _via = [...via];
    _prefer = null;
    _pos = null;
    _arrived = false;
  }

  /// The stops on the way changed (item 134): the next fix plans the way through them.
  void setVia(List<NavStop> via) {
    _via = [...via];
    _prefer = null;
    _pos = null;
  }

  /// Off's Rescue (item 116): Guided to the destination; later decisions are watched only.
  void rescue() {
    _level = DriveLevel.guided;
    _rescued = true;
  }

  /// Other ways on from the car (SPEC §16.23 item 130's routes): the quickest drives to the
  /// destination from its next junction, leaving out the rest of the plan; none off the plan.
  List<NavPlan> routeOptions() {
    final pos = _pos;
    if (pos == null || !_onPlan) return const [];
    final rest = [
      for (final e in pos.plan.route.edges.skip(pos.index + 1)) e.id,
    ];
    return [
      for (final option in planNavOptions(
        graph,
        cost,
        from: pos.ahead,
        to: destination,
        via: _via,
        approach: pos.edge,
        streets: streets,
        landmarks: landmarks,
        junctionNodes: junctionNodes,
      ))
        if (!_sameIds(option.route.edges, rest)) option,
    ];
  }

  /// Drives [option] (one of [routeOptions]) from here on, at once and without a word.
  void takeRoute(NavPlan option) {
    final pos = _pos;
    if (pos == null) return;
    final edge = pos.edge;
    _prefer = option.route;
    _replan(edge, pos.ahead, edge.lengthM == 0 ? 1 : pos.alongM / edge.lengthM);
  }

  static bool _sameIds(List<RoadEdge> edges, List<int> ids) =>
      edges.length == ids.length &&
      edges.indexed.every((e) => e.$2.id == ids[e.$1]);

  NavUpdate onFix(DriveFix fix) {
    // A coarse fix is none (item 131): the car stays where it was last seen.
    if (isCoarse(fix)) return onTick(fix.t);
    final now = fix.t;
    final last = _last;
    final gapS = last == null
        ? 0.0
        : now.difference(last.t).inMilliseconds / 1000;
    final inGap = gapS > LearningConfig.gpsGapS;
    final moved = last == null ? 0.0 : distanceBetween(last.at, fix.at);
    final speed = fix.speedMps ?? (gapS > 0 ? moved / gapS : 0.0);
    // A stopped fix's move is GPS jitter, not driving.
    if (speed * 3.6 >= LearningConfig.stoppedKmh) _drivenM += moved;
    _last = fix;
    final heading = speed > LearningConfig.navHeadingMps
        ? fix.headingDeg
        : null;
    _headingDeg = heading ?? _headingDeg;
    final prompts = <NavPrompt>[];

    _follow(fix.at, heading, now, inGap, prompts);
    _promptNext(now, speed, prompts);
    _confirmTurn(fix.at, now, prompts);
    _cueDistrict(fix.at, _headingDeg, now, prompts);
    _warnCameras(speed, prompts);

    final kmh = speed * 3.6;
    final limit = switch (_pos) {
      final pos? => cost.limitKmh(pos.edge),
      null => null,
    };
    final (:warned, :chime) = _speed.overspeed(now, kmh, limit);
    if (kmh < LearningConfig.stoppedKmh) {
      _slowSince ??= now;
    } else {
      _slowSince = null;
    }
    final stopped = _stopped(now);
    final reached = _reach(fix.at, stopped: stopped);
    if (_via.isEmpty &&
        stopped &&
        distanceBetween(fix.at, destination.pointOn(graph)) <=
            LearningConfig.navArriveM) {
      _arrived = true;
    }
    prompts.sort((a, b) => a.kind.index.compareTo(b.kind.index));
    return (
      view: _view(
        now: now,
        at: fix.at,
        headingDeg: _headingDeg,
        speedMps: speed,
        limitKmh: limit,
        over: warned,
        stopped: stopped,
        gpsLostS: null,
        reached: reached,
      ),
      prompts: prompts,
      chime: chime,
    );
  }

  /// The car at [p] on its plan: a plan made once it is on a road, the decisions followed passed,
  /// and after two fixes off it the move judged; a recovery held long enough on a good path ends.
  void _follow(
    LatLng p,
    double? heading,
    DateTime now,
    bool inGap,
    List<NavPrompt> prompts,
  ) {
    final pos = _pos;
    final where = pos?.track(p, heading, wide: inGap);
    _onPlan = where != null;
    if (pos == null) {
      final located = _locate(p, heading);
      if (located != null) _replan(located.edge, located.ahead, located.along);
    } else if (where == null) {
      if (++_offFixes >= LearningConfig.navOffFixes) {
        _deviate(p, heading, now, inGap, prompts);
      }
    } else {
      _offFixes = 0;
      _passFollowed(now, inGap);
    }
    if (_recovering) {
      _lastRecoveryAt = now;
      if (where == null) {
        _goodSince = null;
      } else if (now.difference(_goodSince ??= now).inSeconds >=
          LearningConfig.recoveryHoldS) {
        _recovering = false;
      }
    }
  }

  /// The street turned onto, said [LearningConfig.confirmDelayS] after the turn: not while the
  /// car may yet be on another branch of a shallow fork.
  void _confirmTurn(LatLng p, DateTime now, List<NavPrompt> prompts) {
    final c = _confirm;
    if (c == null ||
        now.isBefore(c.at) ||
        !_onPlan ||
        c.others.any(
          (e) => nearestOnEdge(p, e).distM <= LearningConfig.driveSnapM,
        )) {
      return;
    }
    prompts.add(
      _prompt(
        PromptKind.confirmation,
        street: c.street,
        headingDeg: c.headingDeg,
      ),
    );
    _confirm = null;
  }

  /// The cameras newly ahead of the car, each said once.
  void _warnCameras(double speed, List<NavPrompt> prompts) {
    final pos = _pos;
    if (pos == null) return;
    for (final limit in _speed.camerasAhead(
      pos.edge,
      pos.from,
      alongM: pos.alongM,
      speedMps: speed,
      drivenM: _drivenM,
    )) {
      prompts.add(_prompt(PromptKind.camera, limitKmh: limit));
    }
  }

  /// The next stop on the way, reached once the car stopped near it or drove past it: dropped
  /// from [_via] and returned; null otherwise.
  NavStop? _reach(LatLng at, {required bool stopped}) {
    final stop = _via.firstOrNull;
    if (stop == null) return null;
    final near =
        stopped &&
        distanceBetween(at, stop.pointOn(graph)) <= LearningConfig.navArriveM;
    final aheadM = _pos?.viaInM(_via.length);
    final past =
        _onPlan && aheadM != null && aheadM <= -LearningConfig.navArriveM;
    if (!near && !past) return null;
    _via.removeAt(0);
    return stop;
  }

  /// Time passing without fixes (since the last one, or the first tick before any): the GPS
  /// line after [LearningConfig.gpsGapS], "Still finding you" once at
  /// [LearningConfig.gpsLostSayS]. Before the first fix, and once lost that long, the car
  /// counts as stopped: its speed is unknown, and End drive must stay within reach.
  NavUpdate onTick(DateTime now) {
    final last = _last;
    final since = last?.t ?? (_firstTick ??= now);
    final gapS = now.difference(since).inSeconds;
    final still = gapS >= LearningConfig.gpsLostSayS && _stillSaidFor != since;
    if (still) _stillSaidFor = since;
    return (
      view: _view(
        now: now,
        at: last?.at,
        headingDeg: _headingDeg,
        speedMps: 0,
        limitKmh: switch (_pos) {
          final pos? => cost.limitKmh(pos.edge),
          null => null,
        },
        over: false,
        stopped:
            last == null || gapS >= LearningConfig.gpsLostSayS || _stopped(now),
        gpsLostS: gapS > LearningConfig.gpsGapS ? gapS : null,
      ),
      prompts: [if (still) _prompt(PromptKind.stillFinding)],
      chime: false,
    );
  }

  bool _stopped(DateTime now) {
    final since = _slowSince;
    return since != null &&
        now.difference(since).inSeconds >= LearningConfig.stoppedHoldS;
  }

  NavView _view({
    required DateTime now,
    required LatLng? at,
    required double? headingDeg,
    required double speedMps,
    required int? limitKmh,
    required bool over,
    required bool stopped,
    required int? gpsLostS,
    NavStop? reached,
  }) {
    final pos = _pos;
    final plan = pos?.plan;
    final progressM = pos?.progressM ?? 0;
    final decisions = plan?.decisions ?? const <NavDecision>[];
    final next = _nextDecision < decisions.length
        ? decisions[_nextDecision]
        : null;
    final after = _nextDecision + 1 < decisions.length
        ? decisions[_nextDecision + 1]
        : null;
    final nextInM = next == null ? null : next.atM - progressM;
    final reach = max(
      LearningConfig.prepareM,
      LearningConfig.prepareS * speedMps,
    );
    // Kept once begun, so the approach bar runs on as the car slows.
    final prepareM = next == null
        ? null
        : _prepareFrom[next.index] ??
              (nextInM! <= reach
                  ? _prepareFrom[next.index] = max(nextInM, 1)
                  : null);
    final turned = _turned;
    final goodSince = _goodSince;
    final onPlan = _onPlan ? pos : null;
    return (
      level: _level,
      recovering: _recovering,
      goodS: _recovering && goodSince != null
          ? now.difference(goodSince).inMilliseconds / 1000
          : null,
      stopped: stopped,
      arrived: _arrived,
      gpsLostS: gpsLostS,
      at: at,
      headingDeg: headingDeg,
      onRoad: onPlan?.onRoad(),
      toPlan: onPlan != null && onPlan.index < 0 ? onPlan.toPlan() : const [],
      speedKmh: speedMps * 3.6,
      limitKmh: limitKmh,
      over: over,
      camera: _speed.cameraAhead(_drivenM),
      next: next,
      nextInM: nextInM,
      prepareM: prepareM,
      then: prepareM != null && after != null && after.atM - next!.atM <= reach
          ? after
          : null,
      newRoute:
          plan != null &&
          identical(plan, _newRoutePlan) &&
          next == decisions.firstOrNull,
      turned:
          turned != null &&
              now.difference(turned.at).inSeconds < LearningConfig.confirmDelayS
          ? (street: turned.street, headingDeg: turned.headingDeg)
          : null,
      street: switch (pos?.edge.streetId) {
        final part? => streets[part],
        null => null,
      },
      district: _district,
      drivenM: _drivenM,
      leftM: plan == null ? null : max(0, plan.endM - progressM),
      leftS: pos?.remainingS(cost),
      side: _sideNow(),
      plan: plan,
      reached: reached,
      viaInM: pos?.viaInM(_via.length),
    );
  }

  /// The next stop's side while the car is on its road, by the way it drives.
  NavSide? _sideNow() {
    final stop = _goal;
    final pos = _pos;
    final side = stop.side;
    if (side == null || pos == null || pos.edge.id != stop.edge?.id) {
      return null;
    }
    return pos.edge.other(pos.from) == stop.toward ? side : side.flipped;
  }

  /// Where on the graph [p] is, driving [heading]: the best snap's edge, the junction ahead and
  /// the share of the edge behind.
  ({RoadEdge edge, int ahead, double along})? _locate(
    LatLng p,
    double? heading,
  ) {
    final snaps = edgeSnaps(graph, p, heading);
    if (snaps.isEmpty) return null;
    final best = snaps.reduce((a, b) => b.cost < a.cost ? b : a);
    return (
      edge: best.edge,
      ahead: best.forward ? best.edge.to : best.edge.from,
      along: best.along,
    );
  }

  void _replan(RoadEdge edge, int ahead, double along) {
    final preferred = _restOf(_prefer, edge, ahead);
    _prefer = null;
    final plan = preferred == null
        ? planNav(
            graph,
            cost,
            from: ahead,
            to: destination,
            via: _via,
            approach: edge,
            streets: streets,
            landmarks: landmarks,
            junctionNodes: junctionNodes,
          )
        : NavPlan.of(
            graph,
            cost,
            preferred,
            stop: destination,
            via: _via,
            approach: edge,
            streets: streets,
            landmarks: landmarks,
            junctionNodes: junctionNodes,
          );
    _pos = plan == null ? null : PlanPosition(plan, edge, along);
    _nextDecision = 0;
    _offFixes = 0;
    _said.clear();
    _prepareFrom.clear();
  }

  /// [route] from [ahead] on, when the car on [edge] joins it there legally; else null.
  Route? _restOf(Route? route, RoadEdge edge, int ahead) {
    if (route == null) return null;
    final k = route.junctions.indexOf(ahead);
    if (k < 0 || k >= route.edges.length) return null;
    final joins = k > 0
        ? route.edges[k - 1].id == edge.id
        : graph
              .legalExits(ahead, approach: edge)
              .any((e) => e.id == route.edges.first.id);
    if (!joins) return null;
    final edges = route.edges.sublist(k);
    return Route(
      route.junctions.sublist(k),
      edges,
      edges.fold(0, (sum, e) => sum + e.lengthM),
    );
  }

  /// The plan's decisions now behind the car, each taken as planned.
  void _passFollowed(DateTime now, bool inGap) {
    final pos = _pos!;
    final decisions = pos.plan.decisions;
    while (_nextDecision < decisions.length &&
        decisions[_nextDecision].atM + LearningConfig.driveSampleM <=
            pos.progressM) {
      final d = decisions[_nextDecision++];
      final help = _helpAt(d);
      _pass(
        d.junction,
        d.approach,
        d.exit,
        planned: true,
        ok: inGap ? null : true,
        now: now,
        help: help,
      );
      if (d.street == null || inGap) continue;
      _turned = (
        at: now,
        street: d.street!,
        headingDeg: leavingBearing(d.exit, d.junction),
      );
      if (help == NavHelp.guided || help == NavHelp.cue) {
        _confirm = (
          at: now.add(const Duration(seconds: LearningConfig.confirmDelayS)),
          street: d.street!,
          headingDeg: _turned!.headingDeg,
          others: [
            for (final e in graph.edgesAt(d.junction))
              if (e.id != d.exit.id && e.id != d.approach?.id) e,
          ],
        );
      }
    }
  }

  /// The help a move had: Guided's, a recovery's, Coached's cue at [d] when it was said.
  NavHelp _helpAt(NavDecision? d) {
    if (_level == DriveLevel.guided || _rescued) return NavHelp.guided;
    if (_recovering) return NavHelp.recovery;
    if (d != null && (_said[d.index]?.contains(PromptKind.prepare) ?? false)) {
      return NavHelp.cue;
    }
    return NavHelp.none;
  }

  void _pass(
    int junction,
    RoadEdge? approach,
    RoadEdge exit, {
    required bool planned,
    required bool? ok,
    required DateTime now,
    required NavHelp help,
  }) {
    final recovered = _lastRecoveryAt;
    passed.add((
      junction: junction,
      approach: approach,
      exit: exit,
      key: junctionKey(junctionNodes, junction, approach, exit),
      planned: planned,
      ok: ok,
      at: now,
      level: _level,
      help: help,
      recentHelp:
          recovered != null &&
          now.difference(recovered).inSeconds <=
              LearningConfig.noCreditAfterPromptS,
    ));
  }

  /// Off the plan for two fixes: judges the move at the junction it left by (§5.3 step 6), plans
  /// again from where the car is, and on a move that lost the good path starts a recovery.
  void _deviate(
    LatLng p,
    double? heading,
    DateTime now,
    bool inGap,
    List<NavPrompt> prompts,
  ) {
    final located = _locate(p, heading);
    if (located == null) return;
    final pos = _pos!;
    final route = pos.plan.route;
    final before = pos.remainingS(cost);
    bool? ok;
    // Past the stop nothing is judged: the car only comes round to it again.
    for (final k in [
      if (pos.progressM <= pos.plan.endM) ...[pos.index + 1, pos.index],
    ]) {
      if (k < 0 || k >= route.junctions.length) continue;
      final j = route.junctions[k];
      final edge = located.edge;
      if ((edge.from != j && edge.to != j) || edge.other(j) != located.ahead) {
        continue;
      }
      final approach = k == 0 ? pos.approach : route.edges[k - 1];
      ok = inGap ? null : _keepsGoodPath(j, approach, edge, located.ahead);
      final planned = pos.plan.decisions.where((d) => d.index == k).firstOrNull;
      if (k < route.edges.length) _retractFollowed(j, route.edges[k]);
      _pass(
        j,
        approach,
        edge,
        planned: planned != null,
        ok: ok,
        now: now,
        help: _helpAt(planned),
      );
      break;
    }
    _replan(located.edge, located.ahead, located.along);
    _lostS += max(0, (_pos?.remainingS(cost) ?? 0) - before);
    if (ok == false) _recover(now, prompts);
    _guard(now, prompts);
  }

  /// Whether leaving [junction] on [exit] after [approach], toward [ahead], is legal and keeps a
  /// good path to the next stop (§5.3 step 6).
  bool _keepsGoodPath(
    int junction,
    RoadEdge? approach,
    RoadEdge exit,
    int ahead,
  ) =>
      graph
          .legalExits(junction, approach: approach)
          .any((e) => e.id == exit.id) &&
      keepsGoodPath(
        exit,
        approach: approach,
        here: graph
            .shortestRoute(
              junction,
              _goal.goals,
              approach: approach,
              arriveOn: _goal.edge,
            )
            ?.costM,
        after: graph
            .shortestRoute(
              ahead,
              _goal.goals,
              approach: exit,
              arriveOn: _goal.edge,
            )
            ?.costM,
      );

  /// At a shallow fork the car snaps to the planned branch while still near it on the other:
  /// that pass of [junction] onto [planned] is taken back, and its street not confirmed.
  void _retractFollowed(int junction, RoadEdge planned) {
    final last = passed.lastOrNull;
    if (last == null ||
        last.junction != junction ||
        last.exit.id != planned.id) {
      return;
    }
    passed.removeLast();
    _turned = null;
    _confirm = null;
  }

  /// After a move that lost the good path: Off says nothing, Guided says the new route's first
  /// turn ("New route"), Coached and Quiet recover (item 115).
  void _recover(DateTime now, List<NavPrompt> prompts) {
    if (_level == DriveLevel.off) return;
    prompts.add(
      _prompt(PromptKind.recovery, decision: _plan?.decisions.firstOrNull),
    );
    if (_level == DriveLevel.guided) {
      _newRoutePlan = _plan;
      return;
    }
    _recovering = true;
    _goodSince = null;
    _lastRecoveryAt = now;
    _recoveries.add(now);
    if (_level == DriveLevel.coached) _recoveriesAtCoached++;
  }

  /// Item 115's frustration guard: Quiet goes Coached after two recoveries within
  /// [LearningConfig.guardWindowS] or [LearningConfig.guardLostS] lost; Coached goes Guided after
  /// [LearningConfig.guardToGuidedRecoveries] recoveries.
  void _guard(DateTime now, List<NavPrompt> prompts) {
    final recent = _recoveries
        .where(
          (t) => now.difference(t).inSeconds <= LearningConfig.guardWindowS,
        )
        .length;
    if (_level == DriveLevel.quiet &&
        !_guarded &&
        (recent >= LearningConfig.guardRecoveries ||
            _lostS >= LearningConfig.guardLostS)) {
      _level = DriveLevel.coached;
      _guarded = true;
      prompts.add(_prompt(PromptKind.guard));
    } else if (_level == DriveLevel.coached &&
        _recoveriesAtCoached >= LearningConfig.guardToGuidedRecoveries) {
      _level = DriveLevel.guided;
    }
  }

  /// The next decision's prepare and action prompts (item 117): every decision in Guided and
  /// while recovering, the prepare prompt only at Coached's decisions that aren't silent, none
  /// at Quiet and Off.
  void _promptNext(DateTime now, double speed, List<NavPrompt> prompts) {
    final pos = _pos;
    if (pos == null || _nextDecision >= pos.plan.decisions.length) return;
    final d = pos.plan.decisions[_nextDecision];
    final full = _recovering || _level == DriveLevel.guided;
    final cue = _level == DriveLevel.coached && !_silent.contains(d.key);
    if (!full && !cue) return;
    final said = _said.putIfAbsent(d.index, () => {});
    final distM = d.atM - pos.progressM;
    final actionAt = max(
      LearningConfig.actionM,
      LearningConfig.actionS * speed,
    );
    final prepareAt = max(
      LearningConfig.prepareM,
      LearningConfig.prepareS * speed,
    );
    if (full && distM <= actionAt) {
      if (said.add(PromptKind.action)) {
        said.add(PromptKind.prepare);
        prompts.add(_prompt(PromptKind.action, decision: d));
      }
    } else if (distM <= prepareAt && said.add(PromptKind.prepare)) {
      prompts.add(
        _prompt(
          PromptKind.prepare,
          decision: d,
          distanceM: d.landmark == null && !d.signals ? distM : null,
        ),
      );
    }
  }

  /// A district cue (item 117) on crossing into another district in Guided and Coached, at most
  /// every [LearningConfig.districtCueM] and [LearningConfig.districtCueS].
  void _cueDistrict(
    LatLng p,
    double? heading,
    DateTime now,
    List<NavPrompt> prompts,
  ) {
    final name = districtAt?.call(p);
    if (name == null || name == _district) return;
    final first = _district == null;
    _district = name;
    final cueAt = _cueAt;
    if (first ||
        (_level != DriveLevel.guided && _level != DriveLevel.coached) ||
        (cueAt != null &&
            (now.difference(cueAt).inSeconds < LearningConfig.districtCueS ||
                _drivenM - _cueAtM < LearningConfig.districtCueM))) {
      return;
    }
    _cueAt = now;
    _cueAtM = _drivenM;
    prompts.add(
      _prompt(PromptKind.district, district: name, headingDeg: heading),
    );
  }
}
