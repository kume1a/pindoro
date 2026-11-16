import 'dart:convert';
import 'dart:io';

import 'package:pindoro_core/pindoro_core.dart';
import 'package:test/test.dart';

Map<String, Object?> _fixture(String name) =>
    jsonDecode(File('../../shared/fixtures/$name').readAsStringSync())
        as Map<String, Object?>;

List<Map<String, Object?>> _cases(Map<String, Object?> f, String key) =>
    (f[key]! as List<Object?>).cast<Map<String, Object?>>();

double _d(Object? v) => (v! as num).toDouble();

LatLng _ll(Object? v) {
  final [lat, lon] = (v! as List<Object?>).map(_d).toList();
  return LatLng(lat, lon);
}

Polyline _line(Object? v) => [for (final p in v! as List<Object?>) _ll(p)];

void main() {
  final scoring = _fixture('scoring_vectors.json');
  final tolerance = _d(scoring['distance_tolerance_m']);

  group('pointToPolylineDistance', () {
    for (final v in _cases(scoring, 'distance')) {
      test(v['name'], () {
        final res = pointToPolylineDistance(_ll(v['point']), [
          for (final line in v['lines']! as List<Object?>) _line(line),
        ]);
        expect(res.distanceMeters, closeTo(_d(v['distance_m']), tolerance));
        expect(
          distanceBetween(res.nearestPoint, _ll(v['nearest'])),
          lessThanOrEqualTo(tolerance),
        );
      });
    }

    test('rejects an empty polyline', () {
      expect(
        () => pointToPolylineDistance(const LatLng(0, 0), []),
        throwsArgumentError,
      );
    });
  });

  group('scoring', () {
    for (final v in _cases(scoring, 'thresholds')) {
      final difficulty = Difficulty.values.byName(v['difficulty']! as String);
      test('thresholds for ${v['road_class']} ${difficulty.name}', () {
        final t = TierThresholds.forStreet(
          v['road_class']! as String,
          difficulty,
        );
        expect(t.perfect, closeTo(_d(v['perfect']), 1e-5));
        expect(t.great, closeTo(_d(v['great']), 1e-5));
        expect(t.close, closeTo(_d(v['close']), 1e-5));
      });
    }

    for (final v in _cases(scoring, 'score')) {
      final difficulty = Difficulty.values.byName(v['difficulty']! as String);
      test(v['name'], () {
        final tier = scoreAnswer(
          _d(v['distance_m']),
          v['road_class']! as String,
          difficulty,
        );
        expect(tier.name, v['tier']);
      });
    }
  });

  group('polyline6', () {
    for (final v in _cases(scoring, 'polyline6')) {
      test(v['name'], () {
        expect(encodePolyline6(_line(v['points'])), v['encoded']);
        expect(decodePolyline6(v['encoded']! as String), _line(v['decoded']));
      });
    }
    for (final v in _cases(scoring, 'polyline6_invalid')) {
      test('rejects ${v['name']}', () {
        expect(
          () => decodePolyline6(v['encoded']! as String),
          throwsFormatException,
        );
      });
    }
  });
}
