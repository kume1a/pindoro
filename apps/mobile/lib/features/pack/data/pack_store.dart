import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pindoro_core/pindoro_core.dart';
import 'package:sqlite3/sqlite3.dart';

/// Overridden in main() with the app documents directory.
final packStoreProvider = Provider<PackStore>(
  (ref) => throw UnimplementedError('packStoreProvider must be overridden'),
);

/// A city the server has a pack for; [bbox] is null for packs published
/// before manifests carried it.
typedef CatalogCity = ({String id, String nameKa, String nameEn, Bbox? bbox});

/// A pack download under way: bytes received of the .gz's size.
typedef PackProgress = ({CatalogCity city, int received, int total});

typedef CatalogPack = ({
  CatalogCity city,
  String version,
  String url,
  String sha256,
  int size,
  int formatVersion,
});

/// The newest sideload build the server offers, and where to download it.
typedef AppRelease = ({int build, Uri url});

/// The catalog's pack is in a newer format than this build reads.
class PackFormatTooNew implements Exception {
  const PackFormatTooNew();
}

/// Installs the packs listed by `/v1/catalog` as `<root>/<city>/<version>.sqlite`.
class PackStore {
  PackStore({
    required this.root,
    required this.apiBaseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  static const int supportedFormatVersion = 5;

  /// Format 3 packs still install while the server catches up; learning
  /// waits for format 4.
  static const int oldestFormatVersion = 3;
  static const int keptVersions = 2;
  static const int photosFormatVersion = 1;

  /// Longest wait for the server, and between two chunks of a download.
  final Duration timeout;

  final Directory root;
  final String apiBaseUrl;
  final http.Client _client;

  /// Newest installed pack of [city]; versions sort lexically.
  File? newest(String city) => _installed(city).firstOrNull;

  /// Installs the catalog's pack for [city] when it is newer than the newest
  /// installed one. Returns the new file, or null when there was nothing to do.
  /// Throws on network or verification failures; nothing partial is left.
  /// Throws [PackFormatTooNew] when only a newer app can read the pack.
  /// [onProgress] hears 0 bytes once the catalog answers, then every chunk.
  Future<File?> refresh(
    String city, {
    void Function(PackProgress progress)? onProgress,
  }) async {
    final pack = await _catalogPack(city);
    if (pack == null) return null;
    if (pack.formatVersion > supportedFormatVersion) {
      throw const PackFormatTooNew();
    }
    final current = newest(city);
    if (current != null && _version(current).compareTo(pack.version) >= 0) {
      return null;
    }
    onProgress?.call((city: pack.city, received: 0, total: pack.size));
    final dir = _cityDir(city)..createSync(recursive: true);
    final gz = _temp(dir, pack.version);
    final File installed;
    try {
      await _downloadTo(
        gz,
        url: pack.url,
        size: pack.size,
        sha: pack.sha256,
        onProgress: (received) => onProgress?.call((
          city: pack.city,
          received: received,
          total: pack.size,
        )),
      );
      // ponytail: gunzipped in memory (~1 MB gz); stream it past a few MB.
      installed = await _install(city, pack, await gz.readAsBytes());
    } finally {
      if (gz.existsSync()) gz.deleteSync();
    }
    for (final old in _installed(city).skip(keptVersions)) {
      old.deleteSync();
    }
    return installed;
  }

  /// Streams [url] into [dest], checked against [size] and [sha]; throws
  /// on a mismatch, a non-200 answer or a stall.
  Future<void> _downloadTo(
    File dest, {
    required String url,
    required int size,
    required String sha,
    void Function(int received)? onProgress,
  }) async {
    final uri = Uri.parse(url);
    final res = await _client.send(http.Request('GET', uri)).timeout(timeout);
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}', uri: uri);
    }
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    final out = dest.openWrite();
    var received = 0;
    try {
      await for (final chunk in res.stream.timeout(timeout)) {
        hasher.add(chunk);
        out.add(chunk);
        received += chunk.length;
        onProgress?.call(received);
      }
    } finally {
      await out.close();
    }
    hasher.close();
    if (received != size) {
      throw FormatException('size $received != $size');
    }
    if (digest.value.toString() != sha) {
      throw const FormatException('sha256 mismatch');
    }
  }

  /// A download's file in [dir], unique per call so overlapping refreshes
  /// never share one.
  File _temp(Directory dir, String version) => File(
    _join(
      dir.path,
      '$version.${DateTime.now().microsecondsSinceEpoch}.download',
    ),
  );

  /// Unpacks [gz] as `<city>/<version>.sqlite`; nothing partial is left.
  Future<File> _install(String city, CatalogPack pack, Uint8List gz) async {
    final tmp = _temp(_cityDir(city), '${pack.version}.sqlite');
    try {
      await tmp.writeAsBytes(gzip.decode(gz), flush: true);
      final format = _formatVersion(tmp) ?? 0;
      if (format < oldestFormatVersion || format > supportedFormatVersion) {
        throw const FormatException('unsupported pack format');
      }
      return await tmp.rename(
        _join(_cityDir(city).path, '${pack.version}.sqlite'),
      );
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
    }
  }

