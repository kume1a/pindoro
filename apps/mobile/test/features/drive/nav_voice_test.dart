import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/features/drive/ui/nav_voice.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

void main() {
  final words = NavWords(
    lookupAppLocalizations(const Locale('en')),
    georgian: false,
  );
  String prepare(double m) => words.words((
    kind: PromptKind.prepare,
    decision: null,
    distanceM: m,
    street: null,
    district: null,
    headingDeg: null,
    limitKmh: null,
  ), DriveLevel.guided);

  test('a distance in kilometres is said as people say it', () {
    expect(prepare(1020), contains('In 1 kilometre,'));
    expect(prepare(1520), contains('In 1.5 kilometres'));
    expect(prepare(200), contains('In 200 metres'));
  });
}
