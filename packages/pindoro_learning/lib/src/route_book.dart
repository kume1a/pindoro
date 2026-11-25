import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'cards.dart' show stableSeed;
import 'constants.dart';
import 'curriculum.dart';
import 'map_labels.dart';
import 'names.dart';
import 'route_questions.dart';
import 'routes.dart';

// ponytail: by kind, not a city-wide branch count; pack that count if another kind needs it.
/// Kinds of place the city has many alike, so always named with their street (SPEC §16.20).
const Set<String> _chainKinds = {'fuel', 'supermarket'};

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
  final book = _Book();
  final carried = _junctionCards(
    book,
    graph: graph,
    junctionNodes: junctionNodes,
    items: items,
    landmarks: landmarks,
    bridges: bridges,
    streets: streets,
    curriculum: curriculum,
  );
  final all = streets.values.toSet();
  _connectionCards(book, all, curriculum);
  _landmarkCards(
    book,
    graph: graph,
    landmarks: landmarks,
    streets: streets,
    all: all,
    carried: carried,
    personal: personal,
  );
  return (candidates: book.candidates, questions: book.questions);
}

/// The book as it is built: each item once, its first card kept.
final class _Book {
  final candidates = <RouteCandidate>[];
  final questions = <String, RouteQuestion>{};

  void add(RouteCandidate c, RouteQuestion q) {
    if (questions.containsKey(c.itemId)) return;
    candidates.add(c);
    questions[c.itemId] = q;
  }
}

/// The pack landmarks J cards carry, each with the first turn that carried it: its L cards
/// ask from that approach.
typedef _Carried = Map<String, ({RouteLandmark landmark, TurnQuestion turn})>;

/// The J, G and B cards of the pack's junction [items].
_Carried _junctionCards(
  _Book book, {
  required RoadGraph graph,
  required Map<int, int> junctionNodes,
  required List<JunctionItem> items,
  required List<Landmark> landmarks,
  required List<Bridge> bridges,
  required Map<String, NamedStreet> streets,
  required Curriculum curriculum,
}) {
  final edges = {for (final e in graph.edges) e.id: e};
  final byLandmark = {for (final l in landmarks) l.id: l};
  final _Carried carried = {};
  NamedStreet? streetOf(RoadEdge e) => streets[e.streetId];
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
          carried.putIfAbsent(
            landmark.id,
            () => (landmark: landmark, turn: question),
          );
        }
        book.add((
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
        book.add(
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
        final options = nearest.take(LearningConfig.routeChoices).toList();
        if (options.length < 2) continue;
        if (!options.contains(bridge)) options[options.length - 1] = bridge;
        final id = RouteIds.bridge(
          bridge.id,
          bank == RiverBank.left ? 'L' : 'R',
          node,
        );
        book.add(
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

  return carried;
}

/// A C card per grid street and family parent with two named ends.
void _connectionCards(_Book book, Set<NamedStreet> all, Curriculum curriculum) {
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
    book.add((
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
}

/// L1–L3 for each landmark a turn [carried] and each of [personal].
void _landmarkCards(
  _Book book, {
  required RoadGraph graph,
  required List<Landmark> landmarks,
  required Map<String, NamedStreet> streets,
  required Set<NamedStreet> all,
  required _Carried carried,
  required List<RouteLandmark> personal,
}) {
  final byLandmark = {for (final l in landmarks) l.id: l};
  final onTurns = [for (final c in carried.values) c.landmark];
  NamedStreet? streetOf(RoadEdge e) => streets[e.streetId];
  final turnJunctions = {
    for (final q in book.questions.values)
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
  final places = [...onTurns, ...personal];
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
  for (final l in onTurns) {
    if (streetOfPlace[l.id] == null) continue;
    sameOnStreet.update(nameOnStreet(l), (n) => n + 1, ifAbsent: () => 1);
  }
  for (final landmark in places) {
    final at = landmark.junction;
    final turn = carried[landmark.id]?.turn ?? turnJunctions[at];
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
          ? _placeChoices(landmark, onTurns)
          : const <RouteLandmark>[];
      if (n == 2 && junctions.length < 2) continue;
      if (n == 3 &&
          (choices.length < 2 ||
              streetsAt(at!).any((s) => _namesStreet(landmark, s)))) {
        continue;
      }
      final id = RouteIds.landmark(landmark.id, n);
      book.add(
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
        .take(LearningConfig.routeChoices - 1),
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
    ..._byDistance(place.at, onTurns, (l) => l.at)
        .where((l) => names.add(normaliseName(l.name)))
        .take(LearningConfig.routeChoices - 1),
  ];
}

/// The pack junction with OSM node [node] (a personal landmark's), or null.
int? junctionOfNode(Map<int, int> junctionNodes, int node) => junctionNodes
    .entries
    .where((e) => e.value == node)
    .map((e) => e.key)
    .firstOrNull;
