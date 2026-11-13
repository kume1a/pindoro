import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/api_client.dart';

final accountApiProvider = Provider<AccountApi>(
  (ref) => AccountApi(ref.watch(apiClientProvider)),
);

/// A signed-in phone and when the account last backed up (null: never). A
/// new account and a reset carry the [recoveryCode] too, shown once.
typedef Session = ({
  String username,
  String token,
  DateTime? backupAt,
  String? recoveryCode,
});

/// The API's account and backup routes.
class AccountApi {
  const AccountApi(this._api);

  final ApiClient _api;

  /// 409 when the username is taken.
  Future<Session> create(String username, String password) =>
      _session('/v1/accounts', {'username': username, 'password': password});

  /// 401 for a wrong username or password. Signs out the phone that was
  /// signed in before.
  Future<Session> signIn(String username, String password) =>
      _session('/v1/sessions', {'username': username, 'password': password});

  /// A new [password] with the [recoveryCode]; 401 when either is wrong.
  Future<Session> reset(
    String username,
    String recoveryCode,
    String password,
  ) => _session('/v1/accounts/reset', {
    'username': username,
    'recoveryCode': recoveryCode,
    'password': password,
  });

  /// 403 when [password] isn't the current one.
  Future<void> changePassword(
    String token,
    String password,
    String newPassword,
  ) => _api.json(
    'PUT',
    '/v1/accounts/me/password',
    token: token,
    body: {'password': password, 'newPassword': newPassword},
    (_) {},
  );

  Future<void> signOut(String token) =>
      _api.json('DELETE', '/v1/sessions/me', token: token, (_) {});

  /// Deletes the account and its backup on the server.
  Future<void> delete(String token) =>
      _api.json('DELETE', '/v1/accounts/me', token: token, (_) {});

  /// When the server saved [backup].
  Future<DateTime> upload(String token, Uint8List backup) => _api.upload(
    '/v1/accounts/me/backup',
    backup,
    token: token,
    (body) => DateTime.parse(body['backupAt']! as String),
  );

  Future<Uint8List> download(String token) =>
      _api.download('/v1/accounts/me/backup', token: token);

  Future<Session> _session(String path, Map<String, Object?> body) => _api.json(
    'POST',
    path,
    body: body,
    (body) => (
      username:
          (body['account']! as Map<String, Object?>)['username']! as String,
      token: body['token']! as String,
      backupAt: switch (body['backupAt']) {
        final String at => DateTime.parse(at),
        _ => null,
      },
      recoveryCode: body['recoveryCode'] as String?,
    ),
  );
}
