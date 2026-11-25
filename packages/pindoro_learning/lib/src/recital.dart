import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'cards.dart';
import 'constants.dart';
import 'fsrs.dart';
import 'grader.dart';
import 'names.dart';
import 'route_questions.dart';
import 'routes.dart';

/// A piece of a recited route (SPEC §5.3 step 1): a turn word, or words that name a street or a
/// landmark.
sealed class RecitalToken {
  const RecitalToken();
}

final class TurnToken extends RecitalToken {
  const TurnToken(this.turn);

  final Turn turn;

  @override
  bool operator ==(Object other) => other is TurnToken && other.turn == turn;

  @override
  int get hashCode => turn.hashCode;

  @override
  String toString() => 'TurnToken($turn)';
}

final class NameToken extends RecitalToken {
  const NameToken(this.text);

  final String text;

  @override
  bool operator ==(Object other) => other is NameToken && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'NameToken($text)';
}

/// One step of a recital: the turn said (if any), then the street or the landmark it names.
typedef RecitalStep = ({
  Turn? turn,
  NamedStreet? street,
  RouteLandmark? landmark,
});

const Map<String, Turn> _turnWords = {
  'left': Turn.left,
  'right': Turn.right,
  'straight': Turn.straight,
  'u-turn': Turn.uTurn,
  'uturn': Turn.uTurn,
  'მარცხნივ': Turn.left,
  'მარჯვნივ': Turn.right,
  'პირდაპირ': Turn.straight,
  'მობრუნება': Turn.uTurn,
  'უკან': Turn.uTurn,
  'martskhniv': Turn.left,
  'marcxniv': Turn.left,
  'marjvniv': Turn.right,
  'pirdapir': Turn.straight,
  'mobruneba': Turn.uTurn,
  'ukan': Turn.uTurn,
};

const Map<String, Turn> _turnPairs = {
  'u turn': Turn.uTurn,
  'turn around': Turn.uTurn,
};

/// Words around the names that say nothing about the route. "And" (და) stays in a run: names
/// hold it ("ზაზა და საულ კახიანების ქუჩა"), and a run's words that name nothing are skipped.
const Set<String> _fillers = {
  'onto', 'on', 'into', 'to', 'then', 'turn', 'take', 'the', 'go', //
  'at', 'keep', 'drive', 'continue', 'along', 'until', 'till', 'past', //
  'after', 'a', 'down', 'up', 'from', 'via', 'by', //
  'მერე', 'შემდეგ', 'ვუხვევ', 'შევუხვევ', 'გავყვები', 'ვაგრძელებ', //
  'mere', 'shemdeg', 'vukhvev', 'shevukhvev', 'gavyvebi', 'vagrdzeleb',
};

/// Georgian case endings a spoken name can carry ("abashidzeze": onto Abashidze).
const List<String> _caseEndings = [
  'ზედ', 'ზე', 'დან', 'მდე', 'ით', 'ში', 'თან', 'კენ', //
  'zed', 'ze', 'dan', 'mde', 'it', 'shi', 'tan', 'ken',
];

String _bare(String word) => word.replaceAll(RegExp('[«»„“”"\'`()]'), '');

/// Splits a transcript into turn words and runs of name words (SPEC §5.3 step 1): punctuation,
/// turn words and filler words end a run.
List<RecitalToken> tokenizeRecital(String transcript) {
  final tokens = <RecitalToken>[];
  final name = <String>[];
  void flush() {
    if (name.isEmpty) return;
    tokens.add(NameToken(name.join(' ')));
    name.clear();
  }

  for (final clause in transcript.toLowerCase().split(RegExp(r'[,;.!?…\n]+'))) {
    final words = [
      for (final w in clause.split(RegExp(r'\s+')))
        if (_bare(w) case final b when b.isNotEmpty) b,
    ];
    for (var i = 0; i < words.length; i++) {
      final pair = i + 1 < words.length
          ? _turnPairs['${words[i]} ${words[i + 1]}']
          : null;
      final turn = pair ?? _turnWords[words[i]];
      if (turn != null) {
        flush();
        tokens.add(TurnToken(turn));
        if (pair != null) i++;
      } else if (_fillers.contains(words[i])) {
        flush();
      } else {
        name.add(words[i]);
      }
    }
    flush();
  }
  return tokens;
}

