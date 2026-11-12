import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/pack/data/pack_store.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:sqlite3/sqlite3.dart';

/// Reads a city pack (docs/pack-format.md) opened read-only. A pack never
/// changes, so its meta, city, districts and district links are decoded
/// once.
class SqlitePackRepository implements PackRepository {
  SqlitePackRepository.open(String path)
    : _db = sqlite3.open(path, mode: OpenMode.readOnly);

  final Database _db;

  late final Map<String, String> _meta = {
    for (final r in _db.select('SELECT key, value FROM meta'))
      r['key'] as String: r['value'] as String,
  };

  late final City _city = City.fromRow(
    _db.select('SELECT * FROM city LIMIT 1').first,
  );

  late final List<District> _districts = List.unmodifiable([
    for (final r in _db.select('SELECT * FROM district ORDER BY name_ka'))
      District.fromRow(r),
  ]);

  @override
  Map<String, String> meta() => _meta;

  @override
  City city() => _city;

  @override
  List<District> districts() => _districts;

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
  Map<String, Set<String>> partsByDistrict() => _partsByDistrict;

  late final Map<String, Set<String>> _partsByDistrict = Map.unmodifiable({
    for (final MapEntry(:key, :value) in lengthsByDistrict().entries)
      key: Set<String>.unmodifiable(value.keys),
  });

  @override
  Map<String, Map<String, double>> lengthsByDistrict() => _lengthsByDistrict;

  late final Map<String, Map<String, double>> _lengthsByDistrict = () {
    final byDistrict = <String, Map<String, double>>{};
    for (final r in _db.select(
      'SELECT district_id, street_id, length_m FROM street_district',
    )) {
      byDistrict.putIfAbsent(
        r['district_id'] as String,
        () => {},
      )[r['street_id'] as String] = (r['length_m'] as num)
          .toDouble();
    }
    return Map<String, Map<String, double>>.unmodifiable({
      for (final MapEntry(:key, :value) in byDistrict.entries)
        key: Map<String, double>.unmodifiable(value),
    });
  }();

  /// Format 3 only; built once (the graph is about 16 000 edges for Tbilisi).
  late final RoadGraph? _graph = () {
    final hasGraph = _db
        .select(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'road_edge'",
        )
        .isNotEmpty;
    if (!hasGraph) return null;
    return RoadGraph(
      {
        for (final r in _db.select('SELECT id, lat, lon FROM junction'))
          r['id'] as int: LatLng(
            (r['lat'] as num).toDouble(),
            (r['lon'] as num).toDouble(),
          ),
      },
      [
        for (final r in _db.select('SELECT * FROM road_edge ORDER BY id'))
          RoadEdge.fromRow(r),
      ],
    );
  }();

  @override
  RoadGraph? roadGraph() => _graph;

  @override
  void close() => _db.close();
}

/// Copies the bundled Vake fixture next to downloaded packs, again whenever
/// an app update ships a different one.
Future<File> copyFixture(Directory root) async {
  final file = File('${root.path}/tbilisi_vake_fixture.sqlite');
  final data = await rootBundle.load(AppConfig.fixturePackAsset);
  // ponytail: size stands in for a checksum; the fixture changes rarely.
  if (file.existsSync() && file.lengthSync() == data.lengthInBytes) {
    return file;
  }
  final tmp = File('${file.path}.tmp');
  await tmp.create(recursive: true);
  await tmp.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
  return tmp.rename(file.path);
}

/// The bundled Vake pack's city (the whole Tbilisi row).
Future<City> fixtureCity(Directory root) async {
  final pack = SqlitePackRepository.open((await copyFixture(root)).path);
  try {
    return pack.city();
  } finally {
    pack.close();
  }
}

/// A city with no pack on the phone whose download failed: offline, or
/// [noSpace] when the phone is full, or [needsUpdate] when only a newer app
/// reads the server's pack.
class PackUnavailable implements Exception {
  const PackUnavailable(
    this.city, {
    this.noSpace = false,
    this.needsUpdate = false,
  });

  final String city;
  final bool noSpace;
  final bool needsUpdate;
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

  void report(PackProgress progress) => state = progress;

