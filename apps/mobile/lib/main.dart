import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/config.dart';
import 'app/database.dart';
import 'app/router.dart';
import 'features/pack/pack_store.dart';
import 'features/pack/sqlite_pack_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'FiraGO',
    ], await rootBundle.loadString('packages/pindoro_design/fonts/OFL.txt'));
  });
  final db = AppDatabase();
  final docs = await getApplicationDocumentsDirectory();
  final store = PackStore(
    root: Directory('${docs.path}/packs'),
    apiBaseUrl: AppConfig.apiBaseUrl,
  );
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      packStoreProvider.overrideWithValue(store),
    ],
  );
  // A pack installed in the background is used right away; a round in play
  // keeps the streets it already loaded.
  final city = (await db.readSettings()).lastCity ?? AppConfig.cityId;
  unawaited(
    refreshQuietly(store, city).then((installed) {
      if (installed) container.invalidate(packRepositoryProvider);
    }),
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: PindoroApp(initialLocation: await initialLocation(db)),
    ),
  );
}
