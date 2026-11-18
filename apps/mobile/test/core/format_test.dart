import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/l10n/app_localizations.dart';

void main() {
  test('numbers group by three with a narrow no-break space', () {
    expect(formatNumber(0), '0');
    expect(formatNumber(695), '695');
    expect(formatNumber(3555), '3 555');
    expect(formatNumber(1234567), '1 234 567');
  });

  test('Georgian names romanise for Latin search', () {
    expect(latinGeorgian('ვაკე'), 'vake');
    expect(latinGeorgian('სოლოლაკი'), 'sololaki');
    expect(latinGeorgian('ჩუღურეთი'), 'chughureti');
    expect(latinGeorgian('Vake 2'), 'Vake 2');
  });

  final en = lookupAppLocalizations(const Locale('en'));
  final ka = lookupAppLocalizations(const Locale('ka'));

  test('ordinals: English suffixes with the teens, Georgian prefixes', () {
    expect(
      [
        1,
        2,
        3,
        4,
        11,
        12,
        13,
        21,
        22,
        23,
        111,
      ].map((n) => formatOrdinal(n, en)),
      [
        '1st',
        '2nd',
        '3rd',
        '4th',
        '11th',
        '12th',
        '13th',
        '21st',
        '22nd',
        '23rd',
        '111th',
      ],
    );
    expect([1, 2, 30].map((n) => formatOrdinal(n, ka)), [
      '1-ლი',
      'მე-2',
      'მე-30',
    ]);
  });

  test('distances: metres, up to the next 10 m from 100 m, km from 1 km', () {
    expect(formatDistance(84.4, en), '84 m');
    expect(formatDistance(99.6, en), '100 m');
    expect(formatDistance(842, en), '850 m');
    expect(formatDistance(300.2, en), '310 m');
    expect(formatDistance(300, en), '300 m');
    expect(formatDistance(992, en), '1.0 km');
    expect(formatDistance(999.6, en), '1.0 km');
    expect(formatDistance(1234, en), '1.2 km');
    expect(formatDistance(84, ka), '84 მ');
    expect(formatDistance(1234, ka), '1,2 კმ');
  });

  test('area sizes drop a trailing .0 and use one unit for both sides', () {
    expect(formatSize(500, en), '500 m');
    expect(formatSize(1500, en), '1.5 km');
    expect(formatSize(3000, en), '3 km');
    expect(formatSides(2600, 3000, en), '2.6 × 3 km');
    expect(formatSides(2600, 3000, ka), '2,6 × 3 კმ');
  });

  test('download sizes in MB with one decimal, per locale', () {
    expect(formatMegabytes(1_100_000, en), '1.1 MB');
    expect(formatMegabytes(400_000, ka), '0,4 მბ');
  });
}
