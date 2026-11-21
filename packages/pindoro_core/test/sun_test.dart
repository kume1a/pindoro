import 'package:pindoro_core/pindoro_core.dart';
import 'package:test/test.dart';

void main() {
  const tbilisi = LatLng(41.7151, 44.8271);

  test(
    'Tbilisi on 21 November: sunrise about 08:00 and sunset about 17:33 (UTC+4)',
    () {
      expect(isNight(tbilisi, DateTime.utc(2026, 11, 21, 8)), isFalse);
      expect(isNight(tbilisi, DateTime.utc(2026, 11, 21, 3, 30)), isTrue);
      expect(isNight(tbilisi, DateTime.utc(2026, 11, 21, 4, 15)), isFalse);
      expect(isNight(tbilisi, DateTime.utc(2026, 11, 21, 13, 20)), isFalse);
      expect(isNight(tbilisi, DateTime.utc(2026, 11, 21, 13, 50)), isTrue);
    },
  );

  test('the noon sun at the June solstice stands 90° − latitude + 23.4°', () {
    final noon =
        DateTime.utc(2026, 6, 21, 12) // 44.8° E: local noon ~09:00 UTC
            .subtract(const Duration(minutes: 179));
    expect(sunElevationDeg(tbilisi, noon), closeTo(90 - 41.7151 + 23.44, 0.3));
  });
}
