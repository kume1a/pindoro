import 'dart:io';
import 'dart:typed_data';

import 'package:pindoro/core/database/database.dart';
import 'package:sqlite3/sqlite3.dart';

/// A backup the app can't open: made by a newer Pindoro, or damaged.
class UnreadableBackup implements Exception {
  const UnreadableBackup();
}

/// The progress database as one gzipped SQLite file, put together in [work].
/// The account row stays on the phone: the server never sees its token.
Future<Uint8List> snapshot(AppDatabase db, Directory work) async {
  final copy = File('${work.path}/pindoro.backup.sqlite');
  if (copy.existsSync()) await copy.delete();
  try {
    await db.customStatement('VACUUM INTO ?', [copy.path]);
    final raw = sqlite3.open(copy.path);
    try {
      // Overwrites the deleted row's bytes instead of only freeing its page.
      raw
        ..execute('PRAGMA secure_delete = ON')
        ..execute('DELETE FROM account');
    } finally {
      raw.close();
    }
    return Uint8List.fromList(gzip.encode(await copy.readAsBytes()));
  } finally {
    if (copy.existsSync()) await copy.delete();
  }
}

/// Writes [backup] to [target] signed in as [username] with [token] (backed
/// up at [backedUpAt]), ready to replace the database file; drift migrates
/// it on open. Throws [UnreadableBackup] for a newer schema or a damaged file.
Future<void> stageRestore(
  Uint8List backup,
  File target, {
  required String username,
  required String token,
  DateTime? backedUpAt,
}) async {
  try {
    await target.writeAsBytes(gzip.decode(backup), flush: true);
    final raw = sqlite3.open(target.path);
    try {
      final ok = raw.select('PRAGMA quick_check').first.values.first == 'ok';
      if (!ok || raw.userVersion > AppDatabase.version) {
        throw const UnreadableBackup();
      }
      // Drift keeps dates as ISO 8601 text (build.yaml).
      raw.execute(
        'INSERT OR REPLACE INTO account (id, username, token, backed_up_at) '
        'VALUES (1, ?, ?, ?)',
        [username, token, backedUpAt?.toUtc().toIso8601String()],
      );
    } finally {
      raw.close();
    }
  } on Object {
    if (target.existsSync()) await target.delete();
    throw const UnreadableBackup();
  }
}
