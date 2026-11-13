import 'dart:convert';
import 'dart:io';

import 'package:pindoro_core/pindoro_core.dart';
import 'package:test/test.dart';

void main() {
  final vectors =
      jsonDecode(
            File(
              '../../shared/fixtures/account_vectors.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  List<Map<String, Object?>> cases(String key) =>
      (vectors[key]! as List<Object?>).cast<Map<String, Object?>>();

  group('usernames', () {
    for (final v in cases('username')) {
      test('"${v['raw']}"', () {
        final username = tidyUsername(v['raw']! as String);
        expect(username, v['username']);
        expect(isUsername(username), v['valid']);
      });
    }
  });

  group('passwords', () {
    for (final v in cases('password')) {
      test('"${v['password']}"', () {
        expect(isPassword(v['password']! as String), v['valid']);
      });
    }
  });

  group('recovery codes', () {
    for (final v in cases('recoveryCode')) {
      test('"${v['raw']}"', () {
        final code = tidyRecoveryCode(v['raw']! as String);
        expect(code, v['code']);
        expect(isRecoveryCode(code), v['valid']);
      });
    }

    test('show in dashed groups of four', () {
      expect(groupRecoveryCode('abcdefghjkmnpqrs'), 'abcd-efgh-jkmn-pqrs');
    });
  });
}