  /// Installed packs of [city], newest first.
  List<File> _installed(String city) => _sqliteFiles(_cityDir(city));

  /// The `.sqlite` files directly in [dir], newest version first.
  static List<File> _sqliteFiles(Directory dir) {
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sqlite'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
  }

  Directory _cityDir(String city) => Directory(_join(root.path, city));

  Directory _photosDir(String city) =>
      Directory(_join(_cityDir(city).path, 'photos'));

  /// The installed photo pack of [city] (SPEC §10), if any.
  File? photos(String city) => _sqliteFiles(_photosDir(city)).firstOrNull;

  /// Installs the catalog's photo pack for [city] as
  /// `<city>/photos/<version>.sqlite` when it is newer than the installed
  /// one, streamed to disk, and keeps only it. Returns the photo pack, or
  /// null when the server has none for [city]. Throws like [refresh].
  Future<File?> refreshPhotos(
    String city, {
    void Function(PackProgress progress)? onProgress,
  }) async {
    final entry = await _catalogEntry(city);
    final photos = entry?['photos'] as Map<String, Object?>?;
    if (entry == null || photos == null) return null;
    if (photos['format_version']! as int > photosFormatVersion) {
      throw const PackFormatTooNew();
    }
    final version = photos['version']! as String;
    final current = this.photos(city);
    if (current != null && _version(current).compareTo(version) >= 0) {
      return current;
    }
    final size = photos['size']! as int;
    final dir = _photosDir(city)..createSync(recursive: true);
    final tmp = _temp(dir, version);
    try {
      onProgress?.call((city: _city(entry), received: 0, total: size));
      await _downloadTo(
        tmp,
        url: photos['url']! as String,
        size: size,
        sha: photos['sha256']! as String,
        onProgress: (received) => onProgress?.call((
          city: _city(entry),
          received: received,
          total: size,
        )),
      );
      final installed = await tmp.rename(_join(dir.path, '$version.sqlite'));
      for (final old in _sqliteFiles(dir).skip(1)) {
        old.deleteSync();
      }
      return installed;
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
    }
  }

  /// Deletes [city]'s photo pack (Street photos off).
  void removePhotos(String city) {
    final dir = _photosDir(city);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  /// Every city the server has a pack for.
  Future<List<CatalogCity>> cities() async => [
    for (final entry in await _catalogCities()) _city(entry),
  ];

  static CatalogCity _city(Map<String, Object?> entry) => (
    id: entry['id']! as String,
    nameKa: entry['name_ka']! as String,
    nameEn: entry['name_en']! as String,
    bbox: Bbox.tryParse(entry['bbox']),
  );

  /// The newest sideload build the catalog lists, if any.
  Future<AppRelease?> latestApp() async {
    final app = (await _catalog())['app'] as Map<String, Object?>?;
    if (app == null) return null;
    return (build: app['build']! as int, url: Uri.parse(app['url']! as String));
  }

  Future<Map<String, Object?>> _catalog() async {
    final uri = Uri.parse('$apiBaseUrl/v1/catalog');
    final res = await _client.get(uri).timeout(timeout);
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}', uri: uri);
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, Object?>;
  }

  Future<List<Map<String, Object?>>> _catalogCities() async =>
      ((await _catalog())['cities']! as List<Object?>)
          .cast<Map<String, Object?>>();

  Future<Map<String, Object?>?> _catalogEntry(String city) async =>
      (await _catalogCities()).where((e) => e['id'] == city).firstOrNull;

  Future<CatalogPack?> _catalogPack(String city) async {
    final entry = await _catalogEntry(city);
    if (entry == null) return null;
    final p = entry['pack']! as Map<String, Object?>;
    return (
      city: _city(entry),
      version: p['version']! as String,
      url: p['url']! as String,
      sha256: p['sha256']! as String,
      size: p['size']! as int,
      formatVersion: p['format_version']! as int,
    );
  }
}

/// Holds the digest a chunked hash ends with.
class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Native separators, so built paths equal the ones `listSync()` returns.
String _join(String dir, String name) => '$dir${Platform.pathSeparator}$name';

String _version(File pack) =>
    pack.uri.pathSegments.last.replaceFirst('.sqlite', '');

int? _formatVersion(File pack) {
  final db = sqlite3.open(pack.path, mode: OpenMode.readOnly);
  try {
    final rows = db.select(
      "SELECT value FROM meta WHERE key = 'format_version'",
    );
    return rows.isEmpty ? null : int.tryParse(rows.first['value'] as String);
  } finally {
    db.close();
  }
}

/// Background refresh: true when a new pack was installed. Failures keep the
/// current pack and are logged in debug builds only.
/// Only updates an installed pack: a first download is the pack provider's.
Future<bool> refreshQuietly(PackStore store, String city) async {
  if (store.newest(city) == null) return false;
  try {
    return await store.refresh(city) != null;
  } catch (e) {
    if (kDebugMode) debugPrint('pack refresh failed: $e');
    return false;
  }
}
