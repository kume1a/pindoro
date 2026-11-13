import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pindoro/core/api_client.dart';
import 'package:pindoro/core/config.dart';

final accountApiProvider = Provider<AccountApi>(
  (ref) => AccountApi(AppConfig.apiBaseUrl),
);

/// A signed-in phone, and when the account last backed up (null: never).
typedef Session = ({String username, String token, DateTime? backupAt});

/// The API's account and backup routes.
class AccountApi {
  AccountApi(String baseUrl, {http.Client? client})
    : _api = ApiClient(baseUrl, client: client);

  final ApiClient _api;

  /// 409 when the username is taken.
  Future<Session> create(String username, String password) =>
      _session('/v1/accounts', username, password);

  /// 401 for a wrong username or password. Signs out the phone that was
  /// signed in before.
  Future<Session> signIn(String username, String password) =>
      _session('/v1/sessions', username, password);

  /// When the server saved [backup].
  Future<DateTime> upload(String token, Uint8List backup) => _api.json(
    'PUT',
    '/v1/accounts/me/backup',
    token: token,
    bytes: backup,
    (body) => DateTime.parse(body['backupAt']! as String),
  );

  Future<Uint8List> download(String token) =>
      _api.download('/v1/accounts/me/backup', token: token);

  Future<Session> _session(String path, String username, String password) =>
      _api.json(
        'POST',
        path,
        body: {'username': username, 'password': password},
        (body) => (
          username:
              (body['account']! as Map<String, Object?>)['username']! as String,
          token: body['token']! as String,
          backupAt: switch (body['backupAt']) {
            final String at => DateTime.parse(at),
            _ => null,
          },
        ),
      );
}
