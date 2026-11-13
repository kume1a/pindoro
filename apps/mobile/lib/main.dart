import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pindoro/app/app.dart';
import 'package:pindoro/app/router.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/database_file.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/restart.dart';
import 'package:pindoro/core/sounds.dart';
import 'package:pindoro/features/map/data/city_tiles.dart';
import 'package:pindoro/features/pack/data/pack_store.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'FiraGO',
    ], await rootBundle.loadString('packages/pindoro_design/fonts/OFL.txt'));
  });
  await _boot(coldStart: true);
}

/// Opens the database and runs the app on it; a restart boots again.
Future<void> _boot({required bool coldStart}) async {
  final db = openDatabase();
  final docs = await getApplicationDocumentsDirectory();
  final store = PackStore(
    root: Directory('${docs.path}/packs'),
    apiBaseUrl: AppConfig.apiBaseUrl,
  );
  late final ProviderContainer container;
  Future<void> restart(Future<void> Function() swap) async {
    // Nothing on screen may read the database while it is swapped.
    runApp(const SizedBox.shrink());
    await WidgetsBinding.instance.endOfFrame;
    container.dispose();
    await db.close();
    await swap();
    await _boot(coldStart: false);
  }

  container = ProviderContainer(
    observers: [CityTilesObserver(Directory('${docs.path}/city_tiles'))],
    overrides: [
      databaseProvider.overrideWithValue(db),
      packStoreProvider.overrideWithValue(store),
      restartProvider.overrideWithValue(restart),
    ],
  );
  // Preloads while the first page builds; sounds before it lands are skipped.
  unawaited(container.read(soundsProvider).load());
  // A pack installed in the background is used right away; a round in play
  // keeps the streets it already loaded.
  final city = (await SettingsDao(db).read()).cityId;
  unawaited(
    refreshQuietly(store, city).then((installed) {
      if (installed) container.invalidate(packRepositoryProvider);
    }),
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: PindoroApp(
        initialLocation: await startLocation(db),
        coldStart: coldStart,
      ),
    ),
  );
}
