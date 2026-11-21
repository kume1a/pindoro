import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'constants.dart';
import 'drive.dart';
import 'drive_log.dart';
import 'nav_level.dart';
import 'nav_route.dart';
import 'recital.dart';
import 'route_questions.dart';
import 'routes.dart';

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

/// What the drive screen shows after a fix or a tick.
typedef NavView = ({
  DriveLevel level,
  bool recovering,
  bool stopped,
  bool arrived,

  /// Seconds since the last fix once over [LearningConfig.gpsGapS]; null while GPS is fine.
  int? gpsLostS,
  LatLng? at,
  double? headingDeg,
  double speedKmh,
  int? limitKmh,
  bool over,
  NavDecision? next,
  double? nextInM,
  String? district,
  NavPlan? plan,
});

/// One step of navigation: the view, at most one prompt, and whether to chime for speed.
typedef NavUpdate = ({NavView view, NavPrompt? prompt, bool chime});

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

double _angleOff(double a, double b) =>
    (((a - b) % 360 + 540) % 360 - 180).abs();

/// Navigation to [destination] fed one fix at a time (SPEC §16.23 items 112–117, 127): where the
/// car is on the plan, the next decision and its prompts by level, a silent new plan after a
/// move that keeps a good path, recovery after one that doesn't, the frustration guard, district
/// cues, speed and camera warnings, stops and arrival. Times come from the fixes, so it replays.
class Navigator {
  Navigator({
    required this.graph,
    required this.cost,
    required this.destination,
    required DriveLevel level,
    this.streets = const {},
    this.landmarks = const [],
    this.junctionNodes = const {},
    this.silent = const {},
    this.districtAt,
  }) : _level = level,
       _camerasByEdge = _byEdge(graph.cameras);

  final RoadGraph graph;
  final NavCost cost;
  final int destination;

  /// By part id.
  final Map<String, NamedStreet> streets;
  final List<RouteLandmark> landmarks;
  final Map<int, int> junctionNodes;

  /// The silent-eligible decisions, by key: Coached says nothing at them.
  final Set<String> silent;

  /// The district a point lies in, for cues and the screen.
  final String? Function(LatLng at)? districtAt;

  final Map<int, List<SpeedCamera>> _camerasByEdge;

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

  DriveLevel get level => _level;
  bool get rescued => _rescued;
  int get recoveries => _recoveries.length;

  /// Seconds the drive lost against its plans (the detours' extra time).
  double get lostS => _lostS;

  /// A level chosen while stopped (item 116), at once.
  void setLevel(DriveLevel level) => _level = level;

  /// Off's Rescue (item 116): Guided to the destination; later decisions are watched only.
  void rescue() {
    _level = DriveLevel.guided;
    _rescued = true;
  }

