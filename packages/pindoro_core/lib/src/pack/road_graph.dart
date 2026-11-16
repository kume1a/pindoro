import 'dart:math' show min;

import '../geo/geo.dart';
import '../geo/polyline6.dart';
import 'models.dart';

/// Which way an edge may be driven (pack format 5 `road_edge.oneway`):
/// [forward] only from its `from` junction to its `to`, [backward] only the
/// other way.
enum Oneway { both, forward, backward }

/// Numbers for routing on the directed graph (SPEC §16.7).
abstract final class RoutingConfig {
  /// What a U-turn adds to a route's cost: about 30 s at 30 km/h.
  static const double uTurnPenaltyM = 250;
}

/// A turn restriction (OSM `type=restriction`, pack `turn_restriction`):
/// arriving on [fromEdge] at junction [via], [toEdge] is forbidden (`no_*`),
/// or with [only] (`only_*`) the only way on.
typedef TurnRestriction = ({int fromEdge, int via, int toEdge, bool only});

/// A stretch of road between two junctions (pack `road_edge`): of a street,
/// or with no [streetId] a connector (an unnamed way or a `*_link`).
class RoadEdge {
  RoadEdge({
    required this.id,
    required this.from,
    required this.to,
    required this.streetId,
    required this.lengthM,
    required Polyline line,
    this.oneway = Oneway.both,
  }) : _line = line,
       _geometry = null;

  /// Keeps the polyline6 and decodes it on first use: a city has thousands
  /// of edges and a trip draws a few dozen. Packs before format 5 have no
  /// `oneway` column: every edge is two-way there.
  RoadEdge.fromRow(PackRow r)
    : id = r['id']! as int,
      from = r['from_junction']! as int,
      to = r['to_junction']! as int,
      streetId = r['street_id'] as String?,
      lengthM = (r['length_m']! as num).toDouble(),
      oneway = switch (r['oneway']) {
        1 => Oneway.forward,
        -1 => Oneway.backward,
        _ => Oneway.both,
      },
      _geometry = r['geometry']! as String;

  final int id;
  final int from;
  final int to;

  /// The street part (pack `street.id`) it belongs to; null for a connector.
  final String? streetId;
  final double lengthM;
  final Oneway oneway;
  final String? _geometry;
  Polyline? _line;

  /// From [from] to [to].
  Polyline get line => _line ??= decodePolyline6(_geometry!);

  /// The far end, driving away from [junction].
  int other(int junction) => junction == from ? to : from;

  /// The line as driven away from [junction].
  Polyline lineFrom(int junction) =>
      junction == from ? line : line.reversed.toList();
}

/// A drive along edges: its junctions from the start, the edges between them,
/// its length and its cost (the length plus [RoutingConfig.uTurnPenaltyM] per
/// U-turn).
class Route {
  const Route(this.junctions, this.edges, this.lengthM, {double? costM})
    : costM = costM ?? lengthM;

  final List<int> junctions;
  final List<RoadEdge> edges;
  final double lengthM;
  final double costM;

  /// Each edge's line in driving order.
  MultiPolyline get lines => [
    for (final (i, e) in edges.indexed) e.lineFrom(junctions[i]),
  ];
}

/// A city's road graph (pack format 3, directed from format 5): junctions,
/// the edges at each (by id) and the turn restrictions.
class RoadGraph {
  RoadGraph(
    this.junctions,
    Iterable<RoadEdge> edges, {
    Iterable<TurnRestriction> restrictions = const [],
  }) : edges = List.unmodifiable(edges) {
    for (final e in this.edges) {
      _at.putIfAbsent(e.from, () => []).add(e);
      if (e.to != e.from) _at.putIfAbsent(e.to, () => []).add(e);
    }
    for (final list in _at.values) {
      list.sort((a, b) => a.id.compareTo(b.id));
    }
    for (final r in restrictions) {
      final turn = _turns.putIfAbsent((r.fromEdge, r.via), _Turn.new);
      (r.only ? (turn.only ??= {}) : turn.no).add(r.toEdge);
    }
  }

