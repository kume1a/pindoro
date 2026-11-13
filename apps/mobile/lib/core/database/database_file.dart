import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pindoro/core/database/database.dart';

/// The progress database's file, where drift_flutter has always kept it; a
/// restore replaces it.
Future<File> databaseFile() async =>
    File('${(await getApplicationDocumentsDirectory()).path}/pindoro.sqlite');

AppDatabase openDatabase() => AppDatabase(
  driftDatabase(
    name: 'pindoro',
    native: DriftNativeOptions(
      databasePath: () async => (await databaseFile()).path,
    ),
  ),
);
