import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

void main() {
  group('nameStems', () {
    final from = LatLng(41.7, 44.8);
    final to = LatLng(41.7, 44.81);
    final rustaveli = NamedStreet([
      Street(
        id: 'r',
        nameKa: 'შოთა რუსთაველის გამზირი',
        nameEn: 'Shota Rustaveli Avenue',
        roadClass: 'primary',
        difficulty: Difficulty.easy,
        lengthM: distanceBetween(from, to),
        midpoint: LatLng(41.7, 44.805),
        bbox: Bbox.of([from, to]),
        geometry: [
          [from, to],
        ],
      ),
    ]);
    // As the map's place-name filter matches: a stem inside the lower-cased name.
    bool givesAway(String place) =>
        nameStems(rustaveli).any(place.toLowerCase().contains);

    test('a place named after the street gives it away', () {
      expect(givesAway('რუსთაველის მეტრო'), isTrue);
      expect(givesAway('Metro Rustaveli'), isTrue);
      expect(givesAway('რუსთაველი'), isTrue);
    });

    test('an unrelated place does not', () {
      expect(givesAway("Dunkin'"), isFalse);
      expect(givesAway('ვისოლი'), isFalse);
      expect(givesAway(''), isFalse);
    });
  });
}
