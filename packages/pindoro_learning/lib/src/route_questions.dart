import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'cards.dart' show stableSeed;
import 'curriculum.dart';
import 'grader.dart';
import 'map_labels.dart';
import 'routes.dart';

/// A landmark a route card can ask about: one from the pack, or the player's own (SPEC §9).
/// [junction] is the pack junction it belongs to, [onLeft] its side driving in.
typedef RouteLandmark = ({
  String id,
  String name,

  /// The English name, when the pack has one (the player's own have none).
  String? nameEn,
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
/// on [approachStreet], pick the landmark among [places].
final class LandmarkQuestion extends RouteQuestion {
  const LandmarkQuestion(
    super.itemId, {
    required this.n,
    required this.landmark,
    this.junction,
    this.junctions = const [],
    this.places = const [],
    this.approachStreet,
    this.street,
    this.crossStreet,
    this.ambiguous = false,
    this.outline,
  });

  final int n;
  final RouteLandmark landmark;
  final int? junction;

  /// L2's choices, the right one among them (pack junction ids).
  final List<int> junctions;

  /// L3's choices, one per name, the right one among them; the answer is the
  /// chosen place's `name`.
  final List<RouteLandmark> places;
  final NamedStreet? approachStreet;

  /// The street the landmark stands on: the one of its junction's nearest it.
  final NamedStreet? street;

  /// A chain or a repeated name: the question names [street] with it (SPEC §16.18).
  final bool ambiguous;

  /// Another place of the same name on [street]: its junction's other street,
  /// named too (SPEC §16.20).
  final NamedStreet? crossStreet;

  /// The pack's outline of an area place (a park, a mall); null for a point.
  final List<List<Polyline>>? outline;

  /// The [outline]'s rings as lines to draw, null for a point.
  MultiPolyline? get outlineLines => switch (outline) {
    final o? => [for (final polygon in o) ...polygon],
    null => null,
  };

  /// How far [pin] is from the place, and the spot that is measured to: 0
  /// anywhere inside its [outline], else to the outline's nearest edge; a
  /// point place to its point (SPEC §16.18 item 95).
  ({double distanceM, LatLng to}) distanceFrom(LatLng pin) {
    final o = outline;
    if (o == null) {
      return (distanceM: distanceBetween(pin, landmark.at), to: landmark.at);
    }
    if (boundaryContains(o, pin)) return (distanceM: 0, to: pin);
    final edge = pointToPolylineDistance(pin, outlineLines!);
    return (distanceM: edge.distanceMeters, to: edge.nearestPoint);
  }
}

/// The city's route items: what opens each (for the planner) and what each asks.
typedef RouteBook = ({
  List<RouteCandidate> candidates,
  Map<String, RouteQuestion> questions,
});

/// How many choices a pick question offers.
const int _choices = 4;

// ponytail: by kind, not a city-wide branch count; pack that count if another kind needs it.
/// Kinds of place the city has many alike, so always named with their street (SPEC §16.20).
const Set<String> _chainKinds = {'fuel', 'supermarket'};

/// Degrees from north driving along [line] at its start, past a repeated first vertex.
double _startBearing(Polyline line) =>
    bearingDegrees(line.first, _awayFrom(line.first, line.skip(1)));

/// The first of [points] that isn't [at] (the last one when all are).
LatLng _awayFrom(LatLng at, Iterable<LatLng> points) =>
    points.firstWhere((p) => p != at, orElse: () => points.last);

/// The heading arriving at [junction] on [edge], past a repeated last vertex.
double arrivingBearing(RoadEdge edge, int junction) {
  final line = edge.lineFrom(edge.other(junction));
  return bearingDegrees(_awayFrom(line.last, line.reversed.skip(1)), line.last);
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
}) {
  final edges = {for (final e in graph.edges) e.id: e};
  final candidates = <RouteCandidate>[];
  final questions = <String, RouteQuestion>{};
  final byLandmark = {for (final l in landmarks) l.id: l};
  final onTurns = <String, RouteLandmark>{};
  // The turn whose card first carried each pack landmark: its L cards follow that approach.
  final carriedBy = <String, TurnQuestion>{};
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
            nameEn: l.nameEn,
            kind: l.kind,
            at: l.at,
            personal: false,
            junction: item.junctionId,
            onLeft: item.landmarkOnLeft,
          ),
          null => null,
        };
        final turnsOntoIt =
            onto != null && onto != into && _namesStreet(landmark, onto);
        final id = RouteIds.junction(node, from, to);
        final question = TurnQuestion(
          id,
          junction: item.junctionId,
          approach: approach,
          exits: exits,
          correct: correct,
          approachStreet: into,
          exitStreet: onto,
          destChunk: item.destChunkId,
          // A place named after the way on would give the answer away.
          landmark: turnsOntoIt ? null : landmark,
        );
        if (landmark != null) {
          onTurns.putIfAbsent(landmark.id, () => landmark);
          carriedBy.putIfAbsent(landmark.id, () => question);
        }
        add((
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
        ), question);
      case JunctionLayer.gatewayOut || JunctionLayer.gatewayIn:
        final chunk = item.chunkId;
        if (chunk == null) continue;
        final out = item.layer == JunctionLayer.gatewayOut;
        final id = RouteIds.gateway(chunk, node, out: out);
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
        if (options.length < 2) continue;
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
    ), ConnectionQuestion(id, street: street, from: from, to: to));
  }

  final turnJunctions = {
    for (final q in questions.values)
      if (q is TurnQuestion) q.junction: q,
  };
  final sameName = <String, int>{};
  for (final l in landmarks) {
    sameName.update(normaliseName(l.nameKa), (n) => n + 1, ifAbsent: () => 1);
  }
  Set<NamedStreet> streetsAt(int junction) => {
    for (final e in graph.edgesAt(junction)) ?streetOf(e),
  };
  // How a junction reads on an L2 chip: the names of the streets there.
  String labelOf(int junction) => (streetsAt(
    junction,
  ).map((s) => normaliseName(s.name)).toSet().toList()..sort()).join(' × ');
  final places = [...onTurns.values, ...personal];
  // A place stands on the street of its junction nearest it (SPEC §16.18 item 89).
  final streetOfPlace = {
    for (final l in places)
      l.id: switch (l.junction) {
        final j? => _nearestTo(l.at, streetsAt(j).toList()),
        null => null,
      },
  };
  (String, String) nameOnStreet(RouteLandmark l) =>
      (normaliseName(l.name), streetOfPlace[l.id]?.id ?? '');
  final sameOnStreet = <(String, String), int>{};
  for (final l in onTurns.values) {
    if (streetOfPlace[l.id] == null) continue;
    sameOnStreet.update(nameOnStreet(l), (n) => n + 1, ifAbsent: () => 1);
  }
  for (final landmark in places) {
    final at = landmark.junction;
    final turn = carriedBy[landmark.id] ?? turnJunctions[at];
    final pack = byLandmark[landmark.id];
    final street = streetOfPlace[landmark.id];
    final twin =
        pack != null &&
        street != null &&
        (sameOnStreet[nameOnStreet(landmark)] ?? 0) > 1;
    final cross = twin
        ? _corner(landmark.at, street, streetsAt(at!), all)
        : null;
    final random = Random(stableSeed(landmark.id));
    final known = {?turn?.approachStreet?.id};
    for (final n in [1, 2, 3]) {
      if (n > 1 && (at == null || turn == null)) continue;
      // Named with its corner, its L2 would give the answer away.
      if (n == 2 && twin) continue;
      final junctions = n == 2
          ? _junctionChoices(
              at!,
              turnJunctions.keys,
              landmark.at,
              graph,
              labelOf,
            )
          : const <int>[];
      final choices = n == 3
          ? _placeChoices(landmark, onTurns.values)
          : const <RouteLandmark>[];
      if (n == 2 && junctions.length < 2) continue;
      if (n == 3 &&
          (choices.length < 2 ||
              streetsAt(at!).any((s) => _namesStreet(landmark, s)))) {
        continue;
      }
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
        ),
        LandmarkQuestion(
          id,
          n: n,
          landmark: landmark,
          junction: at,
          junctions: n == 2 ? (junctions..shuffle(random)) : const [],
          places: n == 3 ? (choices..shuffle(random)) : const [],
          approachStreet: turn?.approachStreet,
          outline: pack?.outline,
          street: street,
          crossStreet: cross,
          ambiguous:
              pack != null &&
              (pack.brand != null ||
                  _chainKinds.contains(pack.kind) ||
                  (sameName[normaliseName(pack.nameKa)] ?? 0) > 1),
        ),
      );
    }
  }
  return (candidates: candidates, questions: questions);
}