  final Map<int, LatLng> junctions;
  final List<RoadEdge> edges;
  final Map<int, List<RoadEdge>> _at = {};
  final Map<(int, int), _Turn> _turns = {};

  /// The connected piece of network each junction with edges lies on,
  /// ignoring one-ways.
  late final Map<int, int> _piece = _pieces();

  late final Map<String, Set<int>> _byPart = _junctionsByPart();

  /// The edges at [junction], by id.
  List<RoadEdge> edgesAt(int junction) => _at[junction] ?? const [];

  LatLng at(int junction) => junctions[junction]!;

  /// The junctions on the street part [partId] (pack `street.id`).
  Set<int> junctionsOfPart(String partId) => _byPart[partId] ?? const {};

  /// Whether some drive joins [a] and [b], one-ways aside.
  bool connected(int a, int b) =>
      a == b || (_piece[a] != null && _piece[a] == _piece[b]);

  /// Whether [e] may be driven away from [fromJunction].
  bool canDrive(RoadEdge e, int fromJunction) => switch (e.oneway) {
    Oneway.both => true,
    Oneway.forward => fromJunction == e.from,
    Oneway.backward => fromJunction == e.to,
  };

  /// The edges one may drive away from [junction] having arrived on
  /// [approach] (null: starting there), by id: those [canDrive] allows and
  /// the turn restrictions keep; the approach itself (a U-turn) only when it
  /// is two-way.
  List<RoadEdge> legalExits(int junction, {RoadEdge? approach}) {
    final turn = approach == null ? null : _turns[(approach.id, junction)];
    return [
      for (final e in edgesAt(junction))
        if (canDrive(e, junction) &&
            (e.id != approach?.id || e.oneway == Oneway.both) &&
            (turn == null ||
                (!turn.no.contains(e.id) &&
                    (turn.only?.contains(e.id) ?? true))))
          e,
    ];
  }

  /// The cheapest legal drive from [from] to the nearest of [goals] (SPEC
  /// §16.7): A* over (edge driven, junction reached) on [legalExits], each
  /// U-turn costing [RoutingConfig.uTurnPenaltyM] more, the straight line to
  /// the nearest goal as the heuristic, over the edges [allow] keeps. Having
  /// arrived on [approach] restricts the first turn. Ties go to the lower
  /// edge id, then the lower junction id (the start, with no edge, first).
  /// Null when no goal is reached.
  Route? shortestRoute(
    int from,
    Set<int> goals, {
    bool Function(RoadEdge edge)? allow,
    RoadEdge? approach,
  }) {
    // A search between pieces would expand all of [from]'s piece to fail.
    if (!goals.any((g) => connected(from, g))) return null;
    final toGoal = <int, double>{};
    double h(int j) => toGoal.putIfAbsent(
      j,
      () => goals.map((g) => distanceBetween(at(j), at(g))).reduce(min),
    );
    final start = _State(approach, from);
    final cost = <_State, double>{start: 0};
    final back = <_State, _State>{};
    final open = _Heap()..push((0 + h(from), start));
    final closed = <_State>{};
    while (open.isNotEmpty) {
      final (_, state) = open.pop();
      if (!closed.add(state)) continue;
      final c = cost[state]!;
      if (goals.contains(state.junction)) {
        return _route(state, back, c);
      }
      for (final e in legalExits(state.junction, approach: state.edge)) {
        if (allow != null && !allow(e)) continue;
        final next = _State(e, e.other(state.junction));
        if (closed.contains(next)) continue;
        final uTurn = e.id == state.edge?.id;
        final nc = c + e.lengthM + (uTurn ? RoutingConfig.uTurnPenaltyM : 0);
        if (nc >= (cost[next] ?? double.infinity)) continue;
        cost[next] = nc;
        back[next] = state;
        open.push((nc + h(next.junction), next));
      }
    }
    return null;
  }

