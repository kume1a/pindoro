import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'constants.dart';
import 'recital.dart';

/// A GPS fix of a drive: where, when, and the heading, speed and accuracy the device reported
/// (any may be missing).
typedef DriveFix = ({
  LatLng at,
  DateTime t,
  double? headingDeg,
  double? speedMps,
  double? accuracyM,
});

/// A drive matched to the road graph (SPEC §5.3 "Drives").
final class DriveMatch {
  const DriveMatch({
    required this.path,
    required this.uTurns,
    required this.hesitations,
    required this.drivenM,
  });

  /// The edges driven, junction to junction; no edges when no fix lay near a road.
  final Route path;

  /// Where the car turned back.
  final List<LatLng> uTurns;

  /// Where it crawled below [LearningConfig.hesitationKmh] for over
  /// [LearningConfig.hesitationS] away from junctions.
  final List<LatLng> hesitations;

  /// The distance driven along the fixes.
  final double drivenM;
}

/// A fix on an edge driven one way ([forward]: from its `from` junction): what snapping there
/// costs and the share of the edge behind it.
typedef EdgeSnap = ({RoadEdge edge, bool forward, double cost, double along});

int _start(EdgeSnap s) => s.forward ? s.edge.from : s.edge.to;
int _end(EdgeSnap s) => s.forward ? s.edge.to : s.edge.from;

double _angleOff(double a, double b) =>
    (((a - b) % 360 + 540) % 360 - 180).abs();

/// The point of [e]'s line nearest [p]: its distance, the line's heading there and the share of
/// the line before it.
({double distM, double headingDeg, double along}) nearestOnEdge(
  LatLng p,
  RoadEdge e,
) {
  final proj = LocalProjection(p);
  final xy = e.line.map(proj.project).toList();
  var best = double.infinity;
  var heading = 0.0;
  var at = 0.0;
  var walked = 0.0;
  for (var i = 0; i + 1 < xy.length; i++) {
    final (ax, ay) = xy[i];
    final (bx, by) = xy[i + 1];
    final dx = bx - ax, dy = by - ay;
    final len = sqrt(dx * dx + dy * dy);
    final t = len == 0
        ? 0.0
        : ((-ax * dx - ay * dy) / (len * len)).clamp(0.0, 1.0);
    final d = sqrt(pow(ax + t * dx, 2) + pow(ay + t * dy, 2));
    if (d < best) {
      best = d;
      heading = (atan2(dx, dy) * 180 / pi + 360) % 360;
      at = walked + t * len;
    }
    walked += len;
  }
  return (
    distM: best,
    headingDeg: heading,
    along: walked == 0 ? 0 : at / walked,
  );
}

/// The edges within [LearningConfig.driveSnapM] of [p], each way, costed by distance, heading
/// off the way driven ([heading], when known) and driving against a one-way.
List<EdgeSnap> edgeSnaps(RoadGraph graph, LatLng p, double? heading) {
  const r = LearningConfig.driveSnapM;
  final out = <EdgeSnap>[];
  for (final e in graph.edges) {
    // A point within r of the edge is at most its length plus 2r from both ends together.
    if (distanceBetween(p, graph.at(e.from)) +
            distanceBetween(p, graph.at(e.to)) >
        e.lengthM + 2 * r) {
      continue;
    }
    final n = nearestOnEdge(p, e);
    if (n.distM > r) continue;
    for (final forward in [true, false]) {
      var cost = n.distM;
      if (heading != null) {
        final way = forward ? n.headingDeg : (n.headingDeg + 180) % 360;
        cost += LearningConfig.driveHeadingM * _angleOff(heading, way) / 90;
      }
      if (!graph.canDrive(e, forward ? e.from : e.to)) {
        cost += LearningConfig.driveWrongWayM;
      }
      out.add((
        edge: e,
        forward: forward,
        cost: cost,
        along: forward ? n.along : 1 - n.along,
      ));
    }
  }
  return out;
}

/// Where one may legally drive from the end of [s] within [boundM]: per junction, the edges
/// arrived on and the metres from that end.
Map<int, List<(RoadEdge, double)>> _reach(
  RoadGraph graph,
  EdgeSnap s,
  double boundM,
) {
  final out = <int, List<(RoadEdge, double)>>{};
  final best = <(int, int), double>{};
  final open = [(0.0, _end(s), s.edge)];
  while (open.isNotEmpty) {
    open.sort((a, b) => b.$1.compareTo(a.$1));
    final (d, j, arrived) = open.removeLast();
    if ((best[(j, arrived.id)] ?? double.infinity) <= d) continue;
    best[(j, arrived.id)] = d;
    (out[j] ??= []).add((arrived, d));
    for (final e in graph.legalExits(j, approach: arrived)) {
      if (e.id == arrived.id) continue;
      final next = d + e.lengthM;
      if (next <= boundM) open.add((next, e.other(j), e));
    }
  }
  return out;
}

