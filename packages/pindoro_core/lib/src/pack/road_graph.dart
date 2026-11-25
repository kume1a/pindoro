import 'dart:math' show max, min;

import '../geo/geo.dart';
import 'road_edge.dart';

/// Numbers for routing on the directed graph (SPEC §16.7).
abstract final class RoutingConfig {
  /// What a U-turn adds to a route's cost: about 30 s at 30 km/h.
  static const double uTurnPenaltyM = 250;
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
    this.signals = const {},
    this.cameras = const [],
  }) : edges = List.unmodifiable(edges),
       restrictions = List.unmodifiable(restrictions) {
    for (final e in this.edges) {
      _at.putIfAbsent(e.from, () => []).add(e);
      if (e.to != e.from) _at.putIfAbsent(e.to, () => []).add(e);
    }
    for (final list in _at.values) {
      list.sort((a, b) => a.id.compareTo(b.id));
    }
    for (final r in this.restrictions) {
      final turn = _turns.putIfAbsent((r.fromEdge, r.via), _Turn.new);
      (r.only ? (turn.only ??= {}) : turn.no).add(r.toEdge);
    }
  }

  final Map<int, LatLng> junctions;
  final List<RoadEdge> edges;
  final List<TurnRestriction> restrictions;

  /// Junctions with traffic lights (pack format 7).
  final Set<int> signals;

  /// The speed cameras on the graph's edges (pack format 7).
  final List<SpeedCamera> cameras;
  final Map<int, List<RoadEdge>> _at = {};
  final Map<(int, int), _Turn> _turns = {};

  /// The connected piece of network each junction with edges lies on,
  /// ignoring one-ways.
  late final Map<int, int> _piece = _pieces();

  late final Map<String, Set<int>> _byPart = _junctionsByPart();

  /// This graph with moves the player reported as legal (app only, not twinned): the [twoWay]
  /// edges (by id) drivable both ways, and the turns in [allowed] (from edge, via junction, to
  /// edge) let through, an `only_*` restriction at their way in dropped.
  RoadGraph allowing({
    Set<int> twoWay = const {},
    Set<(int, int, int)> allowed = const {},
  }) => RoadGraph(
    junctions,
    [for (final e in edges) twoWay.contains(e.id) ? e.twoWay : e],
    restrictions: restrictions.where(
      (r) => !allowed.any(
        (a) =>
            a.$1 == r.fromEdge && a.$2 == r.via && (r.only || a.$3 == r.toEdge),
      ),
    ),
    signals: signals,
    cameras: cameras,
  );

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
  /// Null when no goal is reached. [costOf] (Dart only, navigation) prices an
  /// edge instead of its length, never below it so the heuristic holds, and
  /// [uTurnCostM] a U-turn; with [arriveOn] (Dart only, a stop on that road)
  /// a goal counts only when reached along it.
  Route? shortestRoute(
    int from,
    Set<int> goals, {
    bool Function(RoadEdge edge)? allow,
    RoadEdge? approach,
    double Function(RoadEdge edge)? costOf,
    double uTurnCostM = RoutingConfig.uTurnPenaltyM,
    RoadEdge? arriveOn,
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
      if (goals.contains(state.junction) &&
          (arriveOn == null || state.edge?.id == arriveOn.id)) {
        return _route(state, back, c);
      }
      for (final e in legalExits(state.junction, approach: state.edge)) {
        if (allow != null && !allow(e)) continue;
        final next = _State(e, e.other(state.junction));
        if (closed.contains(next)) continue;
        final uTurn = e.id == state.edge?.id;
        final nc =
            c + (costOf?.call(e) ?? e.lengthM) + (uTurn ? uTurnCostM : 0);
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
    for (final e in edgesWithin(p, withinM)) {
      final m = pointToPolylineDistance(p, [e.line]).distanceMeters;
      if (m <= bestM) (best, bestM) = (e, m);
    }
    return best;
  }

  /// The edges that may pass within [withinM] of [p], in [edges] order (Dart only, not
  /// twinned): every edge within it and a few more, without a scan of the whole city.
  List<RoadEdge> edgesNear(LatLng p, double withinM) {
    final found = <int>{};
    for (final cell in _cells(p, withinM)) {
      found.addAll(_grid[cell] ?? const []);
    }
    return [for (final i in found.toList()..sort()) edges[i]];
  }

  /// The edges of [edgesNear] whose ends lie close enough for a point within [withinM] of [p]
  /// (Dart only, not twinned): a point on an edge is at most its length from both ends
  /// together, so this skips far edges without decoding their lines.
  Iterable<RoadEdge> edgesWithin(LatLng p, double withinM) =>
      edgesNear(p, withinM).where(
        (e) =>
            distanceBetween(p, at(e.from)) + distanceBetween(p, at(e.to)) <=
            e.lengthM + 2 * withinM,
      );

  /// [edges]' indices by grid cell. A point on an edge is at most half its length from the
  /// middle of its ends (its distances to the ends add up to at most its length), so each edge
  /// sits in the cells around that circle.
  late final Map<(int, int), List<int>> _grid = () {
    final grid = <(int, int), List<int>>{};
    for (final (i, e) in edges.indexed) {
      final a = at(e.from), b = at(e.to);
      final mid = LatLng((a.lat + b.lat) / 2, (a.lon + b.lon) / 2);
      final reachM = max(e.lengthM, distanceBetween(a, b)) / 2 + 1;
      for (final cell in _cells(mid, reachM)) {
        (grid[cell] ??= []).add(i);
      }
    }
    return grid;
  }();

  /// About 220 m of latitude.
  static const double _cellDeg = 0.002;

  /// The grid cells a circle of [radiusM] around [p] touches.
  static Iterable<(int, int)> _cells(LatLng p, double radiusM) sync* {
    final box = Bbox.around(p, radiusM);
    final y0 = (box.minLat / _cellDeg).floor();
    final y1 = (box.maxLat / _cellDeg).floor();
    final x0 = (box.minLon / _cellDeg).floor();
    final x1 = (box.maxLon / _cellDeg).floor();
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        yield (x, y);
      }
    }
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
