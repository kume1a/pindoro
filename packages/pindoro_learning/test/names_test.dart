import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

NamedStreet _street(String id, String ka, String? en) => NamedStreet([
  Street(
    id: id,
    nameKa: ka,
    nameEn: en,
    roadClass: 'residential',
    difficulty: Difficulty.expert,
    lengthM: 300,
    midpoint: const LatLng(41.7, 44.8),
    bbox: const Bbox(41.7, 44.8, 41.7, 44.8),
    geometry: const [],
  ),
]);

void main() {
  _withoutKindTests();
  final barnovi = _street('b', 'ბარნოვის ქუჩა', 'Barnovi Street');
  final bakhtrioni = _street('k', 'ბახტრიონის ქუჩა', null);
  final chavchavadze = _street(
    'c',
    'ილია ჭავჭავაძის გამზირი',
    'Ilia Chavchavadze Avenue',
  );

  test('Georgian letters read in the national romanisation', () {
    expect(transliterate('ჭავჭავაძის'), 'chavchavadzis');
    expect(nameBase('ბარნოვის ქუჩა'), 'ბარნოვის');
    expect(nameBase('Barnovi St.'), 'barnovi');
  });

  test('a typed name matches within 0.25 of any script (SPEC §5.2)', () {
    expect(nameMatches('Barnovi', barnovi), isTrue);
    expect(nameMatches('barnavi street', barnovi), isTrue);
    expect(nameMatches('ბარნოვის', barnovi), isTrue);
    expect(nameMatches('barnovis kucha', barnovi), isTrue);
    expect(nameMatches('Bakhtrioni', bakhtrioni), isTrue, reason: 'no English');
    expect(nameMatches('Chavchavadze', barnovi), isFalse);
    expect(nameMatches('street', barnovi), isFalse);
  });

  test('the suggestion is the name the typing starts, else none', () {
    final all = [barnovi, bakhtrioni, chavchavadze];
    expect(suggestStreet('Bakhtr', all), bakhtrioni);
    expect(suggestStreet('ილია ჭავ', all), chavchavadze);
    expect(suggestStreet('b', all), isNull);
    expect(suggestStreet('zzzz', all), isNull);
  });
}

void _withoutKindTests() {
  test('a turn prompt drops the kind of street, case kept', () {
    expect(withoutKind('Ilia Chavchavadze Avenue'), 'Ilia Chavchavadze');
    expect(withoutKind('ილია ჭავჭავაძის გამზირი'), 'ილია ჭავჭავაძის');
    expect(withoutKind('Square'), 'Square');
  });
}