/// What moving from [a] at one fix to [b] at the next costs ([straightM] apart): how far the
/// network distance between them is from the straight one, plus [LearningConfig.driveTurnBackM]
/// for turning back and [LearningConfig.driveWrongWayM] for an illegal turn; null when [b] isn't
/// near [a] on the network.
double? _transition(
  RoadGraph graph,
  EdgeSnap a,
  EdgeSnap b,
  double straightM,
  Map<int, List<(RoadEdge, double)>> reach,
) {
  final la = a.edge.lengthM, lb = b.edge.lengthM;
  if (a.edge.id == b.edge.id && a.forward == b.forward) {
    final d = (b.along - a.along) * la;
    return d < -LearningConfig.driveSampleM / 2 ? null : (d - straightM).abs();
  }
  if (a.edge.id == b.edge.id) {
    final apart = ((1 - b.along) - a.along).abs() * la;
    return (apart - straightM).abs() + LearningConfig.driveTurnBackM;
  }
  final left = (1 - a.along) * la, into = b.along * lb;
  final arrivals = reach[_start(b)] ?? const [];
  double? network;
  for (final (arrived, d) in arrivals) {
    if (graph
            .legalExits(_start(b), approach: arrived)
            .any((e) => e.id == b.edge.id) &&
        d < (network ?? double.infinity)) {
      network = d;
    }
  }
  if (network != null) return (left + network + into - straightM).abs();
  if (_start(b) == _end(a)) {
    return (left + into - straightM).abs() + LearningConfig.driveWrongWayM;
  }
  return null;
}

/// Matches a drive's [fixes] to [graph] (SPEC §5.3 "Drives"): fixes at least
/// [LearningConfig.driveSampleM] apart (and the last) snap to the edges near them, each way; a Viterbi pass
/// picks the snaps whose distance, heading and one-ways cost least together with how well the
/// network distance between consecutive snaps fits the straight one; the edges are then joined
/// by the shortest legal drives between them. The first and last edge count when the car drove
/// most of them. U-turns are reversals on an edge or at a junction; hesitations are crawls below
/// [LearningConfig.hesitationKmh] for over [LearningConfig.hesitationS], more than
/// [LearningConfig.hesitationJunctionM] from a junction (the pack has no traffic signals), the
/// start and the end aside.
DriveMatch matchDrive(RoadGraph graph, List<DriveFix> fixes) {
  final kept = <DriveFix>[];
  for (final f in fixes) {
    if (kept.isEmpty ||
        distanceBetween(kept.last.at, f.at) >= LearningConfig.driveSampleM) {
      kept.add(f);
    }
  }
  if (fixes.isNotEmpty && kept.last != fixes.last) kept.add(fixes.last);
  var drivenM = 0.0;
  for (var i = 1; i < kept.length; i++) {
    drivenM += distanceBetween(kept[i - 1].at, kept[i].at);
  }

  final layers = <List<EdgeSnap>>[];
  final at = <LatLng>[];
  for (final (i, f) in kept.indexed) {
    final heading = kept.length < 2
        ? f.headingDeg
        : i == 0
        ? bearingDegrees(f.at, kept[1].at)
        : bearingDegrees(kept[i - 1].at, f.at);
    final snaps = edgeSnaps(graph, f.at, heading);
    if (snaps.isEmpty) continue;
    layers.add(snaps);
    at.add(f.at);
  }
  final chosen = _viterbi(graph, layers, at);

  final runs = <({EdgeSnap first, EdgeSnap last, LatLng lastAt})>[];
  for (final (i, s) in chosen.indexed) {
    if (runs.lastOrNull case final r?
        when r.last.edge.id == s.edge.id && r.last.forward == s.forward) {
      runs.last = (first: r.first, last: s, lastAt: at[i]);
    } else {
      runs.add((first: s, last: s, lastAt: at[i]));
    }
  }

  final junctions = <int>[];
  final edges = <RoadEdge>[];
  var turnedBack = <int, LatLng>{};
  void drive(RoadEdge e, int from) {
    if (junctions.isEmpty) junctions.add(from);
    edges.add(e);
    junctions.add(e.other(from));
  }

  for (final (i, r) in runs.indexed) {
    final start = _start(r.first);
    if (edges.isNotEmpty) {
      final previous = runs[i - 1];
      if (previous.last.edge.id == r.first.edge.id) {
        turnedBack[edges.length - 1] = previous.lastAt;
      }
      final end = junctions.last;
      if (end != start) {
        final gap = graph.shortestRoute(end, {start}, approach: edges.last);
        if (gap == null) continue;
        for (final (k, e) in gap.edges.indexed) {
          drive(e, gap.junctions[k]);
        }
      }
    }
    drive(r.first.edge, start);
  }
  if (edges.length > 1 && runs.first.first.along > 0.5) {
    edges.removeAt(0);
    junctions.removeAt(0);
    turnedBack = {
      for (final MapEntry(:key, :value) in turnedBack.entries)
        if (key > 0) key - 1: value,
    };
  }
  if (edges.length > 1 &&
      runs.last.last.edge.id == edges.last.id &&
      runs.last.last.along < 0.5) {
    edges.removeLast();
    junctions.removeLast();
  }

  return DriveMatch(
    path: Route(junctions, edges, edges.fold(0, (sum, e) => sum + e.lengthM)),
    uTurns: [
      for (var i = 0; i + 1 < edges.length; i++)
        if (edges[i].id == edges[i + 1].id)
          turnedBack[i] ?? graph.at(junctions[i + 1]),
    ],
    hesitations: _hesitations(graph, fixes),
    drivenM: drivenM,
  );
}

