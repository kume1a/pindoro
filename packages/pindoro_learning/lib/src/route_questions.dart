import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'cards.dart';
import 'curriculum.dart';
import 'routes.dart';

/// A landmark a route card can ask about: one from the pack, or the player's own (SPEC §9).
/// [junction] is the pack junction it belongs to, [onLeft] its side driving in.
typedef RouteLandmark = ({
  String id,
  String name,
  String kind,
  LatLng at,
  bool personal,
  int? junction,
  bool? onLeft,
});

/// What a route card shows and checks (SPEC §3, §5.2); the session plays it.
sealed class RouteQuestion {
  const RouteQuestion(this.itemId);

  final String itemId;
}

/// J: on [approachStreet] heading to [destChunk], at the junction (and [landmark]), which
/// way? [exits] are the junction's legal ways on, one per direction; [exitStreet] is the street
/// the right one is on.
final class TurnQuestion extends RouteQuestion {
  const TurnQuestion(
    super.itemId, {
    required this.junction,
    required this.approach,
    required this.exits,
    required this.correct,
    this.approachStreet,
    this.exitStreet,
    this.destChunk,
    this.landmark,
  });

  final int junction;
  final RoadEdge approach;
  final Map<Turn, RoadEdge> exits;
  final Turn correct;
  final NamedStreet? approachStreet;
  final NamedStreet? exitStreet;
  final String? destChunk;
  final RouteLandmark? landmark;
}

/// G: out of (or into) [chunk], where do you join the main road? Pin [at] and name
/// [exitStreet].
final class GatewayQuestion extends RouteQuestion {
  const GatewayQuestion(
    super.itemId, {
    required this.junction,
    required this.at,
    required this.chunk,
    required this.out,
    this.exitStreet,
  });

  final int junction;
  final LatLng at;
  final String chunk;
  final bool out;
  final NamedStreet? exitStreet;
}

/// B: from [approachStreet], which bridge crosses the river towards [destChunk]? [options] are
/// the nearest bridges, [bridge] among them.
final class BridgeQuestion extends RouteQuestion {
  const BridgeQuestion(
    super.itemId, {
    required this.at,
    required this.bridge,
    required this.options,
    this.approachStreet,
    this.destChunk,
  });

  final LatLng at;
  final Bridge bridge;
  final List<Bridge> options;
  final NamedStreet? approachStreet;
  final String? destChunk;
}

/// C: [street] runs from [from] to which street? ([to], typed.)
final class ConnectionQuestion extends RouteQuestion {
  const ConnectionQuestion(
    super.itemId, {
    required this.street,
    required this.from,
    required this.to,
  });

  final NamedStreet street;
  final NamedStreet from;
  final NamedStreet to;
}

/// L1 pin the [landmark]; L2 pick its junction among [junctions]; L3 at [junction] coming in
/// on [approachStreet], pick the landmark among [names].
final class LandmarkQuestion extends RouteQuestion {
  const LandmarkQuestion(
    super.itemId, {
    required this.n,
    required this.landmark,
    this.junction,
    this.junctions = const [],
    this.names = const [],
    this.approachStreet,
  });

  final int n;
  final RouteLandmark landmark;
  final int? junction;

  /// L2's choices, the right one among them (pack junction ids).
  final List<int> junctions;

  /// L3's choices, the right one among them.
  final List<String> names;
  final NamedStreet? approachStreet;
}

/// A street photo card (SPEC §3, §5.2): S1 which street is [street]; S2 heading to [destChunk],
/// which way at the junction ahead ([exits], the right one [correct], onto [exitStreet]); S3
/// where was [image] taken and which way does it look. The photo is taken on [approach] before
/// [junction].
final class SceneQuestion extends RouteQuestion {
  const SceneQuestion(
    super.itemId, {
    required this.n,
    required this.image,
    required this.junction,
    required this.approach,
    this.street,
    this.exits = const {},
    this.correct,
    this.exitStreet,
    this.destChunk,
  });

  final int n;
  final SceneImage image;
  final int junction;
  final RoadEdge approach;
  final NamedStreet? street;
  final Map<Turn, RoadEdge> exits;
  final Turn? correct;
  final NamedStreet? exitStreet;
  final String? destChunk;
}

