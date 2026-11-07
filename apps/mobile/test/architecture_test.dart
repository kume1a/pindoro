import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lowest first. A file may import its own slice, or a slice on a lower layer.
const _layers = <Set<String>>[
  {'l10n'},
  {'core'},
  {'features/progress'},
  {'features/pack'},
  {'features/map'},
  {
    'features/home',
    'features/setup',
    'features/quiz',
    'features/results',
    'features/settings',
  },
  {'app'},
  {'main.dart'},
];

final _pindoroImport = RegExp(
  r"^import 'package:pindoro/([^']+)'",
  multiLine: true,
);

/// `features/<name>` for a feature, otherwise the top folder (or `main.dart`).
String _slice(String libPath) {
  final parts = libPath.split('/');
  return parts.first == 'features' ? 'features/${parts[1]}' : parts.first;
}

int _layer(String slice) {
  final layer = _layers.indexWhere((l) => l.contains(slice));
  if (layer < 0) fail('$slice has no layer: add it to _layers in $_self');
  return layer;
}

const _self = 'test/architecture_test.dart';

/// Every Dart file under lib/, by its path there.
Map<String, String> _libSources() => {
  for (final file in Directory(
    'lib',
  ).listSync(recursive: true).whereType<File>())
    if (file.path.endsWith('.dart'))
      file.path.replaceAll(r'\', '/').substring('lib/'.length): file
          .readAsStringSync(),
};

void main() {
  test('lib imports only point down the layers', () {
    final violations = <String>[];
    for (final MapEntry(key: from, value: source) in _libSources().entries) {
      final fromSlice = _slice(from);
      for (final match in _pindoroImport.allMatches(source)) {
        final to = _slice(match[1]!);
        if (to != fromSlice && _layer(to) >= _layer(fromSlice)) {
          violations.add('$from imports ${match[1]}');
        }
      }
    }
    expect(violations, isEmpty);
  });

  test('screens reach the database only through data/ (no Drift in ui/)', () {
    expect([
      for (final MapEntry(key: path, value: source) in _libSources().entries)
        if (path.contains('/ui/') && source.contains("import 'package:drift/"))
          path,
    ], isEmpty);
  });
}
