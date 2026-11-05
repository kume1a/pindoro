import 'dart:convert';

import 'package:pindoro_core/pindoro_core.dart';
import 'package:test/test.dart';

void main() {
  const a = [LatLng(41.71, 44.75), LatLng(41.712, 44.752)];
  const b = [LatLng(41.72, 44.76), LatLng(41.721, 44.761)];

  test('Street.fromRow maps pack columns', () {
    final street = Street.fromRow({
      'id': '0193a5d2-0000-7000-8000-000000000001',
      'name_ka': 'ილია ჭავჭავაძის გამზირი',
      'name_en': null,
      'road_class': 'primary',
      'difficulty': 'easy',
      'length_m': 2400,
      'mid_lat': 41.71,
      'mid_lon': 44.75,
      'min_lat': 41.71,
      'min_lon': 44.75,
      'max_lat': 41.721,
      'max_lon': 44.761,
      'geometry': jsonEncode([encodePolyline6(a), encodePolyline6(b)]),
    });
    expect(street.difficulty, Difficulty.easy);
    expect(street.nameEn, isNull);
    expect(street.lengthM, 2400.0);
    expect(street.geometry, [a, b]);
  });

  test('decodeMultipolygon6 keeps polygons and rings apart', () {
    final ring = encodePolyline6([...a, ...b, a.first]);
    expect(
      decodeMultipolygon6(
        jsonEncode([
          [ring, ring],
          [ring],
        ]),
      ),
      hasLength(2),
    );
    expect(
      decodeMultipolygon6(
        jsonEncode([
          [ring, ring],
        ]),
      ).single,
      hasLength(2),
    );
  });
}
