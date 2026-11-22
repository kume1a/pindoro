import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'constants.dart';
import 'drive.dart';
import 'drive_log.dart';
import 'grader.dart';
import 'nav_level.dart';
import 'nav_route.dart';
import 'recital.dart';
import 'route_questions.dart';

/// What navigation says, most urgent first (SPEC §16.23 items 115, 117, 127): when two come
/// together the first wins and the other is dropped.
enum PromptKind {
  action,
  camera,
  guard,
  recovery,
  prepare,
  confirmation,
  district,
  stillFinding,
}

/// A prompt for the app to word and speak: the [decision] of an action, prepare or recovery
/// prompt ([distanceM] when no landmark or lights name it); a confirmation's [street]; a
/// district cue's [district]; with the [headingDeg] driven; a camera's [limitKmh].
typedef NavPrompt = ({
  PromptKind kind,
  NavDecision? decision,
  double? distanceM,
  NamedStreet? street,
  String? district,
  double? headingDeg,
  int? limitKmh,
});

/// A junction passed on a drive with a way on to choose (SPEC §16.23 item 124): the move made
/// ([key] its J item id), whether the plan had a decision there ([planned]; a wrong turn
/// elsewhere has none), whether it kept a good path ([ok]; null in a GPS gap), the level and
/// help then, and whether a recovery was on within [LearningConfig.noCreditAfterPromptS].
typedef PassedDecision = ({
  int junction,
  RoadEdge? approach,
  RoadEdge exit,
  String? key,
  bool planned,
  bool? ok,
  DateTime at,
  DriveLevel level,
  NavHelp help,
  bool recentHelp,
});

/// What the drive screen shows after a fix or a tick (boards V32-20 to V32-41).
typedef NavView = ({
  DriveLevel level,
  bool recovering,

  /// Seconds back on a good path while [recovering]: the 10 s ring.
  double? goodS,
  bool stopped,
  bool arrived,

  /// Seconds since the last fix once over [LearningConfig.gpsGapS]; null while GPS is fine.
  int? gpsLostS,
  LatLng? at,
  double? headingDeg,

  /// The car on its plan and the way the road runs there ([LearningConfig.navRoadAheadM]
  /// ahead): Guided's car and bearing, the road ahead straight up (item 130). Null off the
  /// plan or before its first junction.
  ({LatLng at, double headingDeg})? onRoad,

  /// The road from the car to the plan's first junction while it is still short of it (the
  /// plan's route starts there); empty once on the route.
  Polyline toPlan,
  double speedKmh,
  int? limitKmh,

  /// Over the limit plus the tolerance for [LearningConfig.overspeedHoldS]: the sign pulses.
  bool over,

  /// A camera was warned of and isn't passed yet.
  bool camera,
  NavDecision? next,
  double? nextInM,

  /// How far before [next] its approach began (the plate shows from the prepare point); null
  /// before it.
  double? prepareM,

  /// The decision after [next] when it comes within the prepare reach of it: "then".
  NavDecision? then,

  /// The first decision of a new route after a wrong turn in Guided.
  bool newRoute,

  /// The street just turned onto and its heading, until the voice confirms it.
  ({NamedStreet street, double headingDeg})? turned,

  /// The car's street.
  NamedStreet? street,
  String? district,

  /// The metres driven so far: with [leftM], the bar's progress.
  double drivenM,

  /// The plan's metres and seconds left.
  double? leftM,
  double? leftS,
  NavPlan? plan,
});

/// One step of navigation: the view, the prompts due (most urgent first; each is due once, so
/// the app says them all), and whether to chime for speed.
typedef NavUpdate = ({NavView view, List<NavPrompt> prompts, bool chime});

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
/// cues, speed and camera warnings, stops and arrival. Times come from the fixes, so it replays.
class Navigator {
  Navigator({
    required this.graph,
    required this.cost,
    required int destination,
    required DriveLevel level,
    this.streets = const {},
    this.landmarks = const [],
    this.junctionNodes = const {},
    this.silent = const {},
    this.districtAt,
    Route? prefer,
  }) : _prefer = prefer,
       _destination = destination,
       _level = level,
       _camerasByEdge = _byEdge(graph.cameras);

  final RoadGraph graph;
  final NavCost cost;
  int _destination;
  int get destination => _destination;

  /// By part id.
  final Map<String, NamedStreet> streets;
  final List<RouteLandmark> landmarks;
  final Map<int, int> junctionNodes;

