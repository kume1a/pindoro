import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pindoro/core/api_client.dart';
import 'package:pindoro/core/config.dart';

final leagueApiProvider = Provider<LeagueApi>(
  (ref) => LeagueApi(AppConfig.apiBaseUrl),
);

/// Where a rank moves at the week's end.
enum LeagueZone { up, stay, down }

typedef LeagueMember = ({
  int rank,
  String name,
  int xp,
  LeagueZone zone,
  bool you,
});

/// The player's league this week (`PUT /v1/league/me`); [members] is empty
/// until they earn XP this week.
typedef Standing = ({
  String name,
  int tier,
  DateTime endsAt,
  List<LeagueMember> members,
});

typedef NewPlayer = ({String id, String token, String name});

/// The API's players and leagues routes (docs: `shared/openapi/openapi.json`).
class LeagueApi {
  LeagueApi(String baseUrl, {http.Client? client})
    : _api = ApiClient(baseUrl, client: client);

  final ApiClient _api;

  Future<NewPlayer> join(String name) =>
      _api.json('POST', '/v1/players', body: {'name': name}, (body) {
        final player = body['player']! as Map<String, Object?>;
        return (
          id: player['id']! as String,
          token: body['token']! as String,
          name: player['name']! as String,
        );
      });

  /// The name as the server saved it.
  Future<String> rename(String token, String name) => _api.json(
    'PATCH',
    '/v1/players/me',
    token: token,
    body: {'name': name},
    (body) => body['name']! as String,
  );

  Future<void> leave(String token) =>
      _api.json('DELETE', '/v1/players/me', token: token, (_) {});

  /// Records [xp] as this [week]'s XP and returns the league.
  Future<Standing> sync(
    String token, {
    required String week,
    required int xp,
  }) => _api.json(
    'PUT',
    '/v1/league/me',
    token: token,
    body: {'week': week, 'xp': xp},
    (body) {
      final player = body['player']! as Map<String, Object?>;
      final league = body['league']! as Map<String, Object?>;
      return (
        name: player['name']! as String,
        tier: league['tier']! as int,
        endsAt: DateTime.parse(league['ends_at']! as String),
        members: [
          for (final m
              in (league['members']! as List<Object?>)
                  .cast<Map<String, Object?>>())
            (
              rank: m['rank']! as int,
              name: m['name']! as String,
              xp: m['xp']! as int,
              zone: LeagueZone.values.byName(m['zone']! as String),
              you: m['you']! as bool,
            ),
        ],
      );
    },
  );
}