/// A street or a landmark a phrase can name, with the forms it's recognised by.
typedef _Entry = ({
  Set<String> forms,
  NamedStreet? street,
  RouteLandmark? landmark,
});

/// The ways [phrase] may be meant: as said, without a case ending, in Latin letters.
Set<String> _variants(String phrase) {
  final base = nameBase(phrase);
  final out = {base};
  for (final ending in _caseEndings) {
    if (base.endsWith(ending) && base.length - ending.length >= 3) {
      out.add(base.substring(0, base.length - ending.length));
    }
  }
  return {
    for (final v in out) ...{v, transliterate(v)},
  }..remove('');
}

double _phraseDistance(Set<String> variants, Set<String> forms) {
  var best = 1.0;
  for (final v in variants) {
    for (final f in forms) {
      // Levenshtein is at least the length difference, so this skips far forms cheaply.
      if ((v.length - f.length).abs() >
          LearningConfig.fuzzyNameMax * max(v.length, f.length)) {
        continue;
      }
      best = min(best, nameDistance(v, f));
    }
  }
  return best;
}

/// How far [entry] lies from [previous]: the nearest of its points to that street's line.
double _apart(_Entry entry, NamedStreet previous) {
  double to(LatLng p) =>
      pointToPolylineDistance(p, previous.geometry).distanceMeters;
  return switch (entry) {
    (street: final s?, landmark: _, forms: _) =>
      s.geometry.expand((line) => line).map(to).reduce(min),
    (landmark: final l?, street: _, forms: _) => to(l.at),
    _ => double.infinity,
  };
}

/// [e]'s names in full, kind words kept.
Set<String> _fullNames(_Entry e) => {
  if (e.street case final s?) ...[
    normaliseName(s.name),
    if (s.nameEn case final en?) normaliseName(en),
  ],
  if (e.landmark case final l?) normaliseName(l.name),
};

/// Resolves [tokens] into steps (SPEC §5.3 step 2): each run of name words is split greedily into
/// the longest phrases naming a street or a landmark within [LearningConfig.fuzzyNameMax] (in
/// Georgian, English or Latin letters, with or without a case ending); among near-equal matches
/// the one nearest the previous street wins ([from] before the first). A turn word goes with the
/// next name; words that name nothing are skipped.
List<RecitalStep> resolveRecital(
  List<RecitalToken> tokens, {
  required Iterable<NamedStreet> streets,
  Iterable<RouteLandmark> landmarks = const [],
  NamedStreet? from,
}) {
  final entries = <_Entry>[
    for (final s in streets) (forms: nameForms(s), street: s, landmark: null),
    for (final l in landmarks)
      (forms: placeForms(l.name, l.nameEn), street: null, landmark: l),
  ];
  final steps = <RecitalStep>[];
  var previous = from;
  Turn? turn;
  _Entry? match(String phrase) {
    final variants = _variants(phrase);
    final found = [
      for (final e in entries)
        if (_phraseDistance(variants, e.forms) case final d
            when d <= LearningConfig.fuzzyNameMax)
          (entry: e, d: d),
    ];
    if (found.isEmpty) return null;
    final best = found.map((f) => f.d).reduce(min);
    final ties = [
      for (final f in found)
        if (f.d <= best + LearningConfig.recitalNameTieSlack) f.entry,
    ];
    // Kind words don't count in a match, so a lane and its street tie: the
    // full name said settles it.
    final whole = normaliseName(phrase);
    final exact = ties.where((e) => _fullNames(e).contains(whole)).toList();
    final near = previous;
    if (exact.length == 1 || (exact.isNotEmpty && near == null)) {
      return exact.first;
    }
    if (ties.length == 1 || near == null) {
      return found.firstWhere((f) => f.d == best).entry;
    }
    return (exact.isEmpty ? ties : exact)
        .map((e) => (entry: e, m: _apart(e, near)))
        .reduce((a, b) => b.m < a.m ? b : a)
        .entry;
  }

  for (final token in tokens) {
    switch (token) {
      case TurnToken(turn: final said):
        turn = said;
      case NameToken(:final text):
        final words = text.split(' ');
        var i = 0;
        while (i < words.length) {
          var taken = 0;
          for (
            var n = min(LearningConfig.recitalNameWordsMax, words.length - i);
            n > 0;
            n--
          ) {
            final entry = match(words.sublist(i, i + n).join(' '));
            if (entry == null) continue;
            steps.add((
              turn: turn,
              street: entry.street,
              landmark: entry.landmark,
            ));
            turn = null;
            if (entry.street case final s?) previous = s;
            taken = n;
            break;
          }
          i += max(taken, 1);
        }
    }
  }
  return steps;
}

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
            (exit.id == approach?.id ? RoutingConfig.uTurnPenaltyM : 0) +
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
      RoutingConfig.uTurnPenaltyM *
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
        turn: approach == null
            ? null
            : turnOf(arrivingBearing(approach, j), leavingBearing(exit, j)),
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
    final made = turnOf(
      arrivingBearing(approach, s.junction),
      leavingBearing(r.edges.first, s.junction),
    );
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

