import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pindoro/core/location.dart';

void main() {
  Position position({
    required double heading,
    required double speed,
    bool measured = true,
  }) => Position(
    latitude: 41.7,
    longitude: 44.8,
    timestamp: DateTime.utc(2026, 11, 22),
    accuracy: measured ? 5 : 0,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: heading,
    headingAccuracy: 0,
    speed: speed,
    speedAccuracy: 0,
    hasAccuracy: measured,
    hasHeading: measured,
    hasSpeed: measured,
  );

  test('a drive fix keeps what was measured', () {
    final fix = driveFixOf(position(heading: 90, speed: 12));
    expect(fix.headingDeg, 90);
    expect(fix.speedMps, 12);
    expect(fix.accuracyM, 5);
  });

  test('Android\'s 0 for an unmeasured heading, speed or accuracy is none, '
      'not north and standing still', () {
    final fix = driveFixOf(position(heading: 0, speed: 0, measured: false));
    expect(fix.headingDeg, isNull);
    expect(fix.speedMps, isNull);
    expect(fix.accuracyM, isNull);
  });

  test('iOS\'s -1 for an invalid course or speed is none', () {
    final fix = driveFixOf(position(heading: -1, speed: -1));
    expect(fix.headingDeg, isNull);
    expect(fix.speedMps, isNull);
  });
}
