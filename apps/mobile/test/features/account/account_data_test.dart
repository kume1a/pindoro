import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pindoro/core/api_client.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/database_file.dart';
import 'package:pindoro/core/restart.dart';
import 'package:pindoro/features/account/data/account_api.dart';
import 'package:pindoro/features/account/data/account_dao.dart';
import 'package:pindoro/features/account/data/account_data.dart';
import 'package:pindoro/features/account/data/backup.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';

void main() {
  late Directory dir;
  late AppDatabase db;
  late List<http.Request> sent;
  late http.Response Function(http.Request) reply;
  late List<File> restarts;
  late ProviderContainer container;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pindoro-account-test');
    db = AppDatabase(NativeDatabase.memory());
    sent = [];
    restarts = [];
    reply = (request) => switch ((request.method, request.url.path)) {
      ('PUT', '/v1/accounts/me/backup') => http.Response(
        jsonEncode({'backupAt': '2026-11-13T12:00:00Z'}),
        200,
      ),
      _ => http.Response('', 204),
    };
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        databaseFileProvider.overrideWithValue(
          () async => File('${dir.path}/pindoro.sqlite'),
        ),
        apiClientProvider.overrideWithValue(
          ApiClient(
            'https://api.example',
            client: MockClient((request) async {
              sent.add(request);
              return reply(request);
            }),
          ),
        ),
        restartProvider.overrideWithValue((restored) async {
          restarts.add(restored);
        }),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    await dir.delete(recursive: true);
  });

  AccountActions actions() => container.read(accountActionsProvider);
  AccountDao dao() => container.read(accountDaoProvider);

  Session session({DateTime? backupAt}) => (
    username: 'nino',
    token: 'new-token',
    backupAt: backupAt,
    recoveryCode: null,
  );

  final yesterday = DateTime.utc(2026, 11, 12);

  Future<bool?> neverAsked(DateTime _) => fail('asked about a restore');

  test('no backup yet: this phone signs in and goes up', () async {
    await actions().takeOver(session(), askRestore: neverAsked);
    final account = await dao().read();
    expect(account?.token, 'new-token');
    expect(account?.backedUpAt, DateTime.utc(2026, 11, 13, 12));
    expect(sent.single.method, 'PUT');
  });

  test('a phone without progress restores without asking', () async {
    final backup = await snapshot(db, dir);
    reply = (_) => http.Response.bytes(backup, 200);
    await actions().takeOver(
      session(backupAt: yesterday),
      askRestore: neverAsked,
    );
    final restored = AppDatabase(NativeDatabase(restarts.single));
    expect((await AccountDao(restored).read())?.token, 'new-token');
    await restored.close();
    expect(await dao().read(), isNull, reason: 'this database is replaced');
  });

  group('a phone with progress', () {
    setUp(() => ProgressDao(db).place('tbilisi', [('vake', 1)]));

    test('keeps its own when the player says so', () async {
      DateTime? asked;
      await actions().takeOver(
        session(backupAt: yesterday),
        askRestore: (at) async {
          asked = at;
          return false;
        },
      );
      expect(asked, yesterday);
      expect(restarts, isEmpty);
      expect((await dao().read())?.token, 'new-token');
      expect(sent.single.method, 'PUT');
    });

    test('saves nothing when the question goes unanswered', () async {
      await expectLater(
        actions().takeOver(
          session(backupAt: yesterday),
          askRestore: (_) async => null,
        ),
        throwsA(isA<SignInGivenUp>()),
      );
      expect(await dao().read(), isNull);
      expect(sent, isEmpty);
    });
  });

  test('signing out offline still signs this phone out', () async {
    await dao().save(username: 'nino', token: 't');
    reply = (_) => throw http.ClientException('down');
    await actions().signOut();
    expect(await dao().read(), isNull);
  });

  test('a token another phone replaced signs this one out', () async {
    await dao().save(username: 'nino', token: 't');
    reply = (_) => http.Response('', 401);
    await expectLater(actions().delete(), throwsA(isA<ApiException>()));
    final account = await dao().read();
    expect(account?.username, 'nino');
    expect(account?.token, isNull);
  });
}
