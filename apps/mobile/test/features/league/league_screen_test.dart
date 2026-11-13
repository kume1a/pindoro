import 'dart:convert';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pindoro/app/app.dart';
import 'package:pindoro/core/api_client.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/league/data/league_dao.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// `count` members; the player is [you] (a rank), XP falling by 100 a rank.
List<Map<String, Object?>> _members(int count, {int you = 4, int tier = 3}) => [
  for (var rank = 1; rank <= count; rank++)
    {
      'rank': rank,
      'name': rank == you
          ? 'Tornike'
          : 'Player ${String.fromCharCode(64 + rank % 26 + 1)}.',
      'xp': 3000 - rank * 100,
      'zone': rank <= 5 && tier < 5
          ? 'up'
          : rank > 25 && tier > 0
          ? 'down'
          : 'stay',
      'you': rank == you,
    },
];

void main() {
  late AppDatabase db;
  late List<http.Request> sent;
  late http.Response Function(http.Request) reply;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    sent = [];
    reply = (_) => http.Response('', 500);
  });
  tearDown(() => db.close());

  http.Response standing(List<Map<String, Object?>> members, {int tier = 3}) =>
      http.Response(
        jsonEncode({
          'player': {'id': 'p1', 'name': 'Tornike'},
          'league': {
            'tier': tier,
            'week': '2026-11-09',
            'ends_at': DateTime.now()
                .add(const Duration(days: 3, hours: 5))
                .toUtc()
                .toIso8601String(),
            'members': members,
          },
        }),
        200,
      );

  Future<void> pump(
    WidgetTester tester, {
    String location = Routes.leagues,
  }) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          pindoroMapBuilderProvider.overrideWithValue((_) => const SizedBox()),
          packRepositoryProvider.overrideWith((ref) async {
            final repo = SqlitePackRepository.open(AppConfig.fixturePackAsset);
            ref.onDispose(repo.close);
            return repo;
          }),
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
        child: PindoroApp(initialLocation: location),
      ),
    );
    await settle(tester);
  }

  Future<void> joined() =>
      LeagueDao(db).save(playerId: 'p1', token: 't0k', name: 'Tornike');

  /// Drift streams need real time: read outside the test's fake clock.
  Future<LeaguePlayer?> account(WidgetTester tester) =>
      tester.runAsync<LeaguePlayer?>(() => LeagueDao(db).watchAccount().first);

  testWidgets('a new player picks a name, joins and sees the week', (
    tester,
  ) async {
    reply = (request) => request.method == 'POST'
        ? http.Response(
            jsonEncode({
              'player': {'id': 'p1', 'name': 'Tornike K.'},
              'token': 't0k',
            }),
            201,
          )
        : standing(const []);
    await pump(tester);
    expect(find.text('Pick a league name'), findsOneWidget);
    PindoroButton join() => tester.widget<PindoroButton>(
      find.widgetWithText(PindoroButton, 'Join'),
    );
    await tester.enterText(find.byType(TextField), 'T');
    await tester.pump();
    expect(join().onPressed, isNull);
    await tester.enterText(find.byType(TextField), '  Tornike   K. ');
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Join'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await settle(tester);
    expect(jsonDecode(sent.first.body), {'name': 'Tornike K.'});
    expect((await account(tester))?.token, 't0k');
    expect(find.text('Earn XP to join this week’s league'), findsOneWidget);
    expect(find.text('Avenue league'), findsOneWidget);
  });

  testWidgets('the board ranks the week with zones and reads each row', (
    tester,
  ) async {
    await joined();
    reply = (_) => standing(_members(30, you: 4, tier: 3));
    await pump(tester);
    expect(find.text('Avenue league'), findsOneWidget);
    expect(find.text('Top 5 move up · 3 days left'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(
      find.text('Promotion zone · top 5 move up to Boulevard'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        '4th, You, ${formatNumber(2600)} XP, promotion zone.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Avenue league, 4th of 6 leagues. Top 5 move up. 3 days left.',
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Demotion zone · bottom 5 move down to Street'),
      300,
    );
    expect(
      find.bySemanticsLabel('26th, Player A., 400 XP, demotion zone.'),
      findsOneWidget,
    );
    final put = sent.single;
    expect(put.headers['authorization'], 'Bearer t0k');
    expect(jsonDecode(put.body)['xp'], 0);
  });

  testWidgets('Highway has no promotion zone', (tester) async {
    await joined();
    reply = (_) => standing(_members(30, tier: 5), tier: 5);
    await pump(tester);
    expect(find.text('Highway league'), findsOneWidget);
    expect(find.textContaining('Bottom 5 move down ·'), findsOneWidget);
    expect(find.byType(ZoneDivider), findsOneWidget);
    expect(find.textContaining('move up'), findsNothing);
    expect(
      find.text('Demotion zone · bottom 5 move down to Boulevard'),
      findsOneWidget,
    );
  });

  testWidgets('offline says so and tries again', (tester) async {
    await joined();
    reply = (_) => throw http.ClientException('down');
    await pump(tester);
    expect(
      find.text('Can’t reach the league. Check your connection and try again.'),
      findsOneWidget,
    );
    reply = (_) => standing(_members(3, you: 1));
    await tester.runAsync(() async {
      await tester.tap(find.text('Try again'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await settle(tester);
    expect(find.text('You'), findsOneWidget);
    expect(find.byType(ZoneDivider), findsNothing);
  });

  testWidgets('a player the server forgot is asked for a name again', (
    tester,
  ) async {
    await joined();
    reply = (_) => http.Response('', 401);
    await pump(tester);
    expect(find.text('Pick a league name'), findsOneWidget);
    expect(await account(tester), isNull);
  });

  testWidgets('a server error says so over the last board, not offline', (
    tester,
  ) async {
    await tester.runAsync(joined);
    reply = (_) => standing(_members(3, you: 2));
    await pump(tester);
    expect(find.byType(LeagueHeader), findsOneWidget);
    reply = (_) => http.Response('', 500);
    await tapThrough(tester, find.bySemanticsLabel('Me').first);
    await tapThrough(tester, find.bySemanticsLabel('Leagues').first);
    expect(
      find.text('The league isn’t working right now. Try again later.'),
      findsOneWidget,
    );
    expect(find.byType(LeagueHeader), findsNothing);
  });

  testWidgets(
    'Leagues is the fourth tab and syncs at launch and each time it opens',
    (tester) async {
      await tester.runAsync(joined);
      reply = (_) => standing(_members(3, you: 2));
      await pump(tester, location: Routes.me);
      final bar = tester.widget<PindoroNavBar>(find.byType(PindoroNavBar));
      expect(bar.items.map((i) => i.label), [
        'Path',
        'Free play',
        'Pit stop',
        'Leagues',
        'Me',
      ]);
      expect(sent, hasLength(1));
      await tapThrough(tester, find.bySemanticsLabel('Leagues').first);
      expect(find.byType(LeagueHeader), findsOneWidget);
      await tapThrough(tester, find.bySemanticsLabel('Me').first);
      await tapThrough(tester, find.bySemanticsLabel('Leagues').first);
      expect(sent, hasLength(3));
    },
  );

  testWidgets('settings rename the player, and leave after asking', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1080, 4800)
      ..devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.runAsync(joined);
    reply = (request) => switch (request.method) {
      'PATCH' => http.Response(
        jsonEncode({'id': 'p1', 'name': 'Tornike B.'}),
        200,
      ),
      'DELETE' => http.Response('', 204),
      _ => http.Response('', 500),
    };
    await pump(tester, location: Routes.settings);
    expect(find.text('Tornike'), findsOneWidget);
    await tapThrough(tester, find.text('League name'));
    await tester.enterText(find.byType(TextField), 'Tornike B.');
    await tester.pump();
    await tapThrough(tester, find.text('Save'));
    expect(jsonDecode(sent.last.body), {'name': 'Tornike B.'});
    expect(find.text('Tornike B.'), findsOneWidget, reason: 'back in Settings');

    await tapThrough(tester, find.text('Leave leagues'));
    expect(find.text('Leave leagues?'), findsOneWidget);
    await tapThrough(tester, find.text('Leave'));
    expect(sent.last.method, 'DELETE');
    expect(sent.last.headers['authorization'], 'Bearer t0k');
    expect(await account(tester), isNull);
    expect(find.text('Leave leagues'), findsNothing);
  });
}

Future<void> tapThrough(WidgetTester tester, Finder target) async {
  await tester.runAsync(() async {
    await tester.tap(target);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await settle(tester);
}

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}
