import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';
import 'package:test/test.dart';

/// Streets on a 1 km grid, so every pair is ≥ 300 m apart.
List<QuestionCandidate> _grid(int n) => [
  for (var i = 0; i < n; i++)
    QuestionCandidate(
      streetId: 's$i',
      midpoint: LatLng(41.70 + (i ~/ 10) * 0.01, 44.70 + (i % 10) * 0.012),
    ),
];

List<String> _ids(QuestionSelection s) => (s as SelectedQuestions).streetIds;

void main() {
  test('picks 10 distinct streets', () {
    final ids = _ids(QuestionSelector(random: Random(1)).select(_grid(40)));
    expect(ids, hasLength(10));
    expect(ids.toSet(), hasLength(10));
  });

  test('returns NotEnoughStreets when the pool is smaller than 10', () {
    final s = QuestionSelector().select(_grid(9));
    expect(s, isA<NotEnoughStreets>());
    expect((s as NotEnoughStreets).count, 9);
  });

  test('is deterministic for a seeded Random', () {
    final pool = _grid(50);
    expect(
      _ids(QuestionSelector(random: Random(42)).select(pool)),
      _ids(QuestionSelector(random: Random(42)).select(pool)),
    );
  });

  test('excludes recently asked streets', () {
    final pool = _grid(30);
    final recent = {for (var i = 0; i < 20; i++) 's$i'};
    final ids = _ids(
      QuestionSelector(random: Random(3)).select(pool, recentlyAsked: recent),
    );
    expect(ids.toSet().intersection(recent), isEmpty);
  });

  test('falls back to recent streets when too few fresh ones remain', () {
    final pool = _grid(12);
    final recent = {for (var i = 0; i < 5; i++) 's$i'};
    final ids = _ids(QuestionSelector().select(pool, recentlyAsked: recent));
    expect(ids, hasLength(10));
  });

  test('weights unknown x3, missed x2, known x0.5', () {
    const pool = [
      QuestionCandidate(streetId: 'u0', midpoint: LatLng(41.7, 44.7)),
      QuestionCandidate(
        streetId: 'm0',
        midpoint: LatLng(41.8, 44.8),
        knowledge: StreetKnowledge.missed,
      ),
      QuestionCandidate(
        streetId: 'k0',
        midpoint: LatLng(41.9, 44.9),
        knowledge: StreetKnowledge.known,
      ),
    ];
    final selector = QuestionSelector(random: Random(7));
    final counts = <String, int>{};
    const trials = 20000;
    for (var i = 0; i < trials; i++) {
      final id = _ids(selector.select(pool, count: 1)).single;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    expect(counts['u0']! / trials, closeTo(3 / 5.5, 0.02));
    expect(counts['m0']! / trials, closeTo(2 / 5.5, 0.02));
    expect(counts['k0']! / trials, closeTo(0.5 / 5.5, 0.02));
  });

  test('never puts consecutive midpoints closer than 300 m', () {
    // 10 far-apart streets plus 30 clustered within 50 m of the first one.
    final pool = [
      ..._grid(10),
      for (var i = 0; i < 30; i++)
        QuestionCandidate(
          streetId: 'near$i',
          midpoint: LatLng(41.70 + i * 0.00001, 44.70),
        ),
    ];
    for (var seed = 0; seed < 50; seed++) {
      final byId = {for (final c in pool) c.streetId: c.midpoint};
      final ids = _ids(QuestionSelector(random: Random(seed)).select(pool));
      for (var i = 1; i < ids.length; i++) {
        expect(
          distanceBetween(byId[ids[i - 1]]!, byId[ids[i]]!),
          greaterThanOrEqualTo(QuestionSelector.minConsecutiveDistanceM),
          reason: 'seed $seed, ${ids[i - 1]} -> ${ids[i]}',
        );
      }
    }
  });
}
