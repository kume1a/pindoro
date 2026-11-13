import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pindoro/core/api_client.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/features/account/data/account_api.dart';
import 'package:pindoro/features/account/data/account_dao.dart';
import 'package:pindoro/features/account/data/account_data.dart';
import 'package:pindoro/features/account/data/backup.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late AppDatabase db;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pindoro-backup-test');
    db = AppDatabase(NativeDatabase.memory());
    await ProgressDao(db).place('tbilisi', [('vake', 1), ('vake', 2)]);
    await AccountDao(db).save(username: 'nino', token: 'old-token');
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  File staged() => File('${dir.path}/pindoro.sqlite.restore');

  test('a snapshot keeps the progress and leaves the token out', () async {
    final backup = await snapshot(db, dir);
    final file = File('${dir.path}/plain.sqlite')
      ..writeAsBytesSync(gzip.decode(backup));
    final raw = sqlite3.open(file.path);
    expect(raw.select('select count(*) c from lesson_result').first['c'], 2);
    expect(raw.select('select count(*) c from account').first['c'], 0);
    raw.close();
    expect(
      utf8.decode(file.readAsBytesSync(), allowMalformed: true),
      isNot(contains('old-token')),
    );
    expect(dir.listSync().map((f) => f.uri.pathSegments.last), [
      'plain.sqlite',
    ]);
  });

  test('a staged restore opens signed in, with the progress', () async {
    final at = DateTime.utc(2026, 11, 12, 9);
    await stageRestore(
      await snapshot(db, dir),
      staged(),
      username: 'nino',
      token: 'new-token',
      backedUpAt: at,
    );
    final restored = AppDatabase(NativeDatabase(staged()));
    final account = await AccountDao(restored).read();
    expect(account?.token, 'new-token');
    expect(account?.backedUpAt?.isAtSameMomentAs(at), isTrue);
    expect(account?.changedAt, isNull);
    expect(await ProgressDao(restored).hasPlayed(), isTrue);
    await restored.close();
  });

  test(
    'a newer, damaged or oversized backup is refused, leaving nothing',
    () async {
      final newer = File('${dir.path}/newer.sqlite');
      sqlite3.open(newer.path)
        ..userVersion = AppDatabase.version + 1
        ..close();
      Uint8List zipped(List<int> bytes) =>
          Uint8List.fromList(gzip.encode(bytes));
      for (final (backup, limit) in [
        (zipped(newer.readAsBytesSync()), maxRestoredBytes),
        (zipped(utf8.encode('not sqlite')), maxRestoredBytes),
        (Uint8List.fromList(utf8.encode('not gzip')), maxRestoredBytes),
        (await snapshot(db, dir), 1024),
      ]) {
        await expectLater(
          stageRestore(
            backup,
            staged(),
            username: 'nino',
            token: 't',
            limit: limit,
          ),
          throwsA(isA<UnreadableBackup>()),
        );
        expect(staged().existsSync(), isFalse);
      }
    },
  );

  group('BackupSync', () {
    late List<http.Request> sent;
    late http.Response Function(http.Request) reply;
    final syncs = <BackupSync>[];

    setUp(() {
      sent = [];
      reply = (_) =>
          http.Response(jsonEncode({'backupAt': '2026-11-13T12:00:00Z'}), 200);
    });

    tearDown(() {
      for (final s in syncs) {
        s.dispose();
      }
      syncs.clear();
    });

    BackupSync start() {
      final sync = BackupSync(
        db: db,
        dao: AccountDao(db),
        api: AccountApi(
          ApiClient(
            'https://api.example',
            client: MockClient((request) async {
              sent.add(request);
              return reply(request);
            }),
          ),
        ),
        databaseFile: () async => File('${dir.path}/pindoro.sqlite'),
      );
      syncs.add(sync);
      return sync;
    }

    test('uploads the gzipped snapshot with the token', () async {
      await AccountDao(db).markChanged(DateTime.now());
      await start().backUp();
      final put = sent.last;
      expect(put.method, 'PUT');
      expect(put.url.path, '/v1/accounts/me/backup');
      expect(put.headers['authorization'], 'Bearer old-token');
      expect(put.bodyBytes.take(2), [0x1f, 0x8b]);
      final account = await AccountDao(db).read();
      expect(account?.backedUpAt, DateTime.utc(2026, 11, 13, 12));
      expect(account?.changedAt, isNull);
    });

    test('uploads at launch what the app last stopped with', () async {
      await AccountDao(db).markChanged(DateTime.now());
      start();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(sent.single.method, 'PUT');
      expect((await AccountDao(db).read())?.changedAt, isNull);
    });

    test(
      'a sign-in elsewhere signs this phone out, keeping the username',
      () async {
        reply = (_) => http.Response('', 401);
        await expectLater(start().backUp(), throwsA(isA<ApiException>()));
        final account = await AccountDao(db).read();
        expect(account?.username, 'nino');
        expect(account?.token, isNull);
        await start().backUp();
        expect(sent, hasLength(1), reason: 'signed out: nothing more goes up');
      },
    );

    test('does nothing without an account', () async {
      await AccountDao(db).drop();
      await start().backUp();
      expect(sent, isEmpty);
    });
  });
}
