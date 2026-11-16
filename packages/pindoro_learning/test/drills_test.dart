import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

final _now = DateTime(2026, 3, 2, 9);

/// A street from [a] to [b] (degrees off 41.7, 44.8).
NamedStreet _line(String id, (double, double) a, (double, double) b) {
  final from = LatLng(41.7 + a.$1, 44.8 + a.$2);
  final to = LatLng(41.7 + b.$1, 44.8 + b.$2);
  return NamedStreet([
    Street(
      id: id,
      nameKa: id,
      nameEn: null,
      roadClass: 'secondary',
      difficulty: Difficulty.expert,
      lengthM: distanceBetween(from, to),
      midpoint: LatLng((from.lat + to.lat) / 2, (from.lon + to.lon) / 2),
      bbox: Bbox.of([from, to]),
      geometry: [
        [from, to],
      ],
      tier: StreetTier.b,
    ),
  ]);
}

CardState _card(String id, double stability) => CardState(
  itemId: CardType.p.item(id),
  phase: CardPhase.review,
  memory: Memory(
    stability: stability,
    difficulty: 5,
    lastReview: _now.subtract(const Duration(days: 2)),
  ),
  dueAt: _now.add(const Duration(days: 30)),
  lastRating: Rating.good,
  priorKnown: true,
);

void main() {
  // An avenue running east crossed by five streets 200 m apart.
  final avenue = _line('avenue', (0, 0), (0, 0.015));
  final crossing = [
    for (var i = 1; i <= 5; i++)
      _line('x$i', (-0.002, 0.0024 * i), (0.002, 0.0024 * i)),
  ];
  final streets = {avenue, ...crossing};
  final curriculum = Curriculum(
    streets: streets,
    districts: const [],
    centre: const LatLng(41.7, 44.8),
  );

  CrossingsDrill? drill(Map<String, CardState> cards, {int seed = 1}) =>
      crossingsDrill(
        curriculum: curriculum,
        streets: streets,
        cards: cards,
        now: _now,
        random: Random(seed),
      );

  test('the crossings drill asks the Known streets after the first, in '
      'order', () {
    final cards = {
      'avenue': _card('avenue', 30),
      for (final s in crossing) s.id: _card(s.id, 10),
    };
    final ids = [for (final s in crossing) s.id];
    final d = drill(cards)!;
    expect(d.streetId, 'avenue');
    final order = d.fromId == 'x1' ? ids : ids.reversed.toList();
    expect(d.fromId, order.first);
    expect(d.crossings, order.skip(1).take(LearningConfig.crossingsMax));
  });

  test('it needs a Solid street and two Known crossings', () {
    expect(
      drill({
        'avenue': _card('avenue', 10),
        for (final s in crossing) s.id: _card(s.id, 10),
      }),
      isNull,
      reason: 'the avenue is not Solid',
    );
    expect(
      drill({'avenue': _card('avenue', 30), 'x2': _card('x2', 10)}),
      isNull,
    );
  });

  test('planDrills skips the crossings once today has one', () {
    final cards = {
      'avenue': _card('avenue', 30),
      for (final s in crossing) s.id: _card(s.id, 10),
    };
    Drills plan(List<LogEntry> today) => planDrills(
      curriculum: curriculum,
      streets: streets,
      cards: cards,
      today: today,
      centre: const LatLng(41.7, 44.8),
      now: _now,
      seed: 1,
    );
    expect(plan(const []).crossings, isNotNull);
    expect(
      plan([
        LogEntry(
          ts: _now,
          itemId: 'P:x2',
          format: ReviewFormat.crossings,
          rating: Rating.good,
          source: ReviewSource.session,
        ),
      ]).crossings,
      isNull,
    );
  });
}
