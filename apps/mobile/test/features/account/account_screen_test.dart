import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pindoro/app/app.dart';
import 'package:pindoro/core/api_client.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/database_file.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/account/data/account_dao.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_design/pindoro_design.dart';

const _code = 'abcdefghjkmnpqrs';

void main() {
  late AppDatabase db;
  late Directory dir;
  late List<http.Request> sent;
  late http.Response Function(http.Request) reply;

  http.Response session({String? backupAt, String? recoveryCode}) =>
      http.Response(
        jsonEncode({
          'token': 'new-token',
          'account': {'username': 'nino'},
          'backupAt': backupAt,
          'recoveryCode': ?recoveryCode,
        }),
        200,
      );

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    dir = Directory.systemTemp.createTempSync('pindoro-account-test');
    sent = [];
    reply = (request) => switch ((request.method, request.url.path)) {
      ('PUT', '/v1/accounts/me/backup') => http.Response(
        jsonEncode({'backupAt': DateTime.now().toUtc().toIso8601String()}),
        200,
      ),
      ('POST', _) => session(recoveryCode: _code),
      _ => http.Response('', 204),
    };
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1080, 4800)
      ..devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          pindoroMapBuilderProvider.overrideWithValue((_) => const SizedBox()),
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
        ],
        child: const PindoroApp(initialLocation: Routes.settings),
      ),
    );
    await settle(tester);
  }

  Future<void> type(WidgetTester tester, List<String> fields) async {
    for (final (i, text) in fields.indexed) {
      await tester.enterText(find.byType(TextField).at(i), text);
    }
    await tester.pump();
  }

  Future<Account?> account(WidgetTester tester) =>
      tester.runAsync<Account?>(() => AccountDao(db).read());

  testWidgets('a new account shows its recovery code once, then backs up', (
    tester,
  ) async {
    await pump(tester);
    await tapThrough(tester, find.text('Back up your progress'));
    await type(tester, ['ab', 'correct horse']);
    final create = find.widgetWithText(PindoroButton, 'Create account');
    expect(tester.widget<PindoroButton>(create).onPressed, isNull);
    await type(tester, ['  Nino ', 'correct horse']);
    await tapThrough(tester, create);
    expect(jsonDecode(sent.first.body), {
      'username': 'nino',
      'password': 'correct horse',
    });
    expect(find.text('Save your recovery code'), findsOneWidget);
    expect(find.textContaining('abcd-efgh-jkmn-pqrs'), findsOneWidget);
    await tapThrough(tester, find.text('I saved it'));
    expect(sent.last.method, 'PUT');
    expect(find.text('Signed in as nino'), findsOneWidget);
    expect(find.text('Change password'), findsOneWidget);
  });

  testWidgets('signing in on a phone with progress asks first; keep uploads', (
    tester,
  ) async {
    await tester.runAsync(
      () => ProgressDao(db).place('tbilisi', [('vake', 1)]),
    );
    final at = DateTime.now().subtract(const Duration(days: 2)).toUtc();
    reply = (request) => request.method == 'POST'
        ? session(backupAt: at.toIso8601String())
        : http.Response(
            jsonEncode({'backupAt': DateTime.now().toUtc().toIso8601String()}),
            200,
          );
    await pump(tester);
    await tapThrough(tester, find.text('Back up your progress'));
    await type(tester, ['nino', 'correct horse']);
    await tapThrough(tester, find.widgetWithText(PindoroButton, 'Sign in'));
    expect(sent.single.url.path, '/v1/sessions');
    expect(find.textContaining('from 2 d ago'), findsOneWidget);
    await tapThrough(tester, find.text('Keep this phone’s'));
    expect(sent.last.method, 'PUT');
    expect((await account(tester))?.token, 'new-token');
    expect(find.text('Signed in as nino'), findsOneWidget);
  });

  testWidgets('a wrong password says so and stays signed out', (tester) async {
    reply = (_) => http.Response('', 401);
    await pump(tester);
    await tapThrough(tester, find.text('Back up your progress'));
    await type(tester, ['nino', 'correct horse']);
    await tapThrough(tester, find.widgetWithText(PindoroButton, 'Sign in'));
    expect(find.text('Wrong username or password.'), findsOneWidget);
    expect(await account(tester), isNull);
  });

  testWidgets('a forgotten password resets with the recovery code', (
    tester,
  ) async {
    await pump(tester);
    await tapThrough(tester, find.text('Back up your progress'));
    await tapThrough(tester, find.text('Forgot password?'));
    await type(tester, ['nino', 'ABCD EFGH JKMN PQRS', 'new password']);
    await tapThrough(
      tester,
      find.widgetWithText(PindoroButton, 'Set new password'),
    );
    expect(jsonDecode(sent.first.body), {
      'username': 'nino',
      'recoveryCode': _code,
      'password': 'new password',
    });
    expect(find.text('Save your recovery code'), findsOneWidget);
    await tapThrough(tester, find.text('I saved it'));
    expect(find.text('Signed in as nino'), findsOneWidget);
  });

  testWidgets('signed out by another phone, Settings says so and keeps the '
      'username for signing in', (tester) async {
    await tester.runAsync(() async {
      final dao = AccountDao(db);
      await dao.save(username: 'nino', token: 't');
      await dao.signedOutElsewhere();
    });
    await pump(tester);
    expect(find.text('Signed out on this phone'), findsOneWidget);
    await tapThrough(tester, find.text('Signed out on this phone'));
    expect(find.text('nino'), findsOneWidget);
  });

  testWidgets('sign out and delete ask first', (tester) async {
    await tester.runAsync(
      () => AccountDao(db).save(username: 'nino', token: 't'),
    );
    await pump(tester);
    await tapThrough(tester, find.text('Delete account'));
    expect(find.text('Delete your account?'), findsOneWidget);
    await tapThrough(tester, find.text('Keep account'));
    expect(sent, isEmpty);
    await tapThrough(tester, find.text('Sign out'));
    await tapThrough(tester, find.widgetWithText(PindoroButton, 'Sign out'));
    expect(sent.single.url.path, '/v1/sessions/me');
    expect(await account(tester), isNull);
    expect(find.text('Back up your progress'), findsOneWidget);
  });
}

Future<void> tapThrough(WidgetTester tester, Finder target) async {
  await tester.runAsync(() async {
    await tester.tap(target);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await settle(tester);
}

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}
