import 'dart:io';

import 'package:flutter/foundation.dart';
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

  bool _hasTable(String name) => _db.select(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
    [name],
  ).isNotEmpty;

  /// Format 3 and later; built once (the graph is about 16 000 edges for
  /// Tbilisi). From format 5 it is directed, with turn restrictions.
  late final RoadGraph? _graph = () {
    if (!_hasTable('road_edge')) return null;
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
      restrictions: [
        if (_hasTable('turn_restriction'))
          for (final r in _db.select('SELECT * FROM turn_restriction'))
            (
              fromEdge: r['from_edge'] as int,
              via: r['via_junction'] as int,
              toEdge: r['to_edge'] as int,
              only: r['only'] == 1,
            ),
      ],
    );
  }();

  @override
  RoadGraph? roadGraph() => _graph;

  @override
  List<FamilyLink> families() => _families;

  late final List<FamilyLink> _families = List.unmodifiable([
    if (_hasTable('family'))
      for (final r in _db.select('SELECT * FROM family')) familyLinkFromRow(r),
  ]);

  @override
  Map<String, Set<String>> chunkNeighbours() => _chunkNeighbours;

  late final Map<String, Set<String>> _chunkNeighbours = () {
    final byChunk = <String, Set<String>>{};
    if (_hasTable('chunk_neighbour')) {
      for (final r in _db.select(
        'SELECT chunk_a, chunk_b FROM chunk_neighbour',
      )) {
        byChunk
            .putIfAbsent(r['chunk_a'] as String, () => {})
            .add(r['chunk_b'] as String);
      }
    }
    return Map<String, Set<String>>.unmodifiable(byChunk);
  }();

  @override
  Map<int, int> junctionNodes() => _junctionNodes;

  late final Map<int, int> _junctionNodes = Map.unmodifiable({
    if (_hasTable('junction_item'))
      for (final r in _db.select('SELECT id, node_id FROM junction'))
        r['id'] as int: r['node_id'] as int,
  });

  @override
  List<Bridge> bridges() => _bridges;

  late final List<Bridge> _bridges = List.unmodifiable([
    if (_hasTable('bridge'))
      for (final r in _db.select('SELECT * FROM bridge ORDER BY id'))
        Bridge.fromRow(r),
  ]);

  @override
  List<Landmark> landmarks() => _landmarks;

  late final List<Landmark> _landmarks = List.unmodifiable([
    if (_hasTable('landmark'))
      for (final r in _db.select('SELECT * FROM landmark ORDER BY id'))
        Landmark.fromRow(r),
  ]);

  @override
  List<JunctionItem> junctionItems() => _junctionItems;

  late final List<JunctionItem> _junctionItems = List.unmodifiable([
    if (_hasTable('junction_item'))
      for (final r in _db.select('SELECT * FROM junction_item ORDER BY rank'))
        JunctionItem.fromRow(r),
  ]);

  @override
  void close() => _db.close();
}

/// Copies the bundled Vake fixture next to downloaded packs, again whenever
/// an app update ships a different one.
Future<File> copyFixture(Directory root) async {
  final file = File('${root.path}/tbilisi_vake_fixture.sqlite');
  final data = await rootBundle.load(AppConfig.fixturePackAsset);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  // SQLite files grow by whole pages, so a new fixture often has the old size.
  if (file.existsSync() && listEquals(file.readAsBytesSync(), bytes)) {
    return file;
  }
  final tmp = File('${file.path}.tmp');
  await tmp.create(recursive: true);
  await tmp.writeAsBytes(bytes, flush: true);
  return tmp.rename(file.path);
}

/// Why a city's pack couldn't download.
enum PackFailure {
  /// The catalog never answered: offline, or the API is down.
  unreachable,

  /// The catalog answered but the pack didn't come: the server's fault.
  server,

  /// Saving the pack failed because the phone is full.
  noSpace,

  /// Only a newer app reads the server's pack.
  needsUpdate,
}

/// A city with no pack on the phone whose download failed, and why.
class PackUnavailable implements Exception {
  const PackUnavailable(this.city, [this.reason = PackFailure.unreachable]);

  final String city;
  final PackFailure reason;

  @override
  String toString() => 'PackUnavailable($city, ${reason.name})';
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
  var catalogAnswered = false;
  try {
    final file = await store.refresh(
      city,
      onProgress: (p) {
        catalogAnswered = true;
        onProgress?.call(p);
      },
    );
    if (file != null) return file;
    // Nothing to download: the catalog doesn't list the city.
    catalogAnswered = true;
  } on PackFormatTooNew {
    throw PackUnavailable(city, PackFailure.needsUpdate);
  } on FileSystemException catch (e) {
    if (e.osError?.errorCode == _noSpaceLeft) {
      throw PackUnavailable(city, PackFailure.noSpace);
    }
    _logFailure(e);
  } on Object catch (e) {
    _logFailure(e);
  }
  throw PackUnavailable(
    city,
    catalogAnswered ? PackFailure.server : PackFailure.unreachable,
  );
}

void _logFailure(Object error) {
  if (kDebugMode) debugPrint('pack download failed: $error');
}

/// Whether [pack] is the bundled Vake-only stand-in.
bool isFixturePack(PackRepository pack) => pack.meta()['scope'] == 'fixture';

/// Whether [state] is downloading the whole city, or has failed to, while the
/// Vake stand-in is still open: screens show that instead of Vake.
bool leavingFixture(AsyncValue<PackRepository> state) =>
    (state.isLoading || state.hasError) &&
    state.hasValue &&
    isFixturePack(state.requireValue);

/// The pack's version, stored on rounds and answers.
String packVersion(PackRepository pack) => pack.meta()['version']!;

/// The active pack's streets as the player sees them, by any part id.
final cityStreetsProvider = FutureProvider<Map<String, NamedStreet>>(
  (ref) async => streetsByPartId(
    (await ref.watch(packRepositoryProvider.future)).streets(),
  ),
);

/// The active pack's road graph; null for a pack older than format 3.
final roadGraphProvider = FutureProvider<RoadGraph?>(
  (ref) async => (await ref.watch(packRepositoryProvider.future)).roadGraph(),
);