/// [match] graded like a recital (SPEC §5.3 drives): from its first junction to where it ended
/// when that is within [LearningConfig.driveArriveM] of [target], else to [target], [stoppedM]
/// short. Nothing is graded when no fix lay near a road.
({RecitalResult? graded, double? stoppedM}) gradeDrive(
  RoadGraph graph,
  DriveMatch match,
  int target, {
  Map<String, NamedStreet> streets = const {},
}) {
  final path = match.path;
  if (path.edges.isEmpty) return (graded: null, stoppedM: null);
  final stoppedM = distanceBetween(
    graph.at(path.junctions.last),
    graph.at(target),
  );
  final arrived = stoppedM <= LearningConfig.driveArriveM;
  return (
    graded: RecitalGrader.score(
      graph,
      path,
      from: path.junctions.first,
      to: arrived ? path.junctions.last : target,
      streets: streets,
    ),
    stoppedM: arrived ? null : stoppedM,
  );
}

/// The cheapest snap per fix: emission (the snap's own cost) plus transitions, with a fix the
/// network can't link to the previous one bridged at the straight distance plus twice
/// [LearningConfig.driveSnapM] (a GPS jump; the gap is filled with a shortest drive later).
List<EdgeSnap> _viterbi(
  RoadGraph graph,
  List<List<EdgeSnap>> layers,
  List<LatLng> at,
) {
  if (layers.isEmpty) return const [];
  var cost = [for (final s in layers.first) s.cost];
  final back = <List<int>>[];
  for (var i = 1; i < layers.length; i++) {
    final straight = distanceBetween(at[i - 1], at[i]);
    final bound = 2 * straight + 2 * LearningConfig.driveSnapM;
    final previous = layers[i - 1];
    final reach = [for (final a in previous) _reach(graph, a, bound)];
    final jumpFrom = _argMin(cost);
    final jump = cost[jumpFrom] + straight + 2 * LearningConfig.driveSnapM;
    final next = <double>[];
    final from = <int>[];
    for (final b in layers[i]) {
      var best = jump;
      var arg = jumpFrom;
      for (final (k, a) in previous.indexed) {
        final t = _transition(graph, a, b, straight, reach[k]);
        if (t != null && cost[k] + t < best) {
          best = cost[k] + t;
          arg = k;
        }
      }
      next.add(best + b.cost);
      from.add(arg);
    }
    back.add(from);
    cost = next;
  }
  var k = _argMin(cost);
  final picked = [layers.last[k]];
  for (var i = layers.length - 1; i > 0; i--) {
    k = back[i - 1][k];
    picked.add(layers[i - 1][k]);
  }
  return picked.reversed.toList();
}

List<LatLng> _hesitations(RoadGraph graph, List<DriveFix> fixes) {
  const slowMps = LearningConfig.hesitationKmh / 3.6;
  double? speed(int i) =>
      fixes[i].speedMps ??
      (i == 0
          ? null
          : distanceBetween(fixes[i - 1].at, fixes[i].at) /
                max(1, fixes[i].t.difference(fixes[i - 1].t).inMilliseconds) *
                1000);
  bool slow(int i) => (speed(i) ?? double.infinity) < slowMps;
  final out = <LatLng>[];
  var i = 0;
  while (i < fixes.length) {
    if (!slow(i)) {
      i++;
      continue;
    }
    var j = i;
    while (j + 1 < fixes.length && slow(j + 1)) {
      j++;
    }
    final crawl = fixes[j].t.difference(fixes[i].t).inSeconds;
    final where = fixes[(i + j) ~/ 2].at;
    if (i > 0 &&
        j < fixes.length - 1 &&
        crawl > LearningConfig.hesitationS &&
        graph.junctions.values.every(
          (p) => distanceBetween(p, where) > LearningConfig.hesitationJunctionM,
        )) {
      out.add(where);
    }
    i = j + 1;
  }
  return out;
}

/// The index of [values]' least, the first on a tie.
int _argMin(List<double> values) {
  var arg = 0;
  for (var i = 1; i < values.length; i++) {
    if (values[i] < values[arg]) arg = i;
  }
  return arg;
}
