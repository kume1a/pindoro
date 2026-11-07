import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/pack/data/pack_store.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:sqlite3/sqlite3.dart';

/// Reads a city pack (docs/pack-format.md) opened read-only.
class SqlitePackRepository implements PackRepository {
  SqlitePackRepository.open(String path)
    : _db = sqlite3.open(path, mode: OpenMode.readOnly);

  final Database _db;

  @override
  Map<String, String> meta() => {
    for (final r in _db.select('SELECT key, value FROM meta'))
      r['key'] as String: r['value'] as String,
  };

  @override
  City city() => City.fromRow(_db.select('SELECT * FROM city LIMIT 1').first);

  @override
  List<District> districts() => [
    for (final r in _db.select('SELECT * FROM district ORDER BY name_ka'))
      District.fromRow(r),
  ];

  @override
  List<Street> streets({String? districtId, Set<Difficulty>? difficulties}) {
    final where = [
      if (districtId != null)
        'id IN (SELECT street_id FROM street_district WHERE district_id = ?)',
      if (difficulties != null)
        'difficulty IN (${List.filled(difficulties.length, '?').join(', ')})',
    ];
    final sql = [
      'SELECT * FROM street',
      if (where.isNotEmpty) 'WHERE ${where.join(' AND ')}',
      'ORDER BY id',
    ].join(' ');
    return [
      for (final r in _db.select(sql, [
        ?districtId,
        ...?difficulties?.map((d) => d.name),
      ]))
        Street.fromRow(r),
    ];
  }

  @override
  Map<String, Set<String>> partsByDistrict() {
    final byDistrict = <String, Set<String>>{};
    for (final r in _db.select(
      'SELECT district_id, street_id FROM street_district',
    )) {
      byDistrict
          .putIfAbsent(r['district_id'] as String, () => {})
          .add(r['street_id'] as String);
    }
    return byDistrict;
  }

  @override
  void close() => _db.close();
}

/// Copies the bundled Vake fixture next to downloaded packs once.
Future<File> copyFixture(Directory root) async {
  final file = File('${root.path}/tbilisi_vake_fixture.sqlite');
  if (!file.existsSync()) {
    final data = await rootBundle.load(AppConfig.fixturePackAsset);
    await file.create(recursive: true);
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }
  return file;
}

/// A city with no pack on the phone whose download failed: offline, or
/// [noSpace] when the phone is full.
class PackUnavailable implements Exception {
  const PackUnavailable(this.city, {this.noSpace = false});

  final String city;
  final bool noSpace;
}

/// The player chose to play the bundled Vake pack while Tbilisi can't
/// download; Try again turns it off.
final offlineVakeProvider = NotifierProvider<OfflineVakeNotifier, bool>(
  OfflineVakeNotifier.new,
);

class OfflineVakeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool on) => state = on;
}

/// The first download of the chosen city's pack, while it runs.
final packDownloadProvider =
    NotifierProvider<PackDownloadNotifier, PackProgress?>(
      PackDownloadNotifier.new,
    );

class PackDownloadNotifier extends Notifier<PackProgress?> {
  @override
  PackProgress? build() => null;

  void report(PackProgress? progress) => state = progress;
}

/// The chosen city's newest pack: downloaded on first use (progress in
/// [packDownloadProvider]); a failed download throws [PackUnavailable], and
/// the bundled fixture stands in for Tbilisi once the player picks it
/// ([offlineVakeProvider]). main() invalidates it when a background download
/// finishes. A failure stays until the player taps Try again: no automatic
/// retries.
final packRepositoryProvider = FutureProvider<PackRepository>(
  retry: (_, _) => null,
  (ref) async {
    final store = ref.watch(packStoreProvider);
    final city =
        ref.watch(settingsProvider.select((s) => s.value?.lastCity)) ??
        AppConfig.cityId;
    final offlineVake = ref.watch(offlineVakeProvider);
    final progress = ref.read(packDownloadProvider.notifier);
    final file =
        store.newest(city) ??
        (offlineVake && city == AppConfig.cityId
            ? await copyFixture(store.root)
            : await downloadPack(
                store,
                city,
                onProgress: progress.report,
              ).whenComplete(() => progress.report(null)));
    final repo = SqlitePackRepository.open(file.path);
    // Screens keep showing the previous pack while a new one loads, so a pack
    // is closed when its replacement opens, not when the provider reloads.
    final open = ref.read(_openPacksProvider);
    for (final old in open) {
      old.close();
    }
    open
      ..clear()
      ..add(repo);
    return repo;
  },
);

/// The pack [packRepositoryProvider] last returned; all closed with the app.
final _openPacksProvider = Provider<List<SqlitePackRepository>>((ref) {
  final open = <SqlitePackRepository>[];
  ref.onDispose(() {
    for (final repo in open) {
      repo.close();
    }
  });
  return open;
});

/// ENOSPC on Android and iOS.
const int _noSpaceLeft = 28;

/// Downloads [city]'s pack, or throws [PackUnavailable].
Future<File> downloadPack(
  PackStore store,
  String city, {
  void Function(PackProgress progress)? onProgress,
}) async {
  try {
    if (await store.refresh(city, onProgress: onProgress) case final file?) {
      return file;
    }
  } on FileSystemException catch (e) {
    if (e.osError?.errorCode == _noSpaceLeft) {
      throw PackUnavailable(city, noSpace: true);
    }
  } on Object {
    // Offline, server down or a bad file: the player can try again.
  }
  throw PackUnavailable(city);
}

/// Whether [pack] is the bundled Vake-only stand-in.
bool isFixturePack(PackRepository pack) => pack.meta()['scope'] == 'fixture';

/// The active pack's streets as the player sees them, by any part id.
final cityStreetsProvider = FutureProvider<Map<String, NamedStreet>>(
  (ref) async => streetsByPartId(
    (await ref.watch(packRepositoryProvider.future)).streets(),
  ),
);
