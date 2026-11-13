import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
    final staged = File('${dir.path}/pindoro.sqlite.restore');
    final at = DateTime.utc(2026, 11, 12, 9);
    await stageRestore(
      await snapshot(db, dir),
      staged,
      username: 'nino',
      token: 'new-token',
      backedUpAt: at,
    );
    final restored = AppDatabase(NativeDatabase(staged));
    final account = await AccountDao(restored).read();
    expect(account?.token, 'new-token');
    expect(account?.backedUpAt?.isAtSameMomentAs(at), isTrue);
    expect(await ProgressDao(restored).hasPlayed(), isTrue);
    await restored.close();
  });

  test('a newer or damaged backup is refused and leaves nothing', () async {
    final staged = File('${dir.path}/pindoro.sqlite.restore');
    final newer = File('${dir.path}/newer.sqlite');
    sqlite3.open(newer.path)
      ..userVersion = AppDatabase.version + 1
      ..close();
    for (final backup in [
      Uint8List.fromList(gzip.encode(newer.readAsBytesSync())),
      Uint8List.fromList(gzip.encode(utf8.encode('not sqlite'))),
      Uint8List.fromList(utf8.encode('not gzip')),
    ]) {
      await expectLater(
        stageRestore(backup, staged, username: 'nino', token: 't'),
        throwsA(isA<UnreadableBackup>()),
      );
      expect(staged.existsSync(), isFalse);
    }
  });

  group('BackupSync', () {
    late List<http.Request> sent;
    late http.Response Function(http.Request) reply;
    late BackupSync sync;

    setUp(() {
      sent = [];
      reply = (_) =>
          http.Response(jsonEncode({'backupAt': '2026-11-13T12:00:00Z'}), 200);
      sync = BackupSync(
        db: db,
        dao: AccountDao(db),
        api: AccountApi(
          'https://api.example',
          client: MockClient((request) async {
            sent.add(request);
            return reply(request);
          }),
        ),
        databaseFile: () async => File('${dir.path}/pindoro.sqlite'),
      );
    });

    tearDown(() => sync.dispose());

    test('uploads the gzipped snapshot with the token', () async {
      await sync.backUp();
      final put = sent.single;
      expect(put.method, 'PUT');
      expect(put.url.path, '/v1/accounts/me/backup');
      expect(put.headers['authorization'], 'Bearer old-token');
      expect(put.headers['content-type'], 'application/octet-stream');
      expect(put.bodyBytes.take(2), [0x1f, 0x8b]);
      final account = await AccountDao(db).read();
      expect(account?.backedUpAt, DateTime.utc(2026, 11, 13, 12));
    });

    test('an unknown token signs this phone out', () async {
      reply = (_) => http.Response('', 401);
      await expectLater(sync.backUp(), throwsA(anything));
      expect(await AccountDao(db).read(), isNull);
    });

    test('does nothing while signed out', () async {
      await AccountDao(db).drop();
      await sync.backUp();
      expect(sent, isEmpty);
    });
  });
}