/// The city's route items: what opens each (for the planner) and what each asks.
typedef RouteBook = ({
  List<RouteCandidate> candidates,
  Map<String, RouteQuestion> questions,
});

/// How many choices a pick question offers.
const int _choices = 4;

/// Degrees from north driving along [line] at its start.
double _startBearing(Polyline line) => bearingDegrees(line[0], line[1]);

/// The heading arriving at [junction] on [edge].
double arrivingBearing(RoadEdge edge, int junction) {
  final line = edge.lineFrom(edge.other(junction));
  return bearingDegrees(line[line.length - 2], line.last);
}

/// The heading leaving [junction] on [edge].
double leavingBearing(RoadEdge edge, int junction) =>
    _startBearing(edge.lineFrom(junction));

/// The legal ways on at [junction] arriving on [approach] (no U-turn), by direction; null when
/// two share a direction, which a J card can't tell apart. A pack cut to a fixture can leave a
/// turn with one way on: no card then.
Map<Turn, RoadEdge>? exitsByTurn(
  RoadGraph graph,
  int junction,
  RoadEdge approach,
) {
  final heading = arrivingBearing(approach, junction);
  final exits = <Turn, RoadEdge>{};
  for (final e in graph.legalExits(junction, approach: approach)) {
    if (e.id == approach.id) continue;
    final turn = turnOf(heading, leavingBearing(e, junction));
    if (turn == Turn.uTurn || exits.containsKey(turn)) return null;
    exits[turn] = e;
  }
  return exits;
}

