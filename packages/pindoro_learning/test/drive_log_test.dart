import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

final _start = DateTime.utc(2026, 11, 20, 9);

DriveFix _fix(
  int s, {
  double lat = 41.7151,
  double lon = 44.7671,
  double? heading,
  double? speed,
  double? accuracy,
}) => (
  at: LatLng(lat, lon),
  t: _start.add(Duration(seconds: s)),
  headingDeg: heading,
  speedMps: speed,
  accuracyM: accuracy,
);

void main() {
  group('track', () {
    test('round-trips position, time, heading, speed and accuracy', () {
      final fixes = [
        _fix(0, heading: 359.9, speed: 0, accuracy: 4.5),
        _fix(1, lat: 41.715134, lon: 44.767218, heading: 12.3, speed: 8.25),
        _fix(3, lat: 41.714901, lon: 44.766002, accuracy: 65),
      ];
      final back = decodeTrack(encodeTrack(fixes));
      expect(back, hasLength(3));
      for (var i = 0; i < 3; i++) {
        expect(back[i].at.lat, closeTo(fixes[i].at.lat, 1e-6));
        expect(back[i].at.lon, closeTo(fixes[i].at.lon, 1e-6));
        expect(back[i].t, fixes[i].t);
        expect(back[i].t.isUtc, isTrue);
      }
      expect(back[0].headingDeg, 359.9);
      expect(back[0].speedMps, 0);
      expect(back[0].accuracyM, 4.5);
      expect(back[1].headingDeg, closeTo(12.3, 0.05));
      expect(back[1].speedMps, 8.25);
      expect(back[1].accuracyM, isNull);
      expect(back[2].headingDeg, isNull);
      expect(back[2].speedMps, isNull);
      expect(back[2].accuracyM, 65);
    });

    test('an empty drive is an empty track', () {
      expect(encodeTrack(const []), isEmpty);
      expect(decodeTrack(''), isEmpty);
    });

    test('a cut-off track is refused', () {
      final text = encodeTrack([_fix(0), _fix(1)]);
      expect(
        () => decodeTrack(text.substring(0, text.length - 1)),
        throwsFormatException,
      );
    });
  });

  group('GPS gaps', () {
    test('fixes every second leave none', () {
      final gaps = gpsGaps(
        [for (var s = 0; s <= 60; s++) _fix(s)],
        _start,
        _start.add(const Duration(seconds: 60)),
      );
      expect(gaps.count, 0);
      expect(gaps.longest, Duration.zero);
    });

    test('a pause up to the threshold is not a gap, past it is', () {
      final gaps = gpsGaps(
        [
          _fix(0),
          _fix(LearningConfig.gpsGapS),
          _fix(LearningConfig.gpsGapS + 40),
        ],
        _start,
        _start.add(Duration(seconds: LearningConfig.gpsGapS + 40)),
      );
      expect(gaps.count, 1);
      expect(gaps.longest, const Duration(seconds: 40));
    });

    test('the wait before the first fix and after the last count', () {
      final gaps = gpsGaps(
        [_fix(30), _fix(31)],
        _start,
        _start.add(const Duration(seconds: 151)),
      );
      expect(gaps.count, 2);
      expect(gaps.longest, const Duration(minutes: 2));
    });

    test('a stale cached first fix leaves no gap', () {
      final gaps = gpsGaps(
        [_fix(-90), for (var s = 1; s <= 30; s++) _fix(s)],
        _start,
        _start.add(const Duration(seconds: 30)),
      );
      expect(gaps.count, 0);
    });

    test('no fix at all is one gap the length of the drive', () {
      final gaps = gpsGaps(
        const [],
        _start,
        _start.add(const Duration(minutes: 5)),
      );
      expect(gaps.count, 1);
      expect(gaps.longest, const Duration(minutes: 5));
    });
  });
}
