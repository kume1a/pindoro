import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'constants.dart';
import 'fsrs.dart';
import 'recital_transcript.dart';
import 'route_questions.dart';
import 'routes.dart';

/// Why a move breaks the rules of the road.
enum IllegalReason { oneway, restriction }

/// The first move of a path the rules forbid: driving [edge] away from [junction].
typedef IllegalMove = ({
  int junction,
  RoadEdge edge,
  IllegalReason reason,

  /// The way in to a restricted turn; null for a one-way.
  RoadEdge? approach,
});

/// A place on the path with another legal way on (SPEC §5.3 step 6): arriving on [approach] (null
/// at the start), leaving on [exit]. [correct] when legal and still on a legal path to B within
/// [LearningConfig.stretchGreat] from there; [newStreet] when [exit] turns onto another named
/// street ("Left onto X").
typedef RecitalDecision = ({
  int junction,
  RoadEdge? approach,
  RoadEdge exit,
  Turn? turn,
  bool correct,
  bool newStreet,
});

/// A graded recital, drawn route or drive (SPEC §5.3).
final class RecitalResult {
  const RecitalResult({
    required this.best,
    required this.path,
    required this.stretch,
    required this.tier,
    required this.rating,
    required this.decisions,
    required this.illegal,
    required this.score,
    required this.divergence,
    required this.extraM,
  });

  /// The shortest legal drive from A to B; null when there is none.
  final Route? best;

  /// The player's path; null when the named streets don't meet or need more than
  /// [LearningConfig.connectorMax] connectors.
  final Route? path;

  /// Path length over [best]'s; null without a path that arrives at B.
  final double? stretch;
  final Tier tier;
  final Rating rating;
  final List<RecitalDecision> decisions;

  /// The first forbidden move ("Not drivable").
  final IllegalMove? illegal;

  /// Partial credit: the share of [decisions] right, plus the landmark bonus, at most 1.
  final double score;

  /// The junction where the path leaves [best]; null when it never does.
  final int? divergence;

  /// How much longer the path is than [best], in metres.
  final double? extraM;

  bool get drivable => path != null && illegal == null;
}

/// The streets a recital names in order, with the turn word and landmarks said on the way in.
typedef _Leg = ({
  Set<String> parts,
  Set<int> junctions,
  Turn? turn,
  List<RouteLandmark> landmarks,
});

/// A partial path of the search: where it is, the edge it came in on and the connectors used.
final class _Walk {
  const _Walk(this.junctions, this.edges, this.connectors, this.cost);

  final List<int> junctions;
  final List<RoadEdge> edges;
  final int connectors;
  final double cost;

  int get junction => junctions.last;
  RoadEdge? get edge => edges.lastOrNull;

  _Walk then(Route r, int connectors, double cost) => _Walk(
    [...junctions, ...r.junctions.skip(1)],
    [...edges, ...r.edges],
    connectors,
    cost,
  );

  Route get route =>
      Route(junctions, edges, edges.fold(0, (sum, e) => sum + e.lengthM));
}

bool _isConnector(RoadEdge e) => e.streetId == null;

/// SPEC §5.3 step 6: leaving on [exit] (after [approach]) keeps a good path when it, plus the
/// shortest legal drive [after] it, is at most [LearningConfig.stretchGreat] times the shortest
/// drive [here] (both to B; null: none).
bool keepsGoodPath(
  RoadEdge exit, {
  required RoadEdge? approach,
  required double? here,
  required double? after,
}) =>
    here != null &&
    after != null &&
    exit.lengthM +
            (exit.id == approach?.id ? LearningConfig.uTurnPenaltyM : 0) +
            after <=
        LearningConfig.stretchGreat * here + 1e-6;

/// The cheapest legal drive left from [junction] to B having arrived on an edge, memoised.
final class _Remaining {
  _Remaining(this.graph, this.to);

  final RoadGraph graph;
  final int to;
  final Map<(int, int?), double?> _costs = {};

  double? from(int junction, RoadEdge? approach) => _costs.putIfAbsent((
    junction,
    approach?.id,
  ), () => graph.shortestRoute(junction, {to}, approach: approach)?.costM);
}