  /// The edge nearest [p], within [withinM]; null when none is that close.
  RoadEdge? edgeNear(LatLng p, double withinM) {
    RoadEdge? best;
    var bestM = withinM;
    for (final e in edges) {
      // A point on the edge is at most its length from both ends together,
      // so this skips far edges without decoding their lines.
      if (distanceBetween(p, at(e.from)) + distanceBetween(p, at(e.to)) >
          e.lengthM + 2 * withinM) {
        continue;
      }
      final m = pointToPolylineDistance(p, [e.line]).distanceMeters;
      if (m <= bestM) (best, bestM) = (e, m);
    }
    return best;
  }

  Route _route(_State end, Map<_State, _State> back, double costM) {
    final junctions = [end.junction];
    final edges = <RoadEdge>[];
    for (var s = end; back[s] != null; s = back[s]!) {
      edges.add(s.edge!);
      junctions.add(back[s]!.junction);
    }
    final driven = edges.reversed.toList();
    return Route(
      junctions.reversed.toList(),
      driven,
      driven.fold(0, (sum, e) => sum + e.lengthM),
      costM: costM,
    );
  }

  Map<int, int> _pieces() {
    final piece = <int, int>{};
    for (final start in _at.keys) {
      if (piece.containsKey(start)) continue;
      piece[start] = start;
      final stack = [start];
      while (stack.isNotEmpty) {
        final j = stack.removeLast();
        for (final e in edgesAt(j)) {
          final next = e.other(j);
          if (piece.containsKey(next)) continue;
          piece[next] = start;
          stack.add(next);
        }
      }
    }
    return piece;
  }

  Map<String, Set<int>> _junctionsByPart() {
    final byPart = <String, Set<int>>{};
    for (final e in edges) {
      if (e.streetId case final part?) {
        byPart.putIfAbsent(part, () => {})
          ..add(e.from)
          ..add(e.to);
      }
    }
    return byPart;
  }
}

/// The ways on from one arrival: forbidden exits, or the only ones allowed.
class _Turn {
  final Set<int> no = {};
  Set<int>? only;
}

/// A search state: arrived at [junction] on [edge] (null at the start).
class _State {
  const _State(this.edge, this.junction);

  final RoadEdge? edge;
  final int junction;

  int get _edgeId => edge?.id ?? -1;

  @override
  bool operator ==(Object other) =>
      other is _State && other._edgeId == _edgeId && other.junction == junction;

  @override
  int get hashCode => Object.hash(_edgeId, junction);
}

/// A binary min-heap of (estimate, state), ordered by estimate, then edge id
/// (the start's -1 first), then junction: the same order as `@pindoro/geo`.
class _Heap {
  final _items = <(double, _State)>[];

  bool get isNotEmpty => _items.isNotEmpty;

  static bool _before((double, _State) a, (double, _State) b) {
    if (a.$1 != b.$1) return a.$1 < b.$1;
    if (a.$2._edgeId != b.$2._edgeId) return a.$2._edgeId < b.$2._edgeId;
    return a.$2.junction < b.$2.junction;
  }

  void _swap(int a, int b) {
    final t = _items[a];
    _items[a] = _items[b];
    _items[b] = t;
  }

  void push((double, _State) item) {
    _items.add(item);
    var i = _items.length - 1;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (!_before(_items[i], _items[parent])) break;
      _swap(i, parent);
      i = parent;
    }
  }

  (double, _State) pop() {
    final top = _items.first;
    final last = _items.removeLast();
    if (_items.isNotEmpty) {
      _items[0] = last;
      var i = 0;
      while (true) {
        final l = 2 * i + 1, r = l + 1;
        var m = i;
        if (l < _items.length && _before(_items[l], _items[m])) m = l;
        if (r < _items.length && _before(_items[r], _items[m])) m = r;
        if (m == i) break;
        _swap(i, m);
        i = m;
      }
    }
    return top;
  }
}
