import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pindoro/features/pack/data/app_update.dart';
import 'package:pindoro/features/pack/data/pack_store.dart';

void main() {
  const apk = 'https://packs.test/app/pindoro-3.apk';

  Future<Uri?> update({required String installed, Object? app}) {
    PackageInfo.setMockInitialValues(
      appName: 'Pindoro',
      packageName: 'app.pindoro',
      version: '2.1.0',
      buildNumber: installed,
      buildSignature: '',
    );
    final store = PackStore(
      root: Directory.systemTemp,
      apiBaseUrl: 'http://api.test',
      client: MockClient(
        (_) async =>
            http.Response(jsonEncode({'app': ?app, 'cities': <Object>[]}), 200),
      ),
    );
    final container = ProviderContainer(
      overrides: [packStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    return container.read(appUpdateProvider.future);
  }

  test('offers a newer build than the installed one', () async {
    expect(
      await update(installed: '2', app: {'build': 3, 'url': apk}),
      Uri.parse(apk),
    );
  });

  test(
    'offers nothing when this build is the newest or none is listed',
    () async {
      expect(
        await update(installed: '3', app: {'build': 3, 'url': apk}),
        isNull,
      );
      expect(await update(installed: '2'), isNull);
    },
  );
}
