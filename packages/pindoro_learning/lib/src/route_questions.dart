import 'package:pindoro_core/pindoro_core.dart';

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
