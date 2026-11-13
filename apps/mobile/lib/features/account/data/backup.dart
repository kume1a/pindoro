import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/features/account/data/account_dao.dart';
import 'package:sqlite3/sqlite3.dart';

/// A backup the app can't open: made by a newer Pindoro, damaged, or bigger
/// than any real one.
class UnreadableBackup implements Exception {
  const UnreadableBackup();
}

/// Far above any real progress database; a bigger one is refused unread.
const int maxRestoredBytes = 64 * 1024 * 1024;

T _withRaw<T>(File file, T Function(Database raw) use) {
  final raw = sqlite3.open(file.path);
  try {
    return use(raw);
  } finally {
    raw.close();
  }
}

Future<void> _deleteIfExists(File file) async {
  if (file.existsSync()) await file.delete();
}

/// The progress database as one gzipped SQLite file, put together in [work].
/// The account row stays on the phone: the server never sees its token.
Future<Uint8List> snapshot(AppDatabase db, Directory work) async {
  final copy = File('${work.path}/pindoro.backup.sqlite');
  await _deleteIfExists(copy);
  try {
    await db.customStatement('VACUUM INTO ?', [copy.path]);
    // Overwrites the deleted row's bytes instead of only freeing its page.
    _withRaw(
      copy,
      (raw) => raw
        ..execute('PRAGMA secure_delete = ON')
        ..execute('DELETE FROM account'),
    );
    return Uint8List.fromList(gzip.encode(await copy.readAsBytes()));
  } finally {
    await _deleteIfExists(copy);
  }
}

/// Unzips [backup] into [target], stopping past [limit] bytes.
Future<void> _inflate(Uint8List backup, File target, int limit) async {
  final sink = target.openWrite();
  var written = 0;
  try {
    await for (final chunk in gzip.decoder.bind(Stream.value(backup))) {
      written += chunk.length;
      if (written > limit) throw const UnreadableBackup();
      sink.add(chunk);
    }
  } finally {
    await sink.close();
  }
}

/// Writes [backup] to [target], migrated to this build's schema and signed
/// in as [username] with [token] (backed up at [backedUpAt]), ready to
/// replace the database file. Throws [UnreadableBackup] for a newer schema, a
/// damaged file or one over [limit] bytes unzipped.
Future<void> stageRestore(
  Uint8List backup,
  File target, {
  required String username,
  required String token,
  DateTime? backedUpAt,
  int limit = maxRestoredBytes,
}) async {
  try {
    await _inflate(backup, target, limit);
    final opens = _withRaw(
      target,
      (raw) =>
          raw.select('PRAGMA quick_check').first.values.first == 'ok' &&
          raw.userVersion <= AppDatabase.version,
    );
    if (!opens) throw const UnreadableBackup();
    // Opening migrates it; a file that can't migrate fails here, not at boot.
    final restored = AppDatabase(NativeDatabase(target));
    try {
      await AccountDao(
        restored,
      ).save(username: username, token: token, backedUpAt: backedUpAt);
    } finally {
      await restored.close();
    }
  } on Object {
    await _deleteIfExists(target);
    throw const UnreadableBackup();
  }
}