  /// Ends [city]'s progress; a download of another city keeps its own.
  void done(String city) {
    if (state?.city.id == city) state = null;
  }
}

/// The chosen city's newest pack: downloaded on first use (progress in
/// [packDownloadProvider]); a failed download throws [PackUnavailable], and
/// the bundled fixture stands in for Tbilisi once the player picks it
/// ([offlineVakeProvider]). main() invalidates it when a background download
/// finishes. Failures wait for the player's Try again instead of retrying
/// behind their back.
final packRepositoryProvider = FutureProvider<PackRepository>((ref) async {
  final store = ref.watch(packStoreProvider);
  final city = await ref.watch(settingsProvider.selectAsync((s) => s.cityId));
  final offlineVake = ref.watch(offlineVakeProvider);
  final file =
      store.newest(city) ??
      (offlineVake && city == AppConfig.defaultCityId
          ? await copyFixture(store.root)
          : await _download(ref, store, city));
  // A rebuild (another city, Try again) superseded this one.
  if (!ref.mounted) throw StateError('superseded pack load for $city');
  final repo = SqlitePackRepository.open(file.path);
  ref.read(_openPacksProvider).add(repo);
  return repo;
}, retry: (_, _) => null);

/// Downloads [city]'s pack, reporting progress while this load is current.
Future<File> _download(Ref ref, PackStore store, String city) {
  final progress = ref.read(packDownloadProvider.notifier);
  return downloadPack(
    store,
    city,
    onProgress: (p) {
      if (ref.mounted) progress.report(p);
    },
  ).whenComplete(() => progress.done(city));
}

/// Every pack opened this session, closed with the app. Screens and rounds
/// keep using the previous pack while a replacement loads, so none closes
/// earlier.
// ponytail: a session opens one or two extra read-only handles at most.
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
  } on PackFormatTooNew {
    throw PackUnavailable(city, needsUpdate: true);
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

/// The pack's version, stored on rounds and answers.
String packVersion(PackRepository pack) => pack.meta()['version']!;

/// The active pack's streets as the player sees them, by any part id.
final cityStreetsProvider = FutureProvider<Map<String, NamedStreet>>(
  (ref) async => streetsByPartId(
    (await ref.watch(packRepositoryProvider.future)).streets(),
  ),
);

/// Opens [cityId]'s newest installed pack for [read] and closes it after;
/// null when the phone has none. Never downloads.
Future<T?> readInstalledPack<T>(
  PackStore store,
  String cityId,
  Future<T> Function(PackRepository pack, Map<String, NamedStreet> streets)
  read,
) async {
  final file = store.newest(cityId);
  if (file == null) return null;
  final pack = SqlitePackRepository.open(file.path);
  try {
    return await read(pack, streetsByPartId(pack.streets()));
  } finally {
    pack.close();
  }
}

/// An open pack and its streets as the player sees them.
typedef OpenPack = ({PackRepository pack, Map<String, NamedStreet> streets});

/// The active [pack] once it and its [streets] are loaded, else null.
OpenPack? openPackOf(
  AsyncValue<PackRepository> pack,
  AsyncValue<Map<String, NamedStreet>> streets,
) => switch ((pack.value, streets.value)) {
  (final pack?, final streets?) => (pack: pack, streets: streets),
  _ => null,
};

/// [read] over each of [cityIds]' packs, in order: [open] for its own city,
/// else the city's newest installed pack in [store], opened just for this
/// (the store is only read then). A city with no pack on the phone is left
/// out. Never downloads.
Future<List<T>> readCityPacks<T>(
  PackStore Function() store,
  Iterable<String> cityIds,
  Future<T> Function(PackRepository pack, Map<String, NamedStreet> streets)
  read, {
  OpenPack? open,
}) async => [
  for (final id in cityIds)
    if (open != null && open.pack.city().id == id)
      await read(open.pack, open.streets)
    else
      ?await readInstalledPack(store(), id, read),
];

/// The active pack's road graph; null for a pack older than format 3.
final roadGraphProvider = FutureProvider<RoadGraph?>(
  (ref) async => (await ref.watch(packRepositoryProvider.future)).roadGraph(),
);
