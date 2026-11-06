import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';
import 'package:test/test.dart';

const _bounds = Bbox(41.70, 44.70, 41.73, 44.73);

/// A 200 m street called [name] whose midpoint is [at].
Street _street(String id, String name, LatLng at, {double lengthM = 200}) =>
    Street(
      id: id,
      nameKa: name,
      nameEn: null,
      roadClass: 'residential',
      difficulty: Difficulty.expert,
      lengthM: lengthM,
      midpoint: at,
      bbox: Bbox.of([at]),
      geometry: [
        [at],
      ],
    );

/// [perCell] streets in each of the 3 × 3 cells of [_bounds].
List<Street> _grid(int perCell) => [
  for (var row = 0; row < 3; row++)
    for (var col = 0; col < 3; col++)
      for (var i = 0; i < perCell; i++)
        _street(
          's$row$col$i',
          'n$row$col$i',
          LatLng(41.705 + row * 0.01, 44.705 + col * 0.01 + i * 1e-4),
        ),
];

int _cell(LatLng p) =>
    ((p.lat - 41.70) / 0.01).floor() * 3 + ((p.lon - 44.70) / 0.01).floor();

List<String> _pick(
  List<Street> streets, {
  Map<String, StreetKnowledge> knowledge = const {},
  Set<String> recentStreets = const {},
  int seed = 1,
}) {
  final s = QuestionSelector(random: Random(seed)).select(
    streets,
    bounds: _bounds,
    knowledge: knowledge,
    recentStreets: recentStreets,
  );
  return (s as SelectedQuestions).streetIds;
}

void main() {
  test('picks 10 distinct names spread over all 9 cells', () {
    final streets = _grid(3);
    final picked = _pick(streets);
    expect(picked.toSet(), hasLength(10));
    final byId = {for (final s in streets) s.id: s};
    expect(picked.map((id) => _cell(byId[id]!.midpoint)).toSet(), hasLength(9));
  });

  test('never asks the same name twice; one id per name', () {
    final streets = [
      for (final s in _grid(2)) s,
      _street('dup', 'n000', const LatLng(41.725, 44.725), lengthM: 900),
    ];
    final picked = _pick(streets);
    final names = {for (final s in streets) s.id: s.nameKa};
    expect(picked.map((id) => names[id]).toSet(), hasLength(10));
  });

  test('skips names shorter than 150 m in total', () {
    final streets = [
      ..._grid(1),
      _street('short', 'short', const LatLng(41.705, 44.705), lengthM: 100),
      _street('pair-a', 'pair', const LatLng(41.715, 44.715), lengthM: 80),
      _street('pair-b', 'pair', const LatLng(41.716, 44.716), lengthM: 80),
    ];
    final picked = _pick(streets);
    expect(picked, isNot(contains('short')));
    expect(picked.where((id) => id.startsWith('pair')), hasLength(1));
  });

  test('NotEnoughStreets counts the candidates', () {
    final s = QuestionSelector().select(_grid(1), bounds: _bounds);
    expect((s as NotEnoughStreets).count, 9);
  });

  test('within a cell: unknown, then missed, then known; then not recent', () {
    final streets = _grid(4);
    final names = {for (final s in streets) s.id: s.nameKa};
    // In every cell, street 0 is known, 1 missed, 2 unknown but recent,
    // 3 unknown and fresh: the first pass takes each cell's street 3.
    final knowledge = {
      for (final s in streets)
        if (s.id.endsWith('0'))
          s.id: StreetKnowledge.known
        else if (s.id.endsWith('1'))
          s.id: StreetKnowledge.missed,
    };
    final recent = {
      for (final s in streets)
        if (s.id.endsWith('2')) s.id,
    };
    final picked = _pick(streets, knowledge: knowledge, recentStreets: recent);
    expect(picked.take(9).every((id) => id.endsWith('3')), isTrue);
    expect(picked[9], endsWith('2'));
    expect(names.keys, containsAll(picked));
  });

  test('knowledge follows the city-wide street of an in-area part', () {
    final streets = _grid(2);
    final inArea = streets.firstWhere((s) => s.id == 's000');
    // The city knows s000 as part of a longer street with another id.
    final city = NamedStreet([
      _street('city', 'n000', inArea.midpoint, lengthM: 900),
      inArea,
    ]);
    final picked = QuestionSelector(random: Random(1)).select(
      streets,
      bounds: _bounds,
      cityStreets: {'s000': city, 'city': city},
      knowledge: {'city': StreetKnowledge.known},
    );
    final first = (picked as SelectedQuestions).streetIds.take(9);
    expect(first, contains('s001'));
    expect(first, isNot(contains('s000')));
  });

  test('is deterministic for a seeded Random', () {
    final streets = _grid(3);
    expect(_pick(streets, seed: 7), _pick(streets, seed: 7));
  });
}
