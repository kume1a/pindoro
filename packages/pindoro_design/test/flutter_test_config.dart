import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Goldens are generated on one OS and compared on others (Linux CI), where
/// glyph anti-aliasing differs slightly.
const double _maxGoldenDiffRatio = 0.015;

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadFonts();
  final basedir = (goldenFileComparator as LocalFileComparator).basedir;
  goldenFileComparator = _TolerantComparator(basedir.resolve('golden_test'));
  await testMain();
}

/// Loads every bundled font (FiraGO, MaterialIcons) so goldens show real
/// glyphs; FiraGO is also registered under its package-qualified family name.
Future<void> _loadFonts() async {
  final manifest =
      jsonDecode(await rootBundle.loadString('FontManifest.json'))
          as List<Object?>;
  for (final entry in manifest.cast<Map<String, Object?>>()) {
    final family = entry['family']! as String;
    final assets = [
      for (final f
          in (entry['fonts']! as List<Object?>).cast<Map<String, Object?>>())
        f['asset']! as String,
    ];
    for (final name in {family, 'packages/pindoro_design/$family'}) {
      final loader = FontLoader(name);
      for (final asset in assets) {
        loader.addFont(rootBundle.load(asset));
      }
      await loader.load();
    }
  }
}

class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= _maxGoldenDiffRatio) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
