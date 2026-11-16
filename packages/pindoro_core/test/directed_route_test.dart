import 'dart:convert';
import 'dart:io';

import 'package:pindoro_core/pindoro_core.dart';
import 'package:test/test.dart';

/// `shared/fixtures/directed_route_vectors.json`, which `@pindoro/geo` runs too.
final Map<String, Object?> _v =
    jsonDecode(
          File(
            '../../shared/fixtures/directed_route_vectors.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

List<Map<String, Object?>> _list(Object? v) =>
    (v! as List<Object?>).cast<Map<String, Object?>>();

List<int> _ints(Object? v) => (v! as List<Object?>).cast<int>();

RoadGraph _graph(String name) {
  final g =
      (_v['graphs']! as Map<String, Object?>)[name]! as Map<String, Object?>;
  final junctions = {
    for (final MapEntry(:key, :value)
        in (g['junctions']! as Map<String, Object?>).entries)
      int.parse(key): LatLng(
        ((value! as List<Object?>)[0]! as num).toDouble(),
        ((value as List<Object?>)[1]! as num).toDouble(),
      ),
  };
  return RoadGraph(
    junctions,
    [
      for (final e in _list(g['edges']))
        RoadEdge(
          id: e['id']! as int,
          from: e['from']! as int,
          to: e['to']! as int,
          streetId: 'e${e['id']}',
          lengthM: (e['length_m']! as num).toDouble(),
          line: [junctions[e['from']]!, junctions[e['to']]!],
          oneway: switch (e['oneway']) {
            1 => Oneway.forward,
            -1 => Oneway.backward,
            _ => Oneway.both,
          },
        ),
    ],
    restrictions: [
      for (final r in _list(g['restrictions']))
        (
          fromEdge: r['from_edge']! as int,
          via: r['via']! as int,
          toEdge: r['to_edge']! as int,
          only: r['only']! as bool,
        ),
    ],
  );
}

void main() {
  test('the U-turn penalty matches the vectors', () {
    expect(RoutingConfig.uTurnPenaltyM, _v['u_turn_penalty_m']);
  });

  group('shortestRoute', () {
    for (final v in _list(_v['routes'])) {
      test(v['name'], () {
        final route = _graph(
          v['graph']! as String,
        ).shortestRoute(v['from']! as int, _ints(v['goals']).toSet());
        if (v['edges'] == null) {
          expect(route, isNull);
          return;
        }
        expect(route!.edges.map((e) => e.id), _ints(v['edges']));
        expect(route.junctions, _ints(v['junctions']));
        expect(route.lengthM, (v['length_m']! as num).toDouble());
        expect(route.costM, (v['cost_m']! as num).toDouble());
      });
    }
  });

  group('legalExits', () {
    for (final v in _list(_v['exits'])) {
      test(v['name'], () {
        final graph = _graph(v['graph']! as String);
        final approach = switch (v['approach']) {
          final int id => graph.edges.firstWhere((e) => e.id == id),
          _ => null,
        };
        expect(
          graph
              .legalExits(v['junction']! as int, approach: approach)
              .map((e) => e.id),
          _ints(v['exits']),
        );
      });
    }
  });

  test('allowing: a reported one-way drives both ways, a reported turn '
      'passes its restriction (an only_* one dropped)', () {
    final oneway = _graph('oneway');
    expect(oneway.canDrive(oneway.edges.first, 1), isFalse);
    final open = oneway.allowing(twoWay: {1});
    expect(open.canDrive(open.edges.first, 1), isTrue);
    expect(open.edges.first.line, oneway.edges.first.line);

    final noLeft = _graph('no_left_turn');
    final approach = noLeft.edges.first;
    Iterable<int> exits(RoadGraph g) =>
        g.legalExits(2, approach: g.edges.first).map((e) => e.id);
    expect(exits(noLeft), isNot(contains(2)));
    expect(exits(noLeft.allowing(allowed: {(approach.id, 2, 2)})), contains(2));
    expect(
      exits(noLeft.allowing(allowed: {(approach.id, 2, 3)})),
      isNot(contains(2)),
    );

    final only = _graph('only_straight_on');
    expect(exits(only), [4]);
    expect(exits(only.allowing(allowed: {(1, 2, 3)})), containsAll([2, 3, 4]));
  });

  test('a pack row reads its one-way and a connector has no street', () {
    final row = {
      'id': 1,
      'from_junction': 1,
      'to_junction': 2,
      'street_id': null,
      'length_m': 10,
      'geometry': encodePolyline6(const [
        LatLng(41.7, 44.8),
        LatLng(41.7, 44.9),
      ]),
    };
    expect(RoadEdge.fromRow(row).oneway, Oneway.both);
    expect(RoadEdge.fromRow(row).streetId, isNull);
    expect(RoadEdge.fromRow({...row, 'oneway': 1}).oneway, Oneway.forward);
    expect(RoadEdge.fromRow({...row, 'oneway': -1}).oneway, Oneway.backward);
    final graph = RoadGraph(
      {1: const LatLng(41.7, 44.8), 2: const LatLng(41.7, 44.9)},
      [
        RoadEdge.fromRow({...row, 'oneway': 1}),
      ],
    );
    expect(graph.junctionsOfPart('s'), isEmpty);
    expect(graph.shortestRoute(2, {1}), isNull);
    expect(graph.shortestRoute(1, {2})!.edges, hasLength(1));
  });
}
