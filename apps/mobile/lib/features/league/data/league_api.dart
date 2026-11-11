import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
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

/// A failed league call: [status] is null when the server wasn't reached, and
/// a 2xx one when its answer didn't parse.
class LeagueException implements Exception {
  const LeagueException([this.status]);

  final int? status;

  bool get offline => status == null;

  /// The token is unknown: the player is gone on the server.
  bool get unknownPlayer => status == 401;

  @override
  String toString() => 'LeagueException($status)';
}

/// The API's players and leagues routes (docs: `shared/openapi/openapi.json`).
class LeagueApi {
  LeagueApi(this.baseUrl, {http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  static const Duration timeout = Duration(seconds: 10);

  Future<NewPlayer> join(String name) =>
      _send('POST', '/v1/players', body: {'name': name}, (body) {
        final player = body['player']! as Map<String, Object?>;
        return (
          id: player['id']! as String,
          token: body['token']! as String,
          name: player['name']! as String,
        );
      });

  /// The name as the server saved it.
  Future<String> rename(String token, String name) => _send(
    'PATCH',
    '/v1/players/me',
    token: token,
    body: {'name': name},
    (body) => body['name']! as String,
  );

  Future<void> leave(String token) =>
      _send('DELETE', '/v1/players/me', token: token, (_) {});

  /// Records [xp] as this [week]'s XP and returns the league.
  Future<Standing> sync(
    String token, {
    required String week,
    required int xp,
  }) => _send(
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

  /// Sends the call and [read]s its JSON body; any answer [read] can't parse
  /// fails like a server error.
  Future<T> _send<T>(
    String method,
    String path,
    T Function(Map<String, Object?> body) read, {
    String? token,
    Map<String, Object?>? body,
  }) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'));
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response res;
    try {
      res = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      ).timeout(timeout);
    } on Exception {
      throw const LeagueException();
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw LeagueException(res.statusCode);
    }
    try {
      return read(
        res.body.isEmpty
            ? const {}
            : jsonDecode(res.body) as Map<String, Object?>,
      );
    } on Object {
      throw LeagueException(res.statusCode);
    }
  }
}