/// Grading of recitals (SPEC §5.3), drawn routes and drives.
abstract final class RecitalGrader {
  /// Grades recited [steps] from junction [from] (A) to [to] (B): the cheapest legal path along
  /// the named streets in order (Viterbi over where each street meets the next, on the
  /// edge-expanded directed graph, with up to [LearningConfig.connectorMax] silent connectors of
  /// at most [LearningConfig.connectorMaxM]; turn words and landmarks said steer it softly), then
  /// [score]d. A first or last street left unsaid is A's or B's. With no legal path but one
  /// ignoring one-ways and turn restrictions, that one is graded "Not drivable"; with neither
  /// the recital is a Miss with no path. [streets] are by part id.
  static RecitalResult grade(
    RoadGraph graph,
    List<RecitalStep> steps, {
    required int from,
    required int to,
    Map<String, NamedStreet> streets = const {},
    bool hinted = false,
  }) {
    final legs = _legs(graph, steps, from, to, streets);
    final path =
        _walk(graph, legs, from, to) ??
        _walkIgnoringRules(graph, legs, from, to);
    if (path == null) {
      return _invalid(graph.shortestRoute(from, {to}));
    }
    final said = [for (final s in steps) ?s.landmark];
    return _score(
      graph,
      path,
      from: from,
      to: to,
      hinted: hinted,
      streets: streets,
      landmarksNamed: (decisions) => _namedAt(graph, said, decisions),
    );
  }

  /// Grades a concrete [path] (a drawn route, a matched drive) from [from] to [to] (SPEC §5.3
  /// steps 4–6): its first forbidden move, the stretch over the shortest legal drive, the tier
  /// and rating (≤ [LearningConfig.stretchPerfect] Perfect / Easy unless [hinted], which caps at
  /// Great / Good, ≤ [LearningConfig.stretchGreat] Great / Good, ≤ [LearningConfig.stretchClose]
  /// Close / Hard, else, illegal or not arriving at [to], Miss / Again), each decision and the
  /// score with [landmarksNamed] at reorientation points.
  static RecitalResult score(
    RoadGraph graph,
    Route path, {
    required int from,
    required int to,
    bool hinted = false,
    int landmarksNamed = 0,
    Map<String, NamedStreet> streets = const {},
  }) => _score(
    graph,
    path,
    from: from,
    to: to,
    hinted: hinted,
    streets: streets,
    landmarksNamed: (_) => landmarksNamed,
  );

  /// A recital not known (SPEC §16.24 item 136): Miss / Again with the best route to show,
  /// and no decisions, so no J card hears of it.
  static RecitalResult notKnown(
    RoadGraph graph, {
    required int from,
    required int to,
  }) => _invalid(graph.shortestRoute(from, {to}));

  static RecitalResult _invalid(Route? best) => RecitalResult(
    best: best,
    path: null,
    stretch: null,
    tier: Tier.miss,
    rating: Rating.again,
    decisions: const [],
    illegal: null,
    score: 0,
    divergence: null,
    extraM: null,
  );

  static RecitalResult _score(
    RoadGraph graph,
    Route path, {
    required int from,
    required int to,
    required bool hinted,
    required Map<String, NamedStreet> streets,
    required int Function(List<RecitalDecision> decisions) landmarksNamed,
  }) {
    final best = graph.shortestRoute(from, {to});
    final illegal = _illegalMove(graph, path);
    final decisions = _decisions(graph, path, to, streets);
    final arrived =
        path.junctions.isNotEmpty &&
        path.junctions.first == from &&
        path.junctions.last == to;
    final stretch = !arrived || best == null
        ? null
        : best.costM == 0
        ? (path.lengthM == 0 ? 1.0 : double.infinity)
        : _withUTurns(path) / best.costM;
    final (tier, rating) = _tierOf(illegal == null ? stretch : null, hinted);
    final right = decisions.where((d) => d.correct).length;
    final base = decisions.isEmpty
        ? (tier == Tier.miss ? 0.0 : 1.0)
        : right / decisions.length;
    final bonus = min(
      LearningConfig.recitalLandmarkBonusCap,
      LearningConfig.recitalLandmarkBonus * landmarksNamed(decisions),
    );
    var same = 0;
    if (best != null) {
      while (same < path.edges.length &&
          same < best.edges.length &&
          path.edges[same].id == best.edges[same].id) {
        same++;
      }
    }
    final onBest =
        best != null && same == path.edges.length && same == best.edges.length;
    return RecitalResult(
      best: best,
      path: path,
      stretch: stretch,
      tier: tier,
      rating: rating,
      decisions: decisions,
      illegal: illegal,
      score: min(1, base + bonus),
      divergence: best == null || onBest || path.junctions.isEmpty
          ? null
          : path.junctions[same],
      extraM: best == null ? null : path.lengthM - best.lengthM,
    );
  }

