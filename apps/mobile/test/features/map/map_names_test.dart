import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/features/map/data/map_style.dart';

void main() {
  const base = ['has', 'name'];

  test('no names hides both name layers', () {
    const none = MapNames();
    expect(none.roadFilter(base), isNull);
    expect(none.placeFilter(base), isNull);
  });

  test('all names keep the style filters', () {
    expect(MapNames.all.roadFilter(base), base);
    expect(MapNames.all.placeFilter(base), ['all', base]);
  });

  test('named streets and hidden stems narrow the style filters', () {
    const names = MapNames(
      streets: {'ვაჟა-ფშაველას გამზირი'},
      places: true,
      placesNot: {'rusta'},
    );
    expect(names.roadFilter(base), [
      'all',
      base,
      [
        'in',
        ['get', 'name'],
        [
          'literal',
          ['ვაჟა-ფშაველას გამზირი'],
        ],
      ],
    ]);
    expect(
      (names.placeFilter(base)! as List).skip(2),
      hasLength(2),
      reason: 'the stem is checked in the local and the English name',
    );
  });

  test('equal by content, so a rebuild does not touch the map', () {
    expect(
      MapNames(streets: {'a'}, placesNot: {'b'}),
      MapNames(streets: {'a'}, placesNot: {'b'}),
    );
    expect(MapNames.all, isNot(const MapNames()));
    expect(MapNames.everything, isNot(MapNames.all));
  });

  test('every place names every street and place, as all names do', () {
    expect(MapNames.everything.everyPlace, isTrue);
    expect(MapNames.all.everyPlace, isFalse);
    expect(MapNames.everything.roadFilter(base), base);
    expect(MapNames.everything.placeFilter(base), ['all', base]);
  });
}
