import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/api_client.dart';

final leagueApiProvider = Provider<LeagueApi>(
  (ref) => LeagueApi(ref.watch(apiClientProvider)),
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

/// The account's league this week (`PUT /v1/league/me`); [members] is empty
/// until it earns XP this week.
typedef Standing = ({int tier, DateTime endsAt, List<LeagueMember> members});

/// The API's league route (docs: `shared/openapi/openapi.json`).
class LeagueApi {
  const LeagueApi(this._api);

  final ApiClient _api;

  /// Records [xp] as this [week]'s XP for the account holding [token] and
  /// returns its league.
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
      final league = body['league']! as Map<String, Object?>;
      return (
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
