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

  test('the search lists streets and places by name, best first', () {
    final all = [barnovi, bakhtrioni, chavchavadze];
    expect(searchNames('Ba', all, nameForms), [barnovi, bakhtrioni]);
    expect(searchNames('Bakhtr', all, nameForms), [bakhtrioni]);
    expect(searchNames('b', all, nameForms), isEmpty);
    final places = [('ლისის ტბა', 'Lisi Lake'), ('ვაკის პარკი', 'Vake Park')];
    expect(searchNames('lisi', places, (p) => placeForms(p.$1, p.$2)), [
      places.first,
    ]);
  });

  test("a chain's branches tie and keep the order given (nearest first, as "
      'the app sorts them); far-off names are left out', () {
    final places = [
      ('far', placeForms('ნიკორა', 'Nikora')),
      ('near', placeForms('ნიკორა', 'Nikora')),
      ('other', placeForms('კარფური', 'Carrefour')),
      ('slip', placeForms('ნიკორა XL', null)),
    ];
    expect(searchNames('nikora', places, (p) => p.$2).map((p) => p.$1), [
      'far',
      'near',
      'slip',
    ]);
    expect(searchNames('nikorra', places, (p) => p.$2), hasLength(3));
  });

  test('the search finds a name by any of its words, in either script, in '
      'any order and with a slip', () {
    final kazbegi = _street(
      'z',
      'ალექსანდრე ყაზბეგის გამზირი',
      'Aleksandre Kazbegi Avenue',
    );
    final lane = _street(
      'l',
      'ივანე ბერიტაშვილის III შესახვევი',
      'Ivane Beritashvili 3rd Lane',
    );
    final all = [barnovi, bakhtrioni, chavchavadze, kazbegi, lane];
    expect(searchNames('Kazbegi', all, nameForms), [kazbegi]);
    expect(searchNames('kazbegi ave', all, nameForms), [kazbegi]);
    expect(searchNames('ყაზბეგი', all, nameForms), [kazbegi]);
    expect(searchNames('qazbegis', all, nameForms), [kazbegi]);
    expect(searchNames('chavchavadze', all, nameForms), [chavchavadze]);
    expect(searchNames('chavchavadze ilia', all, nameForms), [chavchavadze]);
    expect(searchNames('chavchavaze', all, nameForms), [chavchavadze]);
    expect(searchNames('beritashvili 3', all, nameForms), [lane]);
    expect(searchNames('kazbegi barnovi', all, nameForms), isEmpty);
  });
}

void _withoutKindTests() {
  test('a turn prompt drops the kind of street, case kept', () {
    expect(withoutKind('Ilia Chavchavadze Avenue'), 'Ilia Chavchavadze');
    expect(withoutKind('ილია ჭავჭავაძის გამზირი'), 'ილია ჭავჭავაძის');
    expect(withoutKind('Square'), 'Square');
    expect(withoutKind('Paliashvili Street'), 'Paliashvili');
  });

  test('the drive screens shorten the kind of street', () {
    expect(shortKind('Ilia Chavchavadze Avenue'), 'Ilia Chavchavadze Ave');
    expect(shortKind('Paliashvili Street'), 'Paliashvili St');
    expect(shortKind('ილია ჭავჭავაძის გამზირი'), 'ილია ჭავჭავაძის გამზ.');
    expect(shortKind('Avenueview Road'), 'Avenueview Rd');
  });
}