  /// The silent-eligible decisions, by key: Coached says nothing at them.
  Set<String> silent;

  /// The district a point lies in, for cues and the screen.
  final String? Function(LatLng at)? districtAt;

  final Map<int, List<SpeedCamera>> _camerasByEdge;

  /// The route picked at setup (SPEC §16.23 item 129): the first plan follows it from where the
  /// car joins it; once off it, the quickest way is planned as ever.
  Route? _prefer;

  /// The decisions passed so far, in order.
  final List<PassedDecision> passed = [];

  DriveLevel _level;
  bool _rescued = false;
  NavPlan? _plan;
  RoadEdge? _approach;
  List<double> _junctionM = const [];
  int _index = -1;
  double _progressM = 0;
  int _nextDecision = 0;
  int _offFixes = 0;
  final Map<int, Set<PromptKind>> _said = {};

  bool _recovering = false;
  DateTime? _goodSince;
  DateTime? _lastRecoveryAt;
  final List<DateTime> _recoveries = [];
  int _recoveriesAtCoached = 0;
  double _lostS = 0;
  bool _guarded = false;

  ({DateTime at, NamedStreet street, double headingDeg})? _confirm;
  ({DateTime at, NamedStreet street, double headingDeg})? _turned;
  final Map<int, double> _prepareFrom = {};
  NavPlan? _newRoutePlan;
  double _cameraUntilM = 0;
  String? _district;
  DateTime? _cueAt;
  double _cueAtM = 0;
  double _drivenM = 0;
  final Set<int> _warned = {};
  DateTime? _overSince;
  DateTime? _chimedAt;
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
  bool get rescued => _rescued;
  int get recoveries => _recoveries.length;

  /// Seconds the drive lost against its plans (the detours' extra time).
  double get lostS => _lostS;

  /// A level chosen while stopped (item 116), at once.
  void setLevel(DriveLevel level) => _level = level;

  /// A destination changed while stopped (item 116), with its route's [silent] decisions: the
  /// next fix plans the way there.
  void setDestination(int to, {Set<String> silent = const {}}) {
    _destination = to;
    this.silent = silent;
    _prefer = null;
    _plan = null;
    _arrived = false;
  }

  /// Off's Rescue (item 116): Guided to the destination; later decisions are watched only.
  void rescue() {
    _level = DriveLevel.guided;
    _rescued = true;
  }

  /// Other ways on from the car (SPEC §16.23 item 130's routes): the quickest drives to the
  /// destination from its next junction, leaving out the rest of the plan; none off the plan.
  List<NavPlan> routeOptions() {
    final plan = _plan;
    final edge = _edgeNow;
    if (plan == null || edge == null || !_onPlan) return const [];
    final rest = [for (final e in plan.route.edges.skip(_index + 1)) e.id];
    return [
      for (final option in planNavOptions(
        graph,
        cost,
        from: plan.route.junctions[_index + 1],
        to: destination,
        approach: edge,
        streets: streets,
        landmarks: landmarks,
        junctionNodes: junctionNodes,
      ))
        if (!_sameIds(option.route.edges, rest)) option,
    ];
  }

  /// Drives [option] (one of [routeOptions]) from here on, at once and without a word.
  void takeRoute(NavPlan option) {
    final plan = _plan;
    final edge = _edgeNow;
    if (plan == null || edge == null) return;
    _prefer = option.route;
    _replan(
      edge,
      plan.route.junctions[_index + 1],
      edge.lengthM == 0 ? 1 : _alongNow / edge.lengthM,
    );
  }

  static bool _sameIds(List<RoadEdge> edges, List<int> ids) =>
      edges.length == ids.length &&
      edges.indexed.every((e) => e.$2.id == ids[e.$1]);

