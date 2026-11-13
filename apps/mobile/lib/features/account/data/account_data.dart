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

/// The backup account, null when there is none on this phone. A null token
/// means a sign-in on another phone signed this one out.
final accountProvider = StreamProvider<Account?>(
  (ref) => ref.watch(accountDaoProvider).watchAccount(),
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

/// While signed in, uploads the progress [delay] after the last write; at
/// once when the app goes to the background with a write waiting; and at
/// launch when the app last stopped with writes the backup lacks
/// (`account.changed_at`). Offline, server and disk failures try again after
/// [delay]; an unknown token signs this phone out.
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
      _dao.watchAccount().listen(_accountChanged),
      _db
          .tableUpdates()
          .where((updates) => updates.any((u) => u.table != 'account'))
          .listen((_) => _wrote()),
    ];
  }

  static const Duration delay = Duration(minutes: 1);

  final AppDatabase _db;
  final AccountDao _dao;
  final AccountApi _api;
  final Future<File> Function() _databaseFile;
  late final List<StreamSubscription<Object?>> _subscriptions;
  Account? _account;
  bool _launched = false;
  bool _wroteDuringUpload = false;
  Timer? _pendingUpload;
  Future<void>? _running;

  bool get _signedIn => _account?.token != null;

  void _accountChanged(Account? account) {
    _account = account;
    if (_launched) return;
    _launched = true;
    if (_signedIn && account?.changedAt != null) unawaited(backUpQuietly());
  }

  void _wrote() {
    if (!_signedIn) return;
    if (_running != null) _wroteDuringUpload = true;
    if (_account?.changedAt == null) {
      unawaited(_dao.markChanged(DateTime.now()));
    }
    _scheduleUpload();
  }

  void _scheduleUpload() {
    _pendingUpload?.cancel();
    _pendingUpload = Timer(delay, () => unawaited(backUpQuietly()));
  }

  /// Uploads now if a write is waiting (the app going to the background),
  /// after any upload already running.
  Future<void> flushWaiting() async {
    try {
      await _running;
    } on Object {
      // That upload's failure has scheduled its own retry.
    }
    if (_pendingUpload?.isActive ?? false) await backUpQuietly();
  }

  /// Uploads now, unless signed out, and throws what failed.
  Future<void> backUp() =>
      _running ??= _upload().whenComplete(() => _running = null);

  /// [backUp] without throwing: a failure has already been handled.
  Future<void> backUpQuietly() async {
    try {
      await backUp();
    } on Object {
      // Retried, signed out, or (a refused backup) left for the next write.
    }
  }

  Future<void> _upload() async {
    final token = (await _dao.read())?.token;
    if (token == null) return;
    _pendingUpload?.cancel();
    _wroteDuringUpload = false;
    try {
      final work = (await _databaseFile()).parent;
      final at = await _api.upload(token, await snapshot(_db, work));
      await _dao.markBackedUp(at, complete: !_wroteDuringUpload);
    } on ApiException catch (e) {
      if (e.unknownToken) {
        await _dao.signedOutElsewhere();
      } else if (_mayPass(e)) {
        _scheduleUpload();
      }
      rethrow;
    } on Object {
      _scheduleUpload();
      rethrow;
    }
  }

  /// Offline, timeouts, rate limits and server errors pass; a refused
  /// backup (too big, not gzip) would fail the same way every minute.
  static bool _mayPass(ApiException e) => switch (e.status) {
    null || 408 || 429 => true,
    final status => status >= 500,
  };

  void dispose() {
    _pendingUpload?.cancel();
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
  }
}

/// Whether to restore a backup made at the given time over this phone's
/// progress: true restores, false keeps this phone's, null gives up the
/// sign-in.
typedef AskRestore = Future<bool?> Function(DateTime backupAt);

final accountActionsProvider = Provider<AccountActions>(AccountActions.new);

/// Every account change: the server first, then this phone.
class AccountActions {
  const AccountActions(this._ref);

  final Ref _ref;

  AccountApi get _api => _ref.read(accountApiProvider);

  AccountDao get _dao => _ref.read(accountDaoProvider);

  /// The new account backs this phone's progress up right away; its session
  /// carries the recovery code to show.
  Future<Session> create(String username, String password) async {
    final session = await _api.create(username, password);
    await _keep(session);
    return session;
  }

  /// Checks the password; [takeOver] then brings this phone in.
  Future<Session> signIn(String username, String password) =>
      _api.signIn(username, password);

  /// A new [password] with the recovery code; the session carries the new
  /// code to show before [takeOver].
  Future<Session> reset(
    String username,
    String recoveryCode,
    String password,
  ) => _api.reset(username, recoveryCode, password);

  /// Signs this phone in with [session]: a backup restores (the app starts
  /// again on it) unless this phone has progress of its own and [askRestore]
  /// keeps that instead.
  Future<void> takeOver(
    Session session, {
    required AskRestore askRestore,
  }) async {
    final at = session.backupAt;
    if (at != null && await _restores(at, askRestore)) return _restore(session);
    await _keep(session);
  }

  /// 403 when [password] isn't the current one.
  Future<void> changePassword(String password, String newPassword) =>
      _withToken((token) => _api.changePassword(token, password, newPassword));

  /// Signs this phone out; its progress stays here. Offline, the server
  /// token dies with the next sign-in instead.
  Future<void> signOut() async {
    try {
      await _withToken(_api.signOut);
    } on ApiException catch (e) {
      if (!e.offline && !e.unknownToken) rethrow;
    }
    await _dao.drop();
  }

  /// Deletes the account and its backup on the server; progress stays here.
  Future<void> delete() async {
    await _withToken(_api.delete);
    await _dao.drop();
  }

  /// A backup restores straight away on a phone without progress; otherwise
  /// the player picks.
  Future<bool> _restores(DateTime backupAt, AskRestore askRestore) async {
    if (!await _ref.read(progressDaoProvider).hasPlayed()) return true;
    final choice = await askRestore(backupAt);
    if (choice == null) throw const SignInGivenUp();
    return choice;
  }

  /// This phone's progress goes up over any backup.
  Future<void> _keep(Session session) async {
    await _dao.save(
      username: session.username,
      token: session.token,
      changedAt: DateTime.now(),
    );
    await _ref.read(backupSyncProvider).backUpQuietly();
  }

  /// Replaces this phone's progress with the account's backup and starts the
  /// app again on it. Throws [UnreadableBackup] when this build can't open it.
  Future<void> _restore(Session session) async {
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
    await _ref.read(restartProvider)(staged);
  }

  /// Runs [call] with this phone's token; an unknown one (signed in on
  /// another phone) signs this phone out before the error goes on.
  Future<T> _withToken<T>(Future<T> Function(String token) call) async {
    final token = (await _dao.read())?.token;
    if (token == null) throw const ApiException(401);
    try {
      return await call(token);
    } on ApiException catch (e) {
      if (e.unknownToken) await _dao.signedOutElsewhere();
      rethrow;
    }
  }
}

/// The player closed the restore question: nothing was saved.
class SignInGivenUp implements Exception {
  const SignInGivenUp();
}
