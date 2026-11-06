import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/app/format.dart';

void main() {
  test('numbers group by three with a narrow no-break space', () {
    expect(formatNumber(0), '0');
    expect(formatNumber(695), '695');
    expect(formatNumber(3555), '3 555');
    expect(formatNumber(1234567), '1 234 567');
  });

  test('distances: metres under 1 km, else km with one decimal', () {
    const en = Locale('en'), ka = Locale('ka');
    expect(formatDistance(84.4, en), '84 m');
    expect(formatDistance(999.4, en), '999 m');
    expect(formatDistance(999.6, en), '1.0 km');
    expect(formatDistance(1234, en), '1.2 km');
    expect(formatDistance(84, ka), '84 მ');
    expect(formatDistance(1234, ka), '1,2 კმ');
  });

  test('area sizes drop a trailing .0 and use one unit for both sides', () {
    const en = Locale('en'), ka = Locale('ka');
    expect(formatSize(500, en), '500 m');
    expect(formatSize(1500, en), '1.5 km');
    expect(formatSize(3000, en), '3 km');
    expect(formatSides(2600, 3000, en), '2.6 × 3 km');
    expect(formatSides(2600, 3000, ka), '2,6 × 3 კმ');
  });
}