/// Of [streets], the one nearest [at].
NamedStreet? _nearestTo(LatLng at, List<NamedStreet> streets) {
  NamedStreet? best;
  var bestM = double.infinity;
  for (final s in streets) {
    final m = s.nearest(at).distanceM;
    if (m < bestM) (best, bestM) = (s, m);
  }
  return best;
}

/// Whether [place]'s name, in either script, holds a stem of [street]'s names.
bool _namesStreet(RouteLandmark? place, NamedStreet street) {
  if (place == null) return false;
  final stems = nameStems(street);
  return [
    place.name,
    ?place.nameEn,
  ].any((name) => stems.any(normaliseName(name).contains));
}

/// A twin place's corner: the other street at its [junctionStreets] nearest [at], else the
/// street crossing [street] nearest it.
NamedStreet? _corner(
  LatLng at,
  NamedStreet street,
  Set<NamedStreet> junctionStreets,
  Set<NamedStreet> all,
) =>
    _nearestTo(at, [
      for (final s in junctionStreets)
        if (s != street) s,
    ]) ??
    _byDistance(
      at,
      crossingsAlong(street, all),
      (c) => c.at,
    ).firstOrNull?.street;

/// [items] nearest [at] first, each measured once.
List<T> _byDistance<T>(LatLng at, Iterable<T> items, LatLng Function(T) where) {
  final distance = {for (final i in items) i: distanceBetween(at, where(i))};
  return distance.keys.toList()
    ..sort((a, b) => distance[a]!.compareTo(distance[b]!));
}