  NavUpdate onFix(DriveFix fix) {
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
    final heading = speed > 2 ? fix.headingDeg : null;
    _headingDeg = heading ?? _headingDeg;
    final prompts = <NavPrompt>[];

    final where = _plan == null ? null : _track(fix.at, heading, wide: inGap);
    _onPlan = where != null;
    if (_plan == null) {
      final located = _locate(fix.at, heading);
      if (located != null) _replan(located.edge, located.ahead, located.along);
    } else if (where == null) {
      if (++_offFixes >= 2) _deviate(fix.at, heading, now, inGap, prompts);
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
    _promptNext(now, speed, prompts);
    if (_confirm case final c? when !now.isBefore(c.at)) {
      prompts.add(
        _prompt(
          PromptKind.confirmation,
          street: c.street,
          headingDeg: c.headingDeg,
        ),
      );
      _confirm = null;
    }
    _cueDistrict(fix.at, _headingDeg, now, prompts);
    final edge = _edgeNow;
    _warnCameras(speed, prompts);

    final kmh = speed * 3.6;
    final limit = edge == null ? null : cost.limitKmh(edge);
    final (:warned, :chime) = _overspeed(now, kmh, limit);
    if (kmh < LearningConfig.stoppedKmh) {
      _slowSince ??= now;
    } else {
      _slowSince = null;
    }
    final stopped = _stopped(now);
    if (stopped &&
        distanceBetween(fix.at, graph.at(destination)) <=
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
      ),
      prompts: prompts,
      chime: chime,
    );
  }

