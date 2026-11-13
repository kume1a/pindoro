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
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/account/data/account_api.dart';
import 'package:pindoro/features/account/data/account_dao.dart';
import 'package:pindoro/features/account/data/account_data.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_design/pindoro_design.dart';

void main() {
  late AppDatabase db;
  late Directory dir;
  late List<http.Request> sent;
  late http.Response Function(http.Request) reply;

  http.Response session({String? backupAt}) => http.Response(
    jsonEncode({
      'token': 'new-token',
      'account': {'username': 'nino'},
      'backupAt': backupAt,
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
      ('PUT', _) => http.Response(
        jsonEncode({'backupAt': DateTime.now().toUtc().toIso8601String()}),
        200,
      ),
      ('POST', '/v1/accounts') => session(),
      _ => http.Response('', 500),
    };
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1080, 4000)
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
          accountApiProvider.overrideWithValue(
            AccountApi(
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

  Future<void> fill(WidgetTester tester, String username) async {
    await tapThrough(tester, find.text('Back up your progress'));
    await tester.enterText(find.byType(TextField).at(0), username);
    await tester.enterText(find.byType(TextField).at(1), 'correct horse');
    await tester.pump();
  }

  Future<Account?> account(WidgetTester tester) =>
      tester.runAsync<Account?>(() => AccountDao(db).read());

  testWidgets('a new account backs this phone up and shows in Settings', (
    tester,
  ) async {
    await pump(tester);
    await fill(tester, 'ab');
    final create = find.widgetWithText(PindoroButton, 'Create account');
    expect(tester.widget<PindoroButton>(create).onPressed, isNull);
    await tester.enterText(find.byType(TextField).at(0), '  Nino ');
    await tester.pump();
    await tapThrough(tester, create);
    expect(jsonDecode(sent.first.body), {
      'username': 'nino',
      'password': 'correct horse',
    });
    expect(sent.last.method, 'PUT');
    expect(sent.last.headers['authorization'], 'Bearer new-token');
    expect((await account(tester))?.backedUpAt, isNotNull);
    expect(find.text('Signed in as nino'), findsOneWidget);
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
    await fill(tester, 'nino');
    await tapThrough(tester, find.widgetWithText(PindoroButton, 'Sign in'));
    expect(sent.single.url.path, '/v1/sessions');
    expect(find.text('Restore your backup?'), findsOneWidget);
    expect(find.textContaining('from 2 d ago'), findsOneWidget);
    await tapThrough(tester, find.text('Keep this phone’s'));
    expect(sent.last.method, 'PUT');
    expect((await account(tester))?.token, 'new-token');
    expect(find.text('Signed in as nino'), findsOneWidget);
  });

  testWidgets('a wrong password says so and stays signed out', (tester) async {
    reply = (_) => http.Response('', 401);
    await pump(tester);
    await fill(tester, 'nino');
    await tapThrough(tester, find.widgetWithText(PindoroButton, 'Sign in'));
    expect(find.text('Wrong username or password.'), findsOneWidget);
    expect(await account(tester), isNull);
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
