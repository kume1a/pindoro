import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/features/pack/data/cities.dart';
import 'package:pindoro/features/pack/data/pack_store.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';

void main() {
  final gz = gzip.encode(File(AppConfig.fixturePackAsset).readAsBytesSync());
  final sha = sha256.convert(gz).toString();
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('packs'));
  tearDown(() => root.deleteSync(recursive: true));

  PackStore store(String version, {String? hash, int? size, int format = 1}) =>
      PackStore(
        root: root,
        apiBaseUrl: 'http://api.test',
        client: MockClient(
          (req) async => switch (req.url.path) {
            '/v1/catalog' => http.Response(
              jsonEncode({
                'cities': [
                  {
                    'id': 'tbilisi',
                    'name_ka': 'თბილისი',
                    'name_en': 'Tbilisi',
                    'bbox': {
                      'min_lat': 41.6,
                      'min_lon': 44.6,
                      'max_lat': 41.8,
                      'max_lon': 45,
                    },
                    'pack': {
                      'format_version': format,
                      'version': version,
                      'url': 'http://packs.test/tbilisi/$version.sqlite.gz',
                      'sha256': hash ?? sha,
                      'size': size ?? gz.length,
                      'osm_timestamp': '2026-11-04T21:21:03Z',
                    },
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
            final path when path.endsWith('.sqlite.gz') => http.Response.bytes(
              gz,
              200,
            ),
            _ => http.Response('', 404),
          },
        ),
      );

  List<String> files() =>
      root
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList()
        ..sort();

  test('the catalog lists cities with their bounds', () async {
    final cities = await store('20261105T000000Z').cities();
    expect(cities.single.bbox?.maxLat, 41.8);
    expect(cityAt(cities, const LatLng(41.7, 44.8))?.id, 'tbilisi');
    expect(cityAt(cities, const LatLng(42.2, 42.7)), isNull);
  });

  test('nothing is installed at first', () {
    expect(store('20261106T000000Z').newest('tbilisi'), isNull);
  });

  test('installs a newer pack once', () async {
    final s = store('20261106T000000Z');
    final file = await s.refresh('tbilisi');
    expect(file, isNotNull);
    expect(s.newest('tbilisi')!.path, file!.path);
    expect(await s.refresh('tbilisi'), isNull, reason: 'same version again');
    expect(files(), ['20261106T000000Z.sqlite']);
  });

  test('rejects a sha256 mismatch and leaves nothing behind', () async {
    await expectLater(
      store('20261106T000000Z', hash: '0' * 64).refresh('tbilisi'),
      throwsA(isA<FormatException>()),
    );
    expect(files(), isEmpty);
  });

  test('rejects a size mismatch', () async {
    await expectLater(
      store('20261106T000000Z', size: 1).refresh('tbilisi'),
      throwsA(isA<FormatException>()),
    );
    expect(files(), isEmpty);
  });

  test('skips packs in a newer format', () async {
    expect(
      await store('20261106T000000Z', format: 2).refresh('tbilisi'),
      isNull,
    );
    expect(files(), isEmpty);
  });

  test('keeps the two newest versions', () async {
    for (final v in [
      '20261101T000000Z',
      '20261102T000000Z',
      '20261103T000000Z',
    ]) {
      await store(v).refresh('tbilisi');
    }
    expect(files(), ['20261102T000000Z.sqlite', '20261103T000000Z.sqlite']);
  });

  test('the active pack downloads when missing', () async {
    TestWidgetsFlutterBinding.ensureInitialized(); // rootBundle
    final c = ProviderContainer(
      overrides: [
        packStoreProvider.overrideWithValue(store('20261106T000000Z')),
      ],
    );
    addTearDown(c.dispose);
    final seen = <int>[];
    c.listen(packDownloadProvider, (_, p) {
      if (p != null) seen.add(p.received);
    });
    await c.read(packRepositoryProvider.future);
    expect(files(), ['20261106T000000Z.sqlite']);
    expect(seen.last, gz.length);
    expect(c.read(packDownloadProvider), isNull);
  });

  test('offline, another city fails instead of falling back', () async {
    final offline = PackStore(
      root: root,
      apiBaseUrl: 'http://api.test',
      client: MockClient((_) async => throw const SocketException('offline')),
    );
    await expectLater(
      downloadPack(offline, 'batumi'),
      throwsA(isA<PackUnavailable>()),
    );
  });

  test('offline, the active pack falls back to the bundled fixture', () async {
    TestWidgetsFlutterBinding.ensureInitialized(); // rootBundle
    final offline = PackStore(
      root: root,
      apiBaseUrl: 'http://api.test',
      client: MockClient((_) async => throw const SocketException('offline')),
    );
    final c = ProviderContainer(
      overrides: [packStoreProvider.overrideWithValue(offline)],
    );
    addTearDown(c.dispose);
    final pack = await c.read(packRepositoryProvider.future);
    expect(pack.meta()['scope'], 'fixture');
    expect(files(), ['tbilisi_vake_fixture.sqlite']);
  });
}