  static (Tier, Rating) _tierOf(double? stretch, bool hinted) {
    if (stretch == null || stretch > LearningConfig.stretchClose) {
      return (Tier.miss, Rating.again);
    }
    if (stretch > LearningConfig.stretchGreat) return (Tier.close, Rating.hard);
    if (stretch > LearningConfig.stretchPerfect || hinted) {
      return (Tier.great, Rating.good);
    }
    return (Tier.perfect, Rating.easy);
  }

  /// [path]'s length with each U-turn weighed as routing weighs it, so the stretch compares it
  /// with the best route's cost: a way round by a U-turn is never shorter than the best.
  static double _withUTurns(Route path) =>
      path.lengthM +
      LearningConfig.uTurnPenaltyM *
          [
            for (var i = 0; i + 1 < path.edges.length; i++)
              if (path.edges[i].id == path.edges[i + 1].id) i,
          ].length;

  static IllegalMove? _illegalMove(RoadGraph graph, Route path) {
    for (final (i, e) in path.edges.indexed) {
      final j = path.junctions[i];
      if (!graph.canDrive(e, j)) {
        return (
          junction: j,
          edge: e,
          reason: IllegalReason.oneway,
          approach: null,
        );
      }
      if (i > 0 &&
          !graph
              .legalExits(j, approach: path.edges[i - 1])
              .any((x) => x.id == e.id)) {
        return (
          junction: j,
          edge: e,
          reason: IllegalReason.restriction,
          approach: path.edges[i - 1],
        );
      }
    }
    return null;
  }

  static List<RecitalDecision> _decisions(
    RoadGraph graph,
    Route path,
    int to,
    Map<String, NamedStreet> streets,
  ) {
    final remaining = _Remaining(graph, to);
    final decisions = <RecitalDecision>[];
    String? street;
    for (final (i, exit) in path.edges.indexed) {
      final j = path.junctions[i];
      final approach = i == 0 ? null : path.edges[i - 1];
      final named = switch (exit.streetId) {
        final part? => streets[part]?.id ?? part,
        null => null,
      };
      final newStreet = street != null && named != null && named != street;
      if (named != null) street = named;
      final legal = graph.legalExits(j, approach: approach);
      final choice = legal.any((e) => e.id != approach?.id && e.id != exit.id);
      if (!choice) continue;
      decisions.add((
        junction: j,
        approach: approach,
        exit: exit,
        turn: approach == null ? null : turnAt(approach, exit, j),
        correct:
            legal.any((e) => e.id == exit.id) &&
            keepsGoodPath(
              exit,
              approach: approach,
              here: remaining.from(j, approach),
              after: remaining.from(exit.other(j), exit),
            ),
        newStreet: newStreet,
      ));
    }
    return decisions;
  }

  /// How many of the landmarks [said] stand at one of [decisions]' junctions.
  static int _namedAt(
    RoadGraph graph,
    List<RouteLandmark> said,
    List<RecitalDecision> decisions,
  ) {
    final at = {for (final d in decisions) d.junction};
    return {
      for (final l in said)
        if (l.junction case final j? when at.contains(j))
          l.id
        else if (at.any(
          (j) =>
              distanceBetween(graph.at(j), l.at) <=
              LearningConfig.landmarkRadiusM,
        ))
          l.id,
    }.length;
  }

  /// The streets [steps] name, in order and without repeats, each with the turn word and the
  /// landmarks said before it; A's streets first and B's last when the recital leaves them out.
  static List<_Leg> _legs(
    RoadGraph graph,
    List<RecitalStep> steps,
    int from,
    int to,
    Map<String, NamedStreet> streets,
  ) {
    _Leg leg(Set<String> parts, Turn? turn, List<RouteLandmark> landmarks) => (
      parts: parts,
      junctions: {for (final p in parts) ...graph.junctionsOfPart(p)},
      turn: turn,
      landmarks: landmarks,
    );
    _Leg at(int junction) => leg(
      {
        for (final e in graph.edgesAt(junction))
          if (e.streetId case final part?)
            ...streets[part]?.parts.map((p) => p.id) ?? [part],
      },
      null,
      const [],
    );

    final legs = <_Leg>[];
    var landmarks = <RouteLandmark>[];
    Turn? landmarkTurn;
    String? last;
    for (final step in steps) {
      if (step.landmark case final l?) {
        landmarks.add(l);
        landmarkTurn ??= step.turn;
        continue;
      }
      final street = step.street;
      if (street == null || street.id == last) continue;
      last = street.id;
      legs.add(
        leg(
          {for (final p in street.parts) p.id},
          step.turn ?? landmarkTurn,
          landmarks,
        ),
      );
      landmarks = [];
      landmarkTurn = null;
    }
    if (legs.isEmpty || !legs.first.junctions.contains(from)) {
      legs.insert(0, at(from));
    }
    if (!legs.last.junctions.contains(to)) legs.add(at(to));
    return legs;
  }

