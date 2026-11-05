import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:sqlite3/sqlite3.dart';

import '../../app/config.dart';

/// Overridden in main() with the app documents directory.
final packStoreProvider = Provider<PackStore>(
  (ref) => throw UnimplementedError('packStoreProvider must be overridden'),
);

typedef CatalogPack = ({
  String version,
  String url,
  String sha256,
  int size,
  int formatVersion,
});

/// Installs the packs listed by `/v1/catalog` as `<root>/<city>/<version>.sqlite`.
class PackStore {
  PackStore({required this.root, required this.apiBaseUrl, http.Client? client})
    : _client = client ?? http.Client();

  static const int supportedFormatVersion = 1;
  static const int keptVersions = 2;

  final Directory root;
  final String apiBaseUrl;
  final http.Client _client;

  /// Newest installed pack of [city]; versions sort lexically.
  File? newest(String city) => _installed(city).firstOrNull;

  /// Installs the catalog's pack for [city] when it is newer than the newest
  /// installed one. Returns the new file, or null when there was nothing to do.
  /// Throws on network or verification failures; nothing partial is left.
  Future<File?> refresh(String city) async {
    final pack = await _catalogPack(city);
    if (pack == null || pack.formatVersion > supportedFormatVersion) {
      return null;
    }
    final current = newest(city);
    if (current != null && _version(current).compareTo(pack.version) >= 0) {
      return null;
    }

    final dir = _cityDir(city)..createSync(recursive: true);
    final tmp = File(_join(dir.path, '${pack.version}.download'));
    try {
      // ponytail: whole pack in memory (~1 MB gz); stream to disk past a few MB.
      final uri = Uri.parse(pack.url);
      final res = await _client.get(uri);
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}', uri: uri);
      }
      final gz = res.bodyBytes;
      if (gz.length != pack.size) {
        throw FormatException('size ${gz.length} != ${pack.size}');
      }
      if (sha256.convert(gz).toString() != pack.sha256) {
        throw const FormatException('sha256 mismatch');
      }
      await tmp.writeAsBytes(gzip.decode(gz), flush: true);
      if (_formatVersion(tmp) != supportedFormatVersion) {
        throw const FormatException('unsupported pack format');
      }
      final installed = await tmp.rename(
        _join(dir.path, '${pack.version}.sqlite'),
      );
      for (final old in _installed(city).skip(keptVersions)) {
        old.deleteSync();
      }
      return installed;
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

  Future<CatalogPack?> _catalogPack(String city) async {
    final uri = Uri.parse('$apiBaseUrl/v1/catalog');
    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}', uri: uri);
    }
    final catalog =
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, Object?>;
    for (final entry
        in (catalog['cities']! as List<Object?>).cast<Map<String, Object?>>()) {
      if (entry['id'] != city) continue;
      final p = entry['pack']! as Map<String, Object?>;
      return (
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
Future<bool> refreshQuietly(PackStore store) async {
  try {
    return await store.refresh(AppConfig.cityId) != null;
  } catch (e) {
    if (kDebugMode) debugPrint('pack refresh failed: $e');
    return false;
  }
}
