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
  List<Street> streetsNamed(Set<String> names) {
    if (names.isEmpty) return const [];
    final marks = List.filled(names.length, '?').join(', ');
    return [
      for (final r in _db.select(
        'SELECT * FROM street WHERE name_ka IN ($marks) ORDER BY id',
        names.toList(),
      ))
        Street.fromRow(r),
    ];
  }

  @override
  ({Set<String> city, Map<String, Set<String>> byDistrict}) streetNameIndex() {
    final byDistrict = <String, Set<String>>{};
    for (final r in _db.select(
      'SELECT sd.district_id, s.name_ka FROM street_district sd '
      'JOIN street s ON s.id = sd.street_id',
    )) {
      byDistrict
          .putIfAbsent(r['district_id'] as String, () => {})
          .add(r['name_ka'] as String);
    }
    return (
      city: {
        for (final r in _db.select('SELECT DISTINCT name_ka FROM street'))
          r['name_ka'] as String,
      },
      byDistrict: byDistrict,
    );
  }

  @override
  List<StreetDistrict> streetDistricts(String streetId) => [
    for (final r in _db.select(
      'SELECT * FROM street_district WHERE street_id = ?',
      [streetId],
    ))
      StreetDistrict.fromRow(r),
  ];

  @override
  Map<String, String> streetNames(Iterable<String> ids) {
    final list = ids.toList();
    if (list.isEmpty) return const {};
    final marks = List.filled(list.length, '?').join(', ');
    return {
      for (final r in _db.select(
        'SELECT id, name_ka FROM street WHERE id IN ($marks)',
        list,
      ))
        r['id'] as String: r['name_ka'] as String,
    };
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

/// The chosen city's newest pack: downloaded on first use; the bundled
/// fixture stands in for Tbilisi offline. main() invalidates it when a
/// download finishes.
final packRepositoryProvider = FutureProvider<PackRepository>((ref) async {
  final store = ref.watch(packStoreProvider);
  final city =
      ref.watch(settingsProvider.select((s) => s.value?.lastCity)) ??
      AppConfig.cityId;
  final file =
      store.newest(city) ??
      await store.refresh(city).catchError((Object _) => null) ??
      await copyFixture(store.root);
  final repo = SqlitePackRepository.open(file.path);
  ref.onDispose(repo.close);
  return repo;
});
