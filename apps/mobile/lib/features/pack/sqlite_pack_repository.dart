import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../app/config.dart';

/// Reads a city pack (docs/pack-format.md) opened read-only.
class SqlitePackRepository implements PackRepository {
  SqlitePackRepository.open(String path)
    : _db = sqlite3.open(path, mode: OpenMode.readOnly);

  /// Opens the bundled Vake fixture, copying it to app documents first.
  // ponytail: copied once; M1 replaces the fixture with downloaded packs.
  static Future<SqlitePackRepository> openFixture() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/packs/tbilisi_vake_fixture.sqlite');
    if (!file.existsSync()) {
      final data = await rootBundle.load(AppConfig.fixturePackAsset);
      await file.create(recursive: true);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    return SqlitePackRepository.open(file.path);
  }

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
  List<StreetDistrict> streetDistricts(String streetId) => [
    for (final r in _db.select(
      'SELECT * FROM street_district WHERE street_id = ?',
      [streetId],
    ))
      StreetDistrict.fromRow(r),
  ];

  @override
  void close() => _db.close();
}

final packRepositoryProvider = FutureProvider<PackRepository>((ref) async {
  final repo = await SqlitePackRepository.openFixture();
  ref.onDispose(repo.close);
  return repo;
});