/// What a recital or drive says about the junction cards (SPEC §4 implicit evidence, §5.3 step
/// 7): a right decision is evidence for the J item it drove ([ok]); a wrong one against every J
/// item at that junction from that approach. Only items in [routeItems]; an item met twice keeps
/// its worst outcome. G and B ids name no approach, so they get none.
List<({String itemId, bool ok})> recitalEvidence(
  RecitalResult result,
  Map<int, int> junctionNodes,
  Set<String> routeItems,
) {
  final outcome = <String, bool>{};
  void note(String id, bool ok) => outcome[id] = (outcome[id] ?? true) && ok;
  for (final d in result.decisions) {
    final approach = d.approach;
    if (approach == null) continue;
    final node = junctionNodes[d.junction];
    final from = junctionNodes[approach.other(d.junction)];
    if (node == null || from == null) continue;
    if (d.correct) {
      final exit = junctionNodes[d.exit.other(d.junction)];
      if (exit == null) continue;
      final id = RouteIds.junction(node, from, exit);
      if (routeItems.contains(id)) note(id, true);
    } else {
      final prefix = CardType.j.item('n$node:n$from:');
      for (final id in routeItems) {
        if (id.startsWith(prefix)) note(id, false);
      }
    }
  }
  return [
    for (final MapEntry(:key, :value) in outcome.entries)
      (itemId: key, ok: value),
  ];
}

/// The player's report that [move] on [path] is legal after all ("Wrong? Report this turn",
/// SPEC §15), by OSM nodes: `oneway:n<from>:n<to>` or `turn:n<from>:n<via>:n<to>`.
String moveReport(IllegalMove move, Map<int, int> junctionNodes) {
  String n(int junction) => 'n${junctionNodes[junction]}';
  final to = n(move.edge.other(move.junction));
  return switch (move.approach) {
    final approach? =>
      'turn:${n(approach.other(move.junction))}:${n(move.junction)}:$to',
    null => 'oneway:${n(move.junction)}:$to',
  };
}

/// [graph] with the moves in [reports] ([moveReport]s) let through; a report naming junctions
/// the pack no longer has is skipped.
RoadGraph allowingReports(
  RoadGraph graph,
  Set<String> reports,
  Map<int, int> junctionNodes,
) {
  if (reports.isEmpty) return graph;
  final byNode = {for (final e in junctionNodes.entries) e.value: e.key};
  Iterable<RoadEdge> between(int? a, int? b) => a == null || b == null
      ? const []
      : graph.edgesAt(a).where((e) => e.other(a) == b);
  final twoWay = <int>{};
  final allowed = <(int, int, int)>{};
  for (final report in reports) {
    final [kind, ...nodes] = report.split(':');
    final at = [for (final n in nodes) byNode[int.tryParse(n.substring(1))]];
    if (kind == 'oneway' && at.length == 2) {
      twoWay.addAll(between(at[0], at[1]).map((e) => e.id));
    } else if (kind == 'turn' && at.length == 3 && at[1] != null) {
      for (final from in between(at[1], at[0])) {
        for (final to in between(at[1], at[2])) {
          allowed.add((from.id, at[1]!, to.id));
        }
      }
    }
  }
  return graph.allowing(twoWay: twoWay, allowed: allowed);
}
