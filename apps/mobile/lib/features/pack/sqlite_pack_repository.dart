import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../app/config.dart';
import '../../app/settings.dart';
import 'pack_store.dart';

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

/// A city with no pack on the phone whose download failed.
class PackUnavailable implements Exception {
  const PackUnavailable(this.city);

  final String city;
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
/// [packDownloadProvider]); offline, the bundled fixture stands in for
/// Tbilisi and other cities fail with [PackUnavailable]. main() invalidates
/// it when a background download finishes.
final packRepositoryProvider = FutureProvider<PackRepository>((ref) async {
  final store = ref.watch(packStoreProvider);
  final city =
      ref.watch(settingsProvider.select((s) => s.value?.lastCity)) ??
      AppConfig.cityId;
  final progress = ref.read(packDownloadProvider.notifier);
  final file =
      store.newest(city) ??
      await downloadPack(
        store,
        city,
        onProgress: progress.report,
      ).whenComplete(() => progress.report(null));
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
});

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

/// Downloads [city]'s pack; offline, Tbilisi falls back to the bundled
/// fixture and other cities throw [PackUnavailable].
Future<File> downloadPack(
  PackStore store,
  String city, {
  void Function(PackProgress progress)? onProgress,
}) async {
  final file = await store
      .refresh(city, onProgress: onProgress)
      .catchError((Object _) => null);
  if (file != null) return file;
  if (city == AppConfig.cityId) return copyFixture(store.root);
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
