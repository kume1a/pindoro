import 'dart:convert';
import 'dart:io';

import 'package:pindoro_core/pindoro_core.dart';
import 'package:test/test.dart';

void main() {
  final vectors =
      jsonDecode(
            File(
              '../../shared/fixtures/league_vectors.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  List<Map<String, Object?>> cases(String key) =>
      (vectors[key]! as List<Object?>).cast<Map<String, Object?>>();

  group('leagueWeek', () {
    for (final v in cases('week')) {
      test(v['name'], () {
        final week = leagueWeek(DateTime.parse(v['at']! as String));
        expect(week.key, v['key']);
        expect(week.start, DateTime.parse(v['start']! as String));
        expect(week.end, DateTime.parse(v['end']! as String));
      });
    }

    test('a local time gives the same week as its UTC instant', () {
      final at = DateTime.utc(2026, 11, 8, 20);
      expect(leagueWeek(at.toLocal()), leagueWeek(at));
    });
  });

  group('league names', () {
    for (final v in cases('name')) {
      test('"${v['raw']}"', () {
        final name = leagueName(v['raw']! as String);
        expect(name, v['name']);
        expect(isLeagueName(name), v['valid']);
      });
    }
  });
}
