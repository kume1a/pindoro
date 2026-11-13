import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/core/database/database_file.dart';

void main() {
  late Directory dir;
  late File file;
  late File restored;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pindoro-swap-test');
    file = File('${dir.path}/pindoro.sqlite')..writeAsStringSync('old');
    restored = File('${dir.path}/pindoro.sqlite.restore')
      ..writeAsStringSync('new');
  });

  tearDown(() => dir.delete(recursive: true));

  List<String> files() =>
      dir.listSync().map((f) => f.uri.pathSegments.last).toList()..sort();

  test('boots on the restored file and drops the old one', () async {
    final booted = <String>[];
    await swapInDatabase(
      file,
      restored,
      () async => booted.add(file.readAsStringSync()),
    );
    expect(booted, ['new']);
    expect(files(), ['pindoro.sqlite']);
  });

  test('a restored file that won\'t boot gives the old one back', () async {
    final booted = <String>[];
    await expectLater(
      swapInDatabase(file, restored, () async {
        booted.add(file.readAsStringSync());
        if (booted.length == 1) throw StateError('won\'t open');
      }),
      throwsStateError,
    );
    expect(booted, ['new', 'old']);
    expect(files(), ['pindoro.sqlite']);
    expect(file.readAsStringSync(), 'old');
  });
}