/// Builds the route items of a format 5 pack (SPEC §3, §16.14): a J card per skeleton and
/// district turn whose ways on have distinct directions, a G card per gateway junction, a B card
/// per bridge approach, a C card per grid street and family parent with two named ends, and
/// L1–L3 for each landmark on a turn and each of [personal]. [streets] are by part id.
RouteBook buildRouteBook({
  required RoadGraph graph,
  required Map<int, int> junctionNodes,
  required List<JunctionItem> items,
  required List<Landmark> landmarks,
  required List<Bridge> bridges,
  required Map<String, NamedStreet> streets,
  required Curriculum curriculum,
  List<RouteLandmark> personal = const [],
  List<SceneImage> scenes = const [],
}) {
  final edges = {for (final e in graph.edges) e.id: e};
  final candidates = <RouteCandidate>[];
  final questions = <String, RouteQuestion>{};
  final byLandmark = {for (final l in landmarks) l.id: l};
  final onTurns = <String, RouteLandmark>{};
  final sceneTurns = <(int, int), ({String itemId, JunctionItem item})>{};
  NamedStreet? streetOf(RoadEdge e) => streets[e.streetId];
  void add(RouteCandidate c, RouteQuestion q) {
    if (questions.containsKey(c.itemId)) return;
    candidates.add(c);
    questions[c.itemId] = q;
  }

  for (final item in items) {
    final approach = edges[item.approachEdge];
    final exit = edges[item.exitEdge];
    final node = junctionNodes[item.junctionId];
    if (approach == null || exit == null || node == null) continue;
    final from = junctionNodes[approach.other(item.junctionId)];
    final to = junctionNodes[exit.other(item.junctionId)];
    final into = streetOf(approach);
    final onto = streetOf(exit);
    final at = graph.at(item.junctionId);
    final known = {?into?.id, ?onto?.id};
    switch (item.layer) {
      case JunctionLayer.skeleton || JunctionLayer.district:
        final exits = exitsByTurn(graph, item.junctionId, approach);
        final correct = exits?.entries
            .where((e) => e.value.id == exit.id)
            .firstOrNull
            ?.key;
        if (exits == null ||
            exits.length < 2 ||
            correct == null ||
            from == null ||
            to == null) {
          continue;
        }
        final landmark = switch (byLandmark[item.landmarkId]) {
          final l? => (
            id: l.id,
            name: l.nameKa,
            kind: l.kind,
            at: l.at,
            personal: false,
            junction: item.junctionId,
            onLeft: item.landmarkOnLeft,
          ),
          null => null,
        };
        if (landmark != null) onTurns.putIfAbsent(landmark.id, () => landmark);
        final id = RouteIds.junction(node, from, to);
        if (item.layer == JunctionLayer.skeleton) {
          _keepFirst(sceneTurns, (item.junctionId, approach.id), id, item);
        }
        add(
          (
            itemId: id,
            layer: item.layer == JunctionLayer.skeleton
                ? RouteLayer.skeleton
                : RouteLayer.district,
            rank: item.rank,
            known: known,
            raion: into == null ? null : curriculum.raionOf(into.id),
            chunk: null,
            phase2: false,
            personal: false,
            knownCards: const {},
            solidCards: const {},
          ),
          TurnQuestion(
            id,
            junction: item.junctionId,
            approach: approach,
            exits: exits,
            correct: correct,
            approachStreet: into,
            exitStreet: onto,
            destChunk: item.destChunkId,
            landmark: landmark,
          ),
        );
      case JunctionLayer.gatewayOut || JunctionLayer.gatewayIn:
        final chunk = item.chunkId;
        if (chunk == null) continue;
        final out = item.layer == JunctionLayer.gatewayOut;
        final id = RouteIds.gateway(chunk, node, out: out);
        _keepFirst(sceneTurns, (item.junctionId, approach.id), id, item);
        add(
          (
            itemId: id,
            layer: RouteLayer.gateway,
            rank: item.rank,
            known: {?onto?.id},
            raion: null,
            chunk: chunk,
            phase2: !out,
            personal: false,
            knownCards: const {},
            solidCards: const {},
          ),
          GatewayQuestion(
            id,
            junction: item.junctionId,
            at: at,
            chunk: chunk,
            out: out,
            exitStreet: out ? onto : into,
          ),
        );
      case JunctionLayer.bridge:
        final bridge = bridges.where((b) => b.id == item.bridgeId).firstOrNull;
        final bank = into?.parts.first.bank;
        if (bridge == null || bank == null) continue;
        final nearest = [...bridges]
          ..sort(
            (a, b) => distanceBetween(
              at,
              a.midpoint,
            ).compareTo(distanceBetween(at, b.midpoint)),
          );
        final options = nearest.take(_choices).toList();
        if (!options.contains(bridge)) options[options.length - 1] = bridge;
        final id = RouteIds.bridge(
          bridge.id,
          bank == RiverBank.left ? 'L' : 'R',
          node,
        );
        add(
          (
            itemId: id,
            layer: RouteLayer.bridge,
            rank: item.rank,
            known: const {},
            raion: null,
            chunk: null,
            phase2: false,
            personal: false,
            knownCards: const {},
            solidCards: const {},
          ),
          BridgeQuestion(
            id,
            at: at,
            bridge: bridge,
            options: options,
            approachStreet: into,
            destChunk: item.destChunkId,
          ),
        );
    }
  }

  final all = streets.values.toSet();
  for (final street in curriculum.streetsWhere(
    (s) =>
        Curriculum.isCore(s) &&
        (curriculum.tierOf(s.id) == StreetTier.b ||
            curriculum.childrenOf(s.id).isNotEmpty),
  )) {
    final ends = crossingsAlong(street, all);
    if (ends.length < 2) continue;
    final from = ends.first.street;
    final to = ends.last.street;
    final id = RouteIds.connection(street.id);
    add((
      itemId: id,
      layer: RouteLayer.connection,
      rank: 0,
      known: {street.id, from.id, to.id},
      raion: null,
      chunk: null,
      phase2: false,
      personal: false,
      knownCards: const {},
      solidCards: const {},
    ), ConnectionQuestion(id, street: street, from: from, to: to));
  }

  final turnJunctions = {
    for (final q in questions.values)
      if (q is TurnQuestion) q.junction: q,
  };
  for (final landmark in [...onTurns.values, ...personal]) {
    final at = landmark.junction;
    final turn = turnJunctions[at];
    final nearJunctions =
        (turnJunctions.keys.where((j) => j != at).toList()..sort(
              (a, b) => distanceBetween(
                landmark.at,
                graph.at(a),
              ).compareTo(distanceBetween(landmark.at, graph.at(b))),
            ))
            .take(_choices - 1);
    final nearNames =
        (onTurns.values.where((l) => l.name != landmark.name).toList()..sort(
              (a, b) => distanceBetween(
                landmark.at,
                a.at,
              ).compareTo(distanceBetween(landmark.at, b.at)),
            ))
            .map((l) => l.name)
            .toSet()
            .take(_choices - 1);
    final random = Random(landmark.id.hashCode);
    final known = {?turn?.approachStreet?.id};
    for (final n in [1, 2, 3]) {
      if (n > 1 && (at == null || turn == null)) continue;
      final id = RouteIds.landmark(landmark.id, n);
      add(
        (
          itemId: id,
          layer: RouteLayer.landmark,
          rank: n,
          known: known,
          raion: null,
          chunk: null,
          phase2: false,
          personal: landmark.personal,
          knownCards: const {},
          solidCards: const {},
        ),
        LandmarkQuestion(
          id,
          n: n,
          landmark: landmark,
          junction: at,
          junctions: n == 2
              ? ([?at, ...nearJunctions]..shuffle(random))
              : const [],
          names: n == 3
              ? ([landmark.name, ...nearNames]..shuffle(random))
              : const [],
          approachStreet: turn?.approachStreet,
        ),
      );
    }
  }
  final junctionOf = {for (final e in junctionNodes.entries) e.value: e.key};
  final named = <String>{};
  for (final image in scenes) {
    final junction = junctionOf[image.junctionNode];
    final approach = junction == null
        ? null
        : graph
              .edgesAt(junction)
              .where(
                (e) => junctionNodes[e.other(junction)] == image.approachNode,
              )
              .firstOrNull;
    if (junction == null || approach == null) continue;
    final street = streetOf(approach);
    RouteCandidate scene(
      int n, {
      required int rank,
      String? raion,
      bool phase2 = false,
      Set<String> knownCards = const {},
      Set<String> solidCards = const {},
    }) => (
      itemId: RouteIds.scene(image.id, n),
      layer: RouteLayer.scene,
      rank: rank,
      known: {?street?.id},
      raion: raion,
      chunk: null,
      phase2: phase2,
      personal: false,
      knownCards: knownCards,
      solidCards: solidCards,
    );
    final turn = sceneTurns[(junction, approach.id)];
    final exits = exitsByTurn(graph, junction, approach);
    final correct = exits?.entries
        .where((e) => e.value.id == turn?.item.exitEdge)
        .firstOrNull
        ?.key;
    if (turn != null &&
        exits != null &&
        exits.length > 1 &&
        correct != null &&
        turn.item.destChunkId != null) {
      final c = scene(2, rank: 1, knownCards: {turn.itemId});
      add(
        c,
        SceneQuestion(
          c.itemId,
          n: 2,
          image: image,
          junction: junction,
          approach: approach,
          street: street,
          exits: exits,
          correct: correct,
          exitStreet: streetOf(exits[correct]!),
          destChunk: turn.item.destChunkId,
        ),
      );
    }
    if (street == null) continue;
    if (curriculum.tierOf(street.id) != StreetTier.c && named.add(street.id)) {
      final c = scene(
        1,
        rank: 2,
        phase2: true,
        solidCards: {CardType.p.item(street.id), CardType.n.item(street.id)},
      );
      add(
        c,
        SceneQuestion(
          c.itemId,
          n: 1,
          image: image,
          junction: junction,
          approach: approach,
          street: street,
        ),
      );
    }
    final raion = curriculum.raionOf(street.id);
    if (raion == null) continue;
    final c = scene(3, rank: 3, raion: raion);
    add(
      c,
      SceneQuestion(
        c.itemId,
        n: 3,
        image: image,
        junction: junction,
        approach: approach,
        street: street,
      ),
    );
  }
  return (candidates: candidates, questions: questions);
}

/// Keeps the lowest-rank [item] for an approach: the turn its S2 photo asks.
void _keepFirst(
  Map<(int, int), ({String itemId, JunctionItem item})> turns,
  (int, int) approach,
  String itemId,
  JunctionItem item,
) {
  final kept = turns[approach];
  if (kept == null || item.rank < kept.item.rank) {
    turns[approach] = (itemId: itemId, item: item);
  }
}

/// The pack junction with OSM node [node] (a personal landmark's), or null.
int? junctionOfNode(Map<int, int> junctionNodes, int node) => junctionNodes
    .entries
    .where((e) => e.value == node)
    .map((e) => e.key)
    .firstOrNull;
