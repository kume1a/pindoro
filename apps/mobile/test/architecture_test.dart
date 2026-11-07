import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lowest first. A file may import its own slice, or a slice on a lower layer.
const _layers = <Set<String>>[
  {'l10n'},
  {'core'},
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

void main() {
  test('lib imports only point down the layers', () {
    final violations = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      final from = file.path.replaceAll(r'\', '/').substring('lib/'.length);
      final fromSlice = _slice(from);
      for (final match in _pindoroImport.allMatches(file.readAsStringSync())) {
        final to = _slice(match[1]!);
        if (to != fromSlice && _layer(to) >= _layer(fromSlice)) {
          violations.add('$from imports ${match[1]}');
        }
      }
    }
    expect(violations, isEmpty);
  });
}