  /// Over [limit] plus the tolerance for [LearningConfig.overspeedHoldS]: [warned], and a
  /// [chime] then and every [LearningConfig.overspeedRepeatS] while it lasts.
  ({bool warned, bool chime}) _overspeed(DateTime now, double kmh, int? limit) {
    if (limit == null || kmh <= limit + cost.toleranceKmh) {
      _overSince = null;
      return (warned: false, chime: false);
    }
    final since = _overSince ??= now;
    final chimed = _chimedAt;
    final warned =
        now.difference(since).inSeconds >= LearningConfig.overspeedHoldS;
    final chime =
        warned &&
        (chimed == null ||
            now.difference(chimed).inSeconds >=
                LearningConfig.overspeedRepeatS);
    if (chime) _chimedAt = now;
    return (warned: warned, chime: chime);
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
        limitKmh: switch (_edgeNow) {
          final e? => cost.limitKmh(e),
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
  }) {
    final plan = _plan;
    final decisions = plan?.decisions ?? const <NavDecision>[];
    final next = _nextDecision < decisions.length
        ? decisions[_nextDecision]
        : null;
    final after = _nextDecision + 1 < decisions.length
        ? decisions[_nextDecision + 1]
        : null;
    final nextInM = next == null ? null : next.atM - _progressM;
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
    final edge = _edgeNow;
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
      onRoad: plan != null && _onPlan ? _onRoad(plan) : null,
      toPlan: plan != null && _onPlan && _index < 0 ? _toPlan() : const [],
      speedKmh: speedMps * 3.6,
      limitKmh: limitKmh,
      over: over,
      camera: _drivenM < _cameraUntilM,
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
      street: edge?.streetId == null ? null : streets[edge!.streetId],
      district: _district,
      drivenM: _drivenM,
      leftM: plan == null ? null : plan.route.lengthM - _progressM,
      leftS: plan == null ? null : _remainingS(),
      plan: plan,
    );
  }

  ({LatLng at, double headingDeg})? _onRoad(NavPlan plan) {
    final edge = _edgeNow!;
    if (edge.lengthM <= 0) return null;
    // Before the plan's first junction the car is on the edge it arrived on.
    final ahead = _index >= 0
        ? plan.slice(_progressM, _progressM + LearningConfig.navRoadAheadM)
        : linePart(
            edge.lineFrom(_fromNow!),
            _alongNow / edge.lengthM,
            min(1, (_alongNow + LearningConfig.navRoadAheadM) / edge.lengthM),
          );
    if (ahead.length < 2 || distanceBetween(ahead.first, ahead.last) < 1) {
      return null;
    }
    return (
      at: ahead.first,
      headingDeg: bearingDegrees(ahead.first, ahead.last),
    );
  }

  Polyline _toPlan() {
    final edge = _approach!;
    if (edge.lengthM <= 0) return const [];
    return linePart(
      edge.lineFrom(_fromNow!),
      (_alongNow / edge.lengthM).clamp(0, 1),
      1,
    );
  }

  /// The edge the car is on, by the plan.
  RoadEdge? get _edgeNow {
    final plan = _plan;
    if (plan == null) return null;
    return _index < 0 ? _approach : plan.route.edges[_index];
  }

  /// The junction the car drives away from on [_edgeNow].
  int? get _fromNow {
    final plan = _plan;
    if (plan == null) return null;
    if (_index >= 0) return plan.route.junctions[_index];
    return _approach?.other(plan.route.junctions.first);
  }

  /// The car's edge (driven away from [_fromNow]) and the metres along it.
  double get _alongNow => _index < 0
      ? _approach!.lengthM + _progressM
      : _progressM - _junctionM[_index];

  static Map<int, List<SpeedCamera>> _byEdge(List<SpeedCamera> cameras) {
    final out = <int, List<SpeedCamera>>{};
    for (final c in cameras) {
      out.putIfAbsent(c.edgeId, () => []).add(c);
    }
    return out;
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
            approach: edge,
            streets: streets,
            landmarks: landmarks,
            junctionNodes: junctionNodes,
          )
        : NavPlan(
            preferred,
            navDecisions(
              graph,
              preferred,
              approach: edge,
              streets: streets,
              landmarks: landmarks,
              junctionNodes: junctionNodes,
            ),
            cost.secondsOf(preferred),
          );
    _plan = plan;
    _approach = edge;
    _junctionM = plan?.junctionM ?? const [];
    _index = -1;
    _progressM = -(1 - along) * edge.lengthM;
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

  /// The car on the plan near where it was ([wide]: anywhere further along, after a GPS gap):
  /// its progress, or null when it is off the plan.
  double? _track(LatLng p, double? heading, {bool wide = false}) {
    final plan = _plan!;
    final edges = plan.route.edges;
    final last = wide ? edges.length - 1 : min(_index + 3, edges.length - 1);
    ({int i, double distM, double alongM})? best;
    for (var i = max(-1, _index); i <= last; i++) {
      final e = i < 0 ? _approach! : edges[i];
      final from = i < 0
          ? _approach!.other(plan.route.junctions.first)
          : plan.route.junctions[i];
      final n = nearestOnEdge(p, e);
      if (n.distM > LearningConfig.driveSnapM) continue;
      final forward = from == e.from;
      final way = forward ? n.headingDeg : (n.headingDeg + 180) % 360;
      if (heading != null && bearingError(heading, way) > 100) continue;
      if (best == null || n.distM < best.distM) {
        best = (
          i: i,
          distM: n.distM,
          alongM: (forward ? n.along : 1 - n.along) * e.lengthM,
        );
      }
    }
    if (best == null) return null;
    _index = best.i;
    _progressM = best.i < 0
        ? best.alongM - _approach!.lengthM
        : _junctionM[best.i] + best.alongM;
    return _progressM;
  }

  /// The plan's decisions now behind the car, each taken as planned.
  void _passFollowed(DateTime now, bool inGap) {
    final decisions = _plan!.decisions;
    while (_nextDecision < decisions.length &&
        decisions[_nextDecision].atM + LearningConfig.driveSampleM <=
            _progressM) {
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
    final plan = _plan!;
    final route = plan.route;
    final before = _remainingS();
    bool? ok;
    for (final k in [_index + 1, _index]) {
      if (k < 0 || k >= route.junctions.length) continue;
      final j = route.junctions[k];
      final edge = located.edge;
      if ((edge.from != j && edge.to != j) || edge.other(j) != located.ahead) {
        continue;
      }
      final approach = k == 0 ? _approach : route.edges[k - 1];
      ok = inGap
          ? null
          : graph
                    .legalExits(j, approach: approach)
                    .any((e) => e.id == edge.id) &&
                keepsGoodPath(
                  edge,
                  approach: approach,
                  here: graph.shortestRoute(j, {
                    destination,
                  }, approach: approach)?.costM,
                  after: graph.shortestRoute(located.ahead, {
                    destination,
                  }, approach: edge)?.costM,
                );
      final planned = plan.decisions.where((d) => d.index == k).firstOrNull;
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
    _lostS += max(0, _remainingS() - before);
    if (ok == false) _recover(now, prompts);
    _guard(now, prompts);
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

  /// The plan's time left from the car.
  double _remainingS() {
    final plan = _plan;
    if (plan == null) return 0;
    final edge = _edgeNow!;
    final share = edge.lengthM == 0 ? 0 : 1 - _alongNow / edge.lengthM;
    var s = share * cost.seconds(edge);
    for (var i = _index + 1; i < plan.route.edges.length; i++) {
      s += cost.seconds(plan.route.edges[i]);
    }
    return s;
  }

  /// The next decision's prepare and action prompts (item 117): every decision in Guided and
  /// while recovering, the prepare prompt only at Coached's decisions that aren't silent, none
  /// at Quiet and Off.
  void _promptNext(DateTime now, double speed, List<NavPrompt> prompts) {
    final plan = _plan;
    if (plan == null || _nextDecision >= plan.decisions.length) return;
    final d = plan.decisions[_nextDecision];
    final full = _recovering || _level == DriveLevel.guided;
    final cue = _level == DriveLevel.coached && !silent.contains(d.key);
    if (!full && !cue) return;
    final said = _said.putIfAbsent(d.index, () => {});
    final distM = d.atM - _progressM;
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

  /// A camera on the road ahead (item 127): along the car's edge and on along the same street,
  /// checking the car's way, within the larger of [LearningConfig.cameraWarnM] and
  /// [LearningConfig.cameraWarnS]; once each.
  void _warnCameras(double speed, List<NavPrompt> prompts) {
    var edge = _edgeNow;
    var from = _fromNow;
    if (edge == null || from == null || graph.cameras.isEmpty) return;
    final reach = max(
      LearningConfig.cameraWarnM,
      LearningConfig.cameraWarnS * speed,
    );
    var startM = -_alongNow;
    for (var hop = 0; hop < 10 && startM <= reach; hop++) {
      for (final c in _camerasByEdge[edge!.id] ?? const <SpeedCamera>[]) {
        final n = nearestOnEdge(c.at, edge);
        final forward = from == edge.from;
        final aheadM =
            startM + (forward ? n.along : 1 - n.along) * edge.lengthM;
        final way = forward ? n.headingDeg : (n.headingDeg + 180) % 360;
        final direction = c.directionDeg;
        if (aheadM < 0 ||
            aheadM > reach ||
            (direction != null &&
                bearingError(direction, way) >
                    LearningConfig.cameraHeadingDeg) ||
            !_warned.add(c.id)) {
          continue;
        }
        _cameraUntilM = max(_cameraUntilM, _drivenM + aheadM);
        prompts.add(
          _prompt(
            PromptKind.camera,
            limitKmh: c.maxspeedKmh ?? cost.limitKmh(edge),
          ),
        );
      }
      startM += edge.lengthM;
      final at = edge.other(from!);
      final on = _straightOn(edge, at);
      if (on == null) break;
      (edge, from) = (on, at);
    }
  }

  /// The way on from [junction] after [edge] along the same street, the straightest within
  /// 45°; null at its end.
  RoadEdge? _straightOn(RoadEdge edge, int junction) {
    final street = edge.streetId;
    if (street == null) return null;
    final name = streets[street]?.id ?? street;
    RoadEdge? best;
    var bestDeg = 45.0;
    for (final e in graph.legalExits(junction, approach: edge)) {
      if (e.id == edge.id || e.streetId == null) continue;
      if ((streets[e.streetId]?.id ?? e.streetId) != name) continue;
      final deg = turnAngle(edge, e, junction).abs();
      if (deg <= bestDeg) (best, bestDeg) = (e, deg);
    }
    return best;
  }
}

/// The junctions with a way on to choose on a graded GPS-free drive, for the drive log (SPEC
/// §16.23 item 124): each move with its J item id, whether navigation calls it a decision
/// (item 112), whether it kept a good path, and the time of the fix nearest the junction. No
/// help at Off.
List<PassedDecision> offDriveDecisions(
  RoadGraph graph,
  RecitalResult graded,
  List<DriveFix> fixes, {
  Map<int, int> junctionNodes = const {},
}) => [
  for (final d in graded.decisions)
    (
      junction: d.junction,
      approach: d.approach,
      exit: d.exit,
      key: junctionKey(junctionNodes, d.junction, d.approach, d.exit),
      planned: isDecision(
        graph,
        d.junction,
        d.approach,
        d.exit,
        newStreet: d.newStreet,
      ),
      ok: d.correct,
      at: _nearestFix(fixes, graph.at(d.junction)),
      level: DriveLevel.off,
      help: NavHelp.none,
      recentHelp: false,
    ),
];

DateTime _nearestFix(List<DriveFix> fixes, LatLng p) => fixes
    .reduce(
      (a, b) => distanceBetween(b.at, p) < distanceBetween(a.at, p) ? b : a,
    )
    .t;

/// Whether the drive [match] hesitated within [LearningConfig.hesitationBeforeM] of [junction]
/// (SPEC §16.23 item 119: Hard, not Good).
bool hesitatedNear(RoadGraph graph, DriveMatch match, int junction) =>
    match.hesitations.any(
      (h) =>
          distanceBetween(h, graph.at(junction)) <=
          LearningConfig.hesitationBeforeM,
    );