/// L2's choices: [answer] and the turn [junctions] nearest [at] whose streets read apart from
/// every other choice's (SPEC §16.21).
List<int> _junctionChoices(
  int answer,
  Iterable<int> junctions,
  LatLng at,
  RoadGraph graph,
  String Function(int junction) labelOf,
) {
  final label = labelOf(answer);
  if (label.isEmpty) return const [];
  final seen = {label};
  return [
    answer,
    ..._byDistance(at, junctions.where((j) => j != answer), graph.at)
        .where((j) {
          final read = labelOf(j);
          return read.isNotEmpty && seen.add(read);
        })
        .take(_choices - 1),
  ];
}

/// L3's choices: [place] and the places on turns nearest it, one per name.
List<RouteLandmark> _placeChoices(
  RouteLandmark place,
  Iterable<RouteLandmark> onTurns,
) {
  final names = {normaliseName(place.name)};
  return [
    place,
    ..._byDistance(
      place.at,
      onTurns,
      (l) => l.at,
    ).where((l) => names.add(normaliseName(l.name))).take(_choices - 1),
  ];
}

/// The pack junction with OSM node [node] (a personal landmark's), or null.
int? junctionOfNode(Map<int, int> junctionNodes, int node) => junctionNodes
    .entries
    .where((e) => e.value == node)
    .map((e) => e.key)
    .firstOrNull;
