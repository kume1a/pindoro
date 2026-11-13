import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/api_client.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/database_file.dart';
import 'package:pindoro/core/restart.dart';
import 'package:pindoro/features/account/data/account_api.dart';
import 'package:pindoro/features/account/data/account_dao.dart';
import 'package:pindoro/features/account/data/backup.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';

/// Trimmed and lowercased, as the server keeps usernames.
String tidyUsername(String raw) => raw.trim().toLowerCase();

final _username = RegExp(r'^[a-z0-9._-]{3,24}$');

/// The server's rules: a tidied username of 3 to 24 a–z, 0–9, `.`, `_`, `-`.
bool isUsername(String tidy) => _username.hasMatch(tidy);

bool isPassword(String raw) => raw.length >= 8 && raw.length <= 200;

/// The signed-in account, null when signed out.
final accountProvider = StreamProvider<Account?>(
  (ref) => ref.watch(accountDaoProvider).watch(),
);

/// The progress database's file; tests point it into a temp dir.
final databaseFileProvider = Provider<Future<File> Function()>(
  (ref) => databaseFile,
);

/// Started by the app root: keeps the account's backup in step with play.
final backupSyncProvider = Provider<BackupSync>((ref) {
  final sync = BackupSync(
    db: ref.watch(databaseProvider),
    dao: ref.watch(accountDaoProvider),
    api: ref.watch(accountApiProvider),
    databaseFile: ref.watch(databaseFileProvider),
  );
  ref.onDispose(sync.dispose);
  return sync;
});

/// While signed in, uploads the progress [delay] after the last write, and
/// at once when the app goes to the background with a write waiting. A
/// failed upload tries again after [delay].
// ponytail: an app killed inside the delay uploads after the next write.
class BackupSync {
  BackupSync({
    required AppDatabase db,
    required AccountDao dao,
    required AccountApi api,
    required Future<File> Function() databaseFile,
  }) : _db = db,
       _dao = dao,
       _api = api,
       _databaseFile = databaseFile {
    _subscriptions = [
      _dao.watch().listen((account) => _account = account),
      _db
          .tableUpdates()
          .where((updates) => updates.any((u) => u.table != 'account'))
          .listen((_) => _soon()),
    ];
  }

  static const Duration delay = Duration(minutes: 1);

  final AppDatabase _db;
  final AccountDao _dao;
  final AccountApi _api;
  final Future<File> Function() _databaseFile;
  late final List<StreamSubscription<Object?>> _subscriptions;
  Account? _account;
  Timer? _waiting;
  Future<void>? _running;

  void _soon() {
    if (_account == null) return;
    _waiting?.cancel();
    _waiting = Timer(delay, () => unawaited(backUpQuietly()));
  }

  /// Uploads now if a write is waiting (the app going to the background).
  Future<void> flushWaiting() async {
    if (_waiting?.isActive ?? false) await backUpQuietly();
  }

  /// Uploads now, unless signed out. Throws [ApiException]; an unknown token
  /// (signed in on another phone) signs this one out first.
  Future<void> backUp() =>
      _running ??= _upload().whenComplete(() => _running = null);

  /// [backUp], trying again after [delay] when it fails.
  Future<void> backUpQuietly() async {
    try {
      await backUp();
    } on Object {
      _soon();
    }
  }

  Future<void> _upload() async {
    _waiting?.cancel();
    final account = await _dao.read();
    if (account == null) return;
    final work = (await _databaseFile()).parent;
    try {
      final at = await _api.upload(account.token, await snapshot(_db, work));
      await _dao.markBackedUp(at);
    } on ApiException catch (e) {
      if (e.unknownToken) await _dao.drop();
      rethrow;
    }
  }

  void dispose() {
    _waiting?.cancel();
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
  }
}

final accountActionsProvider = Provider<AccountActions>(AccountActions.new);

/// Creating an account and signing in: the server first, then this phone.
class AccountActions {
  const AccountActions(this._ref);

  final Ref _ref;

  AccountApi get _api => _ref.read(accountApiProvider);

  /// The new account backs this phone's progress up right away.
  Future<void> create(String username, String password) async =>
      keep(await _api.create(username, password));

  Future<Session> signIn(String username, String password) =>
      _api.signIn(username, password);

  /// Whether a restore would replace progress made on this phone.
  Future<bool> hasProgress() => _ref.read(progressDaoProvider).hasPlayed();

  /// Signs this phone in; its progress goes up over any backup.
  Future<void> keep(Session session) async {
    await _ref
        .read(accountDaoProvider)
        .save(username: session.username, token: session.token);
    await _ref.read(backupSyncProvider).backUpQuietly();
  }

  /// Replaces this phone's progress with the account's backup and starts the
  /// app again on it. Throws [UnreadableBackup] when this build can't open it.
  Future<void> restore(Session session) async {
    final backup = await _api.download(session.token);
    final file = await _ref.read(databaseFileProvider)();
    final staged = File('${file.path}.restore');
    await stageRestore(
      backup,
      staged,
      username: session.username,
      token: session.token,
      backedUpAt: session.backupAt,
    );
    await _ref.read(restartProvider)(() => staged.rename(file.path));
  }
}
