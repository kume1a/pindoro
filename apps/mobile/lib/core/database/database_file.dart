import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pindoro/core/database/database.dart';

/// The progress database's file, where drift_flutter has always kept it; a
/// restore replaces it.
Future<File> databaseFile() async =>
    File('${(await getApplicationDocumentsDirectory()).path}/pindoro.sqlite');

/// [databaseFile]; tests point it into a temp dir.
final databaseFileProvider = Provider<Future<File> Function()>(
  (ref) => databaseFile,
);

AppDatabase openDatabase() => AppDatabase(
  driftDatabase(
    name: 'pindoro',
    native: DriftNativeOptions(
      databasePath: () async => (await databaseFile()).path,
    ),
  ),
);

/// Moves [restored] in as [file] and runs [boot] on it, nothing having
/// [file] open. If that boot fails, the old database goes back, [boot] runs
/// on it, and the error is rethrown.
Future<void> swapInDatabase(
  File file,
  File restored,
  Future<void> Function() boot,
) async {
  final previous = File('${file.path}.previous');
  if (previous.existsSync()) await previous.delete();
  await file.rename(previous.path);
  try {
    await restored.rename(file.path);
    await boot();
  } on Object {
    if (file.existsSync()) await file.delete();
    await previous.rename(file.path);
    await boot();
    rethrow;
  }
  await previous.delete();
}
