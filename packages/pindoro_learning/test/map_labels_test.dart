import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

/// A street from [a] to [b] (degrees off 41.7, 44.8), named [name].
NamedStreet _line(
  String id,
  (double, double) a,
  (double, double) b, {
  String? name,
  String? en,
}) {
  final from = LatLng(41.7 + a.$1, 44.8 + a.$2);
  final to = LatLng(41.7 + b.$1, 44.8 + b.$2);
  return NamedStreet([
    Street(
      id: id,
      nameKa: name ?? id,
      nameEn: en,
      roadClass: 'residential',
      difficulty: Difficulty.expert,
      lengthM: distanceBetween(from, to),
      midpoint: LatLng((from.lat + to.lat) / 2, (from.lon + to.lon) / 2),
      bbox: Bbox.of([from, to]),
      geometry: [
        [from, to],
      ],
    ),
  ]);
}

void main() {
  group('labelStreets', () {
    // The target runs east along 41.7, from 44.79 to 44.81.
    final target = _line('target', (0, -0.01), (0, 0.01));
    final near = _line('near', (-0.002, 0.001), (0.002, 0.001));
    final far = _line('far', (-0.002, 0.009), (0.002, 0.009));
    final parallel = _line('parallel', (0.003, -0.002), (0.003, 0.002));
    final lane = _line('lane', (0.004, -0.006), (0.004, -0.004));
    final away = _line('away', (0.2, 0.2), (0.21, 0.2));

    test('family first, then crossings nearest first, then nearby', () {
      final labels = labelStreets(
        target,
        [away, parallel, far, near, lane, target],
        family: {'lane'},
      );
      expect(
        [for (final l in labels) l.street.id],
        ['lane', 'near', 'far', 'parallel', 'away'],
      );
    });

    test('a crossing is named on its own line, off the junction', () {
      final label = labelStreets(target, [near]).single;
      final junction = LatLng(41.7, 44.8 + 0.001);
      expect(
        distanceBetween(label.at, junction),
        closeTo(LearningConfig.streetLabelOffsetM, 1),
      );
      expect(near.nearest(label.at).distanceM, lessThan(1));
    });

    test('at most streetLabelMax', () {
      final many = [
        for (var i = 0; i < 30; i++)
          _line('s$i', (0.01 + i * 0.001, 0), (0.01 + i * 0.001, 0.001)),
      ];
      expect(
        labelStreets(target, many),
        hasLength(LearningConfig.streetLabelMax),
      );
    });
  });

  group('namesStreet', () {
    final rustaveli = _line(
      'r',
      (0, 0),
      (0, 0.01),
      name: 'შოთა რუსთაველის გამზირი',
      en: 'Shota Rustaveli Avenue',
    );

    test('a place named after the street gives it away', () {
      expect(namesStreet('რუსთაველის მეტრო', rustaveli), isTrue);
      expect(namesStreet('Metro Rustaveli', rustaveli), isTrue);
      expect(namesStreet('რუსთაველი', rustaveli), isTrue);
    });

    test('an unrelated place does not', () {
      expect(namesStreet("Dunkin'", rustaveli), isFalse);
      expect(namesStreet('ვისოლი', rustaveli), isFalse);
      expect(namesStreet('', rustaveli), isFalse);
    });
  });
}