  /// The cheapest walk from [from] to [to] along [legs] in order on [graph] (Viterbi over the
  /// junctions where each leg meets the next); null when none.
  static Route? _walk(RoadGraph graph, List<_Leg> legs, int from, int to) {
    var states = <(int, int?, int), _Walk>{
      (from, null, 0): _Walk([from], const [], 0, 0),
    };
    for (final (k, leg) in legs.indexed) {
      final goals = k == legs.length - 1
          ? {to}
          : _meeting(graph, legs[k + 1].junctions, leg.junctions);
      final touching = {...leg.junctions, ...goals};
      bool allow(RoadEdge e) => _isConnector(e)
          ? e.lengthM <= LearningConfig.connectorMaxM &&
                (touching.contains(e.from) || touching.contains(e.to))
          : leg.parts.contains(e.streetId);
      final next = <(int, int?, int), _Walk>{};
      for (final s in states.values) {
        for (final goal in goals) {
          final r = s.junction == goal
              ? Route([goal], const [], 0)
              : graph.shortestRoute(
                  s.junction,
                  {goal},
                  allow: allow,
                  approach: s.edge,
                );
          if (r == null) continue;
          final connectors = r.edges.where(_isConnector);
          final used = s.connectors + connectors.length;
          if (used > LearningConfig.connectorMax) continue;
          final cost =
              s.cost +
              r.costM +
              connectors.fold(0.0, (sum, e) => sum + e.lengthM) +
              _turnCost(leg.turn, s, r) +
              _landmarkCost(graph, leg.landmarks, s.junction);
          final key = (goal, r.edges.lastOrNull?.id ?? s.edge?.id, used);
          if (cost < (next[key]?.cost ?? double.infinity)) {
            next[key] = s.then(r, used, cost);
          }
        }
      }
      if (next.isEmpty) return null;
      states = next;
    }
    return states.values
        .where((w) => w.junction == to)
        .fold<_Walk?>(null, (a, b) => a == null || b.cost < a.cost ? b : a)
        ?.route;
  }

  /// [_walk] on a copy of the legs' roads with every edge two-way and no turn restrictions, its
  /// path on [graph]'s own edges.
  static Route? _walkIgnoringRules(
    RoadGraph graph,
    List<_Leg> legs,
    int from,
    int to,
  ) {
    final parts = {for (final l in legs) ...l.parts};
    final junctions = {for (final l in legs) ...l.junctions, from, to};
    final kept = {
      for (final e in graph.edges)
        if (_isConnector(e)
            ? e.lengthM <= LearningConfig.connectorMaxM &&
                  (junctions.contains(e.from) || junctions.contains(e.to))
            : parts.contains(e.streetId))
          e.id: e,
    };
    final free = RoadGraph(graph.junctions, [
      for (final e in kept.values)
        RoadEdge(
          id: e.id,
          from: e.from,
          to: e.to,
          streetId: e.streetId,
          lengthM: e.lengthM,
          line: e.line,
        ),
    ]);
    final path = _walk(free, legs, from, to);
    if (path == null) return null;
    return Route(path.junctions, [
      for (final e in path.edges) kept[e.id]!,
    ], path.lengthM);
  }

  /// The junctions of the next street at or near ([LearningConfig.connectorMax] connectors of
  /// [LearningConfig.connectorMaxM]) this one's.
  static Set<int> _meeting(RoadGraph graph, Set<int> next, Set<int> here) => {
    for (final n in next)
      if (here.contains(n) ||
          here.any(
            (j) =>
                distanceBetween(graph.at(n), graph.at(j)) <=
                LearningConfig.connectorMax * LearningConfig.connectorMaxM,
          ))
        n,
  };

  static double _turnCost(Turn? said, _Walk s, Route r) {
    final approach = s.edge;
    if (said == null || approach == null || r.edges.isEmpty) return 0;
    final made = turnAt(approach, r.edges.first, s.junction);
    return made == said ? 0 : LearningConfig.recitalTurnMismatchM;
  }

  static double _landmarkCost(
    RoadGraph graph,
    List<RouteLandmark> landmarks,
    int junction,
  ) => landmarks.fold(
    0,
    (sum, l) =>
        sum +
        max(
          0,
          distanceBetween(graph.at(junction), l.at) -
              LearningConfig.landmarkRadiusM,
        ),
  );
}
