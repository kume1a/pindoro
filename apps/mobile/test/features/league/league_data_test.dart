import 'dart:convert';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pindoro/core/api_client.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/features/league/data/league_api.dart';
import 'package:pindoro/features/league/data/league_dao.dart';
import 'package:pindoro/features/league/data/league_data.dart';
import 'package:pindoro_core/pindoro_core.dart';

LeagueMember _member(int rank, int xp, {bool you = false}) => (
  rank: rank,
  name: you ? 'Me' : 'P$rank',
  xp: xp,
  zone: LeagueZone.stay,
  you: you,
);

Map<String, Object?> _standing({
  List<Map<String, Object?>> members = const [],
}) => {
  'player': {'id': 'p1', 'name': 'Nino'},
  'league': {
    'tier': 3,
    'week': '2026-11-09',
    'ends_at': '2026-11-15T20:00:00.000Z',
    'members': members,
  },
};

void main() {
  group('rankBefore', () {
    test('counts the players the gained XP passed', () {
      final members = [
        _member(1, 900),
        _member(2, 500, you: true),
        _member(3, 450),
        _member(4, 300),
        _member(5, 100),
      ];
      expect(rankBefore(members, 250), 4);
      expect(rankBefore(members, 10), 2);
    });

    test('an equal player ahead stays ahead', () {
      final members = [_member(1, 400), _member(2, 400, you: true)];
      expect(rankBefore(members, 0), 2);
    });

    test('is null when that XP put the player in the league', () {
      expect(rankBefore([_member(1, 300, you: true)], 300), isNull);
      expect(rankBefore([_member(1, 300)], 10), isNull);
    });
  });

  group('LeagueApi', () {
    test(
      'sync sends the week XP with the token and reads the league',
      () async {
        late http.Request sent;
        final api = LeagueApi(
          'https://api.example',
          client: MockClient((request) async {
            sent = request;
            return http.Response(
              jsonEncode(
                _standing(
                  members: [
                    {
                      'rank': 1,
                      'name': 'Nino',
                      'xp': 120,
                      'zone': 'up',
                      'you': true,
                    },
                  ],
                ),
              ),
              200,
            );
          }),
        );
        final standing = await api.sync('t0k', week: '2026-11-09', xp: 120);
        expect(sent.method, 'PUT');
        expect(sent.url.toString(), 'https://api.example/v1/league/me');
        expect(sent.headers['authorization'], 'Bearer t0k');
        expect(jsonDecode(sent.body), {'week': '2026-11-09', 'xp': 120});
        expect(standing.tier, 3);
        expect(standing.endsAt, DateTime.utc(2026, 11, 15, 20));
        expect(standing.members.single.zone, LeagueZone.up);
      },
    );

    test('an answer that doesn\'t parse fails as a server error', () async {
      final api = LeagueApi(
        'https://api.example',
        client: MockClient((_) async => http.Response('{"player": 1}', 200)),
      );
      await expectLater(
        api.sync('t', week: '2026-11-09', xp: 1),
        throwsA(
          isA<ApiException>()
              .having((e) => e.status, 'status', 200)
              .having((e) => e.offline, 'offline', false),
        ),
      );
    });

    test('a failed call carries its status, or none offline', () async {
      LeagueApi answering(Future<http.Response> Function() reply) =>
          LeagueApi('https://api.example', client: MockClient((_) => reply()));
      await expectLater(
        answering(() async => http.Response('', 401)).leave('t'),
        throwsA(
          isA<ApiException>().having((e) => e.unknownToken, 'unknown', true),
        ),
      );
      await expectLater(
        answering(() => throw http.ClientException('down')).join('Nino'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', null)),
      );
    });
  });

  group('standingProvider', () {
    late AppDatabase db;
    late List<http.Request> sent;
    late int status;

    setUp(() {
      db = AppDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      sent = [];
      status = 200;
    });
    tearDown(() => db.close());

    ProviderContainer container() {
      final c = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          leagueApiProvider.overrideWithValue(
            LeagueApi(
              'https://api.example',
              client: MockClient((request) async {
                sent.add(request);
                return http.Response(jsonEncode(_standing()), status);
              }),
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('is null without an account, and calls nothing', () async {
      final c = container();
      final sub = c.listen(standingProvider, (_, _) {});
      expect(await c.read(standingProvider.future), isNull);
      expect(sent, isEmpty);
      sub.close();
    });

    test("sends this week's XP", () async {
      await LeagueDao(db).save(playerId: 'p1', token: 't0k', name: 'Nino');
      final c = container();
      final sub = c.listen(standingProvider, (_, _) {});
      final standing = await c.read(standingProvider.future);
      expect(standing?.tier, 3);
      expect(jsonDecode(sent.single.body), {
        'week': leagueWeek(DateTime.now()).key,
        'xp': 0,
      });
      sub.close();
    });

    test('drops the account when the server no longer knows it', () async {
      await LeagueDao(db).save(playerId: 'p1', token: 't0k', name: 'Nino');
      status = 401;
      final c = container();
      final sub = c.listen(standingProvider, (_, _) {});
      expect(await c.read(standingProvider.future), isNull);
      expect(await LeagueDao(db).watchAccount().first, isNull);
      sub.close();
    });
  });
}
