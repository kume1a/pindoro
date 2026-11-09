import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

/// Installs the packs listed by `/v1/catalog` as `<root>/<city>/<version>.sqlite`.
class PackStore {
  PackStore({
    required this.root,
    required this.apiBaseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  static const int supportedFormatVersion = 3;
  static const int keptVersions = 2;

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
  /// [onProgress] hears about every chunk of the download.
  Future<File?> refresh(
    String city, {
    void Function(PackProgress progress)? onProgress,
  }) async {
    final pack = await _catalogPack(city);
    if (pack == null || pack.formatVersion > supportedFormatVersion) {
      return null;
    }
    final current = newest(city);
    if (current != null && _version(current).compareTo(pack.version) >= 0) {
      return null;
    }
    final installed = await _install(
      city,
      pack,
      await _download(pack, onProgress),
    );
    for (final old in _installed(city).skip(keptVersions)) {
      old.deleteSync();
    }
    return installed;
  }

  /// The pack's .gz, checked against the catalog's size and sha256.
  Future<Uint8List> _download(
    CatalogPack pack,
    void Function(PackProgress progress)? onProgress,
  ) async {
    // ponytail: whole pack in memory (~1 MB gz); stream to disk past a few MB.
    final uri = Uri.parse(pack.url);
    final res = await _client.send(http.Request('GET', uri)).timeout(timeout);
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}', uri: uri);
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in res.stream.timeout(timeout)) {
      bytes.add(chunk);
      onProgress?.call((
        city: pack.city,
        received: bytes.length,
        total: pack.size,
      ));
    }
    final gz = bytes.takeBytes();
    if (gz.length != pack.size) {
      throw FormatException('size ${gz.length} != ${pack.size}');
    }
    if (sha256.convert(gz).toString() != pack.sha256) {
      throw const FormatException('sha256 mismatch');
    }
    return gz;
  }

  /// Unpacks [gz] as `<city>/<version>.sqlite`; nothing partial is left.
  Future<File> _install(String city, CatalogPack pack, Uint8List gz) async {
    final dir = _cityDir(city)..createSync(recursive: true);
    // Unique per call, so overlapping refreshes never share a temp file.
    final tmp = File(
      _join(
        dir.path,
        '${pack.version}.${DateTime.now().microsecondsSinceEpoch}.download',
      ),
    );
    try {
      await tmp.writeAsBytes(gzip.decode(gz), flush: true);
      if (_formatVersion(tmp) != supportedFormatVersion) {
        throw const FormatException('unsupported pack format');
      }
      return await tmp.rename(_join(dir.path, '${pack.version}.sqlite'));
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
    }
  }

  /// Installed packs of [city], newest first.
  List<File> _installed(String city) {
    final dir = _cityDir(city);
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sqlite'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
  }

  Directory _cityDir(String city) => Directory(_join(root.path, city));

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

  Future<List<Map<String, Object?>>> _catalogCities() async {
    final uri = Uri.parse('$apiBaseUrl/v1/catalog');
    final res = await _client.get(uri).timeout(timeout);
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}', uri: uri);
    }
    final catalog =
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, Object?>;
    return (catalog['cities']! as List<Object?>).cast<Map<String, Object?>>();
  }

  Future<CatalogPack?> _catalogPack(String city) async {
    for (final entry in await _catalogCities()) {
      if (entry['id'] != city) continue;
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
    return null;
  }
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
