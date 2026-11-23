import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/features/drive/ui/nav_voice.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
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
    expect(prepare(985), contains('In 1 kilometre,'), reason: 'not 950 m');
    expect(prepare(970), contains('In 950 metres'));
    expect(prepare(10), contains('In 50 metres'));
  });

  test('lines are said one at a time, in order; an action line drops the '
      'lesser ones waiting', () async {
    final said = <String>[];
    final gates = <Completer<void>>[];
    final speaking = <bool>[];
    var talking = 0;
    var most = 0;
    final queue = SpeechQueue((text) async {
      most = max(most, ++talking);
      said.add(text);
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
      talking--;
    }, onSpeaking: speaking.add);
    Future<void> next() async {
      gates.last.complete();
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    unawaited(queue.add('prepare', kind: PromptKind.prepare));
    unawaited(queue.add('camera', kind: PromptKind.camera));
    unawaited(queue.add('district', kind: PromptKind.district));
    final done = queue.add('action', kind: PromptKind.action);
    expect(said, ['prepare']);
    await next();
    expect(said, ['prepare', 'camera']);
    await next();
    expect(said, ['prepare', 'camera', 'action'], reason: 'district dropped');
    await next();
    await done;
    expect(most, 1);
    expect(speaking, [true, false]);
  });

  test('a district cue names its district by id in the voice’s script, and '
      'says which street it names', () {
    const vake = District(
      id: 'r1',
      kind: DistrictKind.district,
      osmRelationId: null,
      nameKa: 'ვაკის რაიონი',
      nameEn: 'Vake District',
      center: LatLng(41.7, 44.75),
      bbox: Bbox(41.69, 44.74, 41.71, 44.76),
      areaM2: 1,
      boundary: [],
    );
    NavPrompt cue(String id) => (
      kind: PromptKind.district,
      decision: null,
      distanceM: null,
      street: null,
      district: id,
      headingDeg: 90,
      limitKmh: null,
    );
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(
      NavWords(
        l10n,
        georgian: false,
        districts: {'r1': vake},
      ).words(cue('r1'), DriveLevel.coached),
      'Into Vake District, heading east.',
    );
    expect(
      NavWords(
        l10n,
        georgian: true,
        districts: {'r1': vake},
      ).words(cue('r1'), DriveLevel.coached),
      contains('ვაკის რაიონი'),
    );
    expect(NavWords.streetSaid(cue('r1')), isNull);
  });
}
