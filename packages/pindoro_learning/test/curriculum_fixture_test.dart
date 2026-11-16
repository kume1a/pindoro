import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

const _fixture =
    '../../apps/mobile/assets/packs_fixture/tbilisi_vake_fixture.sqlite';

/// The bundled Vake pack's curriculum.
Curriculum _vake() {
  final db = sqlite3.open(_fixture, mode: OpenMode.readOnly);
  try {
    final neighbours = <String, Set<String>>{};
    for (final r in db.select('SELECT chunk_a, chunk_b FROM chunk_neighbour')) {
      neighbours
          .putIfAbsent(r['chunk_a'] as String, () => {})
          .add(r['chunk_b'] as String);
    }
    return Curriculum(
      streets: streetsByPartId([
        for (final r in db.select('SELECT * FROM street')) Street.fromRow(r),
      ]).values,
      districts: [
        for (final r in db.select('SELECT * FROM district'))
          District.fromRow(r),
      ],
      centre: City.fromRow(db.select('SELECT * FROM city').first).center,
      families: [
        for (final r in db.select('SELECT * FROM family')) familyLinkFromRow(r),
      ],
      chunkNeighbours: neighbours,
    );
  } finally {
    db.close();
  }
}

/// A card introduced on [introAt] whose stability grows by 2 days a day.
CardState _card(String street, DateTime introAt, DateTime now) {
  final days = now.difference(introAt).inDays;
  return CardState(
    itemId: CardType.p.item(street),
    phase: CardPhase.review,
    memory: Memory(
      stability: 2.31 + 2.0 * days,
      difficulty: 5,
      lastReview: now,
    ),
    lastRating: Rating.good,
    introAt: introAt,
  );
}

void main() {
  test(
    '120 days of Vake at 10 new streets a day keep the curriculum rules',
    () {
      final curriculum = _vake();
      final introduced = <String, DateTime>{};
      var days = 0;
      for (var day = 0; day < 120; day++) {
        final now = DateTime(2026, 3, 2, 9).add(Duration(days: day));
        final cards = {
          for (final MapEntry(:key, :value) in introduced.entries)
            key: _card(key, value, now),
        };
        final picks = curriculum.next(cards: cards, now: now, count: 10);
        if (picks.isEmpty) break;
        days++;
        expect(curriculum.next(cards: cards, now: now, count: 10), picks);
        expect(picks.toSet(), hasLength(picks.length));
        expect(picks.where(introduced.containsKey), isEmpty);
        final siblings = <String, int>{};
        for (final id in picks) {
          final parent = curriculum.parentOf(id);
          if (parent == null) continue;
          expect(
            cards[parent]?.memory?.stability,
            greaterThanOrEqualTo(LearningConfig.childParentMinDays),
            reason: '$id before its parent $parent',
          );
          siblings[parent] = (siblings[parent] ?? 0) + 1;
        }
        expect(
          siblings.values.every((n) => n <= LearningConfig.maxSiblingsPerDay),
          isTrue,
        );
        for (final id in picks) {
          introduced[id] = now;
        }
      }
      expect(days, greaterThan(30), reason: 'Vake teaches for weeks');
    },
  );
}