  NavUpdate onFix(DriveFix fix) {
    final now = fix.t;
    final last = _last;
    final gapS = last == null
        ? 0.0
        : now.difference(last.t).inMilliseconds / 1000;
    final inGap = gapS > LearningConfig.gpsGapS;
    final moved = last == null ? 0.0 : distanceBetween(last.at, fix.at);
    final speed = fix.speedMps ?? (gapS > 0 ? moved / gapS : 0.0);
    _drivenM += moved;
    _last = fix;
    final heading = speed > 2 ? fix.headingDeg : null;
    final prompts = <NavPrompt>[];

    final where = _plan == null ? null : _track(fix.at, heading);
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
    _cueDistrict(fix.at, heading, now, prompts);
    final edge = _edgeNow;
    _warnCameras(speed, prompts);

    final kmh = speed * 3.6;
    final limit = edge == null ? null : cost.limitKmh(edge);
    final over = limit != null && kmh > limit + cost.toleranceKmh;
    var chime = false;
    if (over) {
      final since = _overSince ??= now;
      final chimed = _chimedAt;
      if (now.difference(since).inSeconds >= LearningConfig.overspeedHoldS &&
          (chimed == null ||
              now.difference(chimed).inSeconds >=
                  LearningConfig.overspeedRepeatS)) {
        chime = true;
        _chimedAt = now;
      }
    } else {
      _overSince = null;
    }
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
        at: fix.at,
        headingDeg: fix.headingDeg,
        speedKmh: kmh,
        limitKmh: limit,
        over: over,
        stopped: stopped,
        gpsLostS: null,
      ),
      prompt: prompts.firstOrNull,
      chime: chime,
    );
  }

  /// Time passing without fixes: the GPS line after [LearningConfig.gpsGapS], "Still finding
  /// you" once at [LearningConfig.gpsLostSayS].
  NavUpdate onTick(DateTime now) {
    final last = _last;
    final gapS = last == null ? 0 : now.difference(last.t).inSeconds;
    NavPrompt? prompt;
    if (last != null &&
        gapS >= LearningConfig.gpsLostSayS &&
        _stillSaidFor != last.t) {
      _stillSaidFor = last.t;
      prompt = _prompt(PromptKind.stillFinding);
    }
    return (
      view: _view(
        at: last?.at,
        headingDeg: last?.headingDeg,
        speedKmh: 0,
        limitKmh: switch (_edgeNow) {
          final e? => cost.limitKmh(e),
          null => null,
        },
        over: false,
        stopped: _stopped(now),
        gpsLostS: gapS > LearningConfig.gpsGapS ? gapS : null,
      ),
      prompt: prompt,
      chime: false,
    );
  }

  bool _stopped(DateTime now) {
    final since = _slowSince;
    return since != null &&
        now.difference(since).inSeconds >= LearningConfig.stoppedHoldS;
  }

  NavView _view({
    required LatLng? at,
    required double? headingDeg,
    required double speedKmh,
    required int? limitKmh,
    required bool over,
    required bool stopped,
    required int? gpsLostS,
  }) {
    final plan = _plan;
    final next = plan == null || _nextDecision >= plan.decisions.length
        ? null
        : plan.decisions[_nextDecision];
    return (
      level: _level,
      recovering: _recovering,
      stopped: stopped,
      arrived: _arrived,
      gpsLostS: gpsLostS,
      at: at,
      headingDeg: headingDeg,
      speedKmh: speedKmh,
      limitKmh: limitKmh,
      over: over,
      next: next,
      nextInM: next == null ? null : next.atM - _progressM,
      district: _district,
      plan: plan,
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
    final plan = planNav(
      graph,
      cost,
      from: ahead,
      to: destination,
      approach: edge,
      streets: streets,
      landmarks: landmarks,
      junctionNodes: junctionNodes,
    );
    _plan = plan;
    _approach = edge;
    _junctionM = plan?.junctionM ?? const [];
    _index = -1;
    _progressM = -(1 - along) * edge.lengthM;
    _nextDecision = 0;
    _offFixes = 0;
    _said.clear();
  }

  /// The car on the plan near where it was: its progress, or null when it is off the plan.
  double? _track(LatLng p, double? heading) {
    final plan = _plan!;
    final edges = plan.route.edges;
    ({int i, double distM, double alongM})? best;
    for (var i = max(-1, _index); i <= min(_index + 3, edges.length - 1); i++) {
      final e = i < 0 ? _approach! : edges[i];
      final from = i < 0
          ? _approach!.other(plan.route.junctions.first)
          : plan.route.junctions[i];
      final n = nearestOnEdge(p, e);
      if (n.distM > LearningConfig.driveSnapM) continue;
      final forward = from == e.from;
      final way = forward ? n.headingDeg : (n.headingDeg + 180) % 360;
      if (heading != null && _angleOff(heading, way) > 100) continue;
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
      final spoken = help == NavHelp.guided || help == NavHelp.cue;
      if (spoken && d.street != null && !inGap) {
        _confirm = (
          at: now.add(const Duration(seconds: LearningConfig.confirmDelayS)),
          street: d.street!,
          headingDeg: leavingBearing(d.exit, d.junction),
        );
      }
    }
  }

  NavHelp _helpAt(NavDecision d) {
    if (_level == DriveLevel.guided || _rescued) return NavHelp.guided;
    if (_recovering) return NavHelp.recovery;
    if (_said[d.index]?.contains(PromptKind.prepare) ?? false) {
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
    final node = junctionNodes[junction];
    final from = approach == null
        ? null
        : junctionNodes[approach.other(junction)];
    final to = junctionNodes[exit.other(junction)];
    final recovered = _lastRecoveryAt;
    passed.add((
      junction: junction,
      approach: approach,
      exit: exit,
      key: node == null || from == null || to == null
          ? null
          : RouteIds.junction(node, from, to),
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
        help: planned == null ? _helpNow : _helpAt(planned),
      );
      break;
    }
    _replan(located.edge, located.ahead, located.along);
    _lostS += max(0, _remainingS() - before);
    if (ok == false) _recover(now, prompts);
    _guard(now, prompts);
  }

  NavHelp get _helpNow => _level == DriveLevel.guided || _rescued
      ? NavHelp.guided
      : _recovering
      ? NavHelp.recovery
      : NavHelp.none;

  /// After a move that lost the good path: Off says nothing, Guided says the new route's first
  /// turn ("New route"), Coached and Quiet recover (item 115).
  void _recover(DateTime now, List<NavPrompt> prompts) {
    if (_level == DriveLevel.off) return;
    prompts.add(
      _prompt(PromptKind.recovery, decision: _plan?.decisions.firstOrNull),
    );
    if (_level == DriveLevel.guided) return;
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
                _angleOff(direction, way) > LearningConfig.cameraHeadingDeg) ||
            !_warned.add(c.id)) {
          continue;
        }
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
      key: switch ((
        junctionNodes[d.junction],
        d.approach == null
            ? null
            : junctionNodes[d.approach!.other(d.junction)],
        junctionNodes[d.exit.other(d.junction)],
      )) {
        (final node?, final from?, final to?) => RouteIds.junction(
          node,
          from,
          to,
        ),
        _ => null,
      },
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
