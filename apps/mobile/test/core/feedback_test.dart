import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/core/sounds.dart';
import 'package:pindoro_core/pindoro_core.dart';

class _FakeSounds implements Sounds {
  final played = <(Sound, double)>[];

  @override
  Future<void> load() async {}

  @override
  void play(Sound sound, {double speed = 1}) => played.add((sound, speed));
}

void main() {
  test('every sound in the kit has its asset', () {
    for (final sound in Sound.values) {
      final file = File('assets/${sound.path}');
      expect(file.existsSync(), isTrue, reason: file.path);
    }
    expect(Sound.levelupFanfare.path, 'sounds/levelup_fanfare.wav');
  });

  test('sounds play per event behind the Sound toggle', () {
    final sounds = _FakeSounds();
    GameFeedback(sounds: sounds, haptics: false, sound: false)
      ..tier(Tier.perfect)
      ..pinDrop()
      ..press();
    expect(sounds.played, isEmpty);

    GameFeedback(sounds: sounds, haptics: false, sound: true)
      ..tier(Tier.perfect)
      ..tier(Tier.miss)
      ..tap()
      ..press();
    expect(sounds.played.map((p) => p.$1), [
      Sound.tierPerfect,
      Sound.tierMiss,
      Sound.tap,
    ]);
  });

  testWidgets('a count-up ticks ten times, rising, within motion.count-up', (
    tester,
  ) async {
    final sounds = _FakeSounds();
    GameFeedback(
      sounds: sounds,
      haptics: false,
      sound: true,
    ).countUp(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 199));
    expect(sounds.played, isEmpty);
    await tester.pump(const Duration(milliseconds: 901));
    expect(sounds.played, hasLength(10));
    expect(sounds.played.every((p) => p.$1 == Sound.countTick), isTrue);
    expect(sounds.played.first.$2, 1);
    expect(sounds.played.last.$2, 1.5);
  });

  testWidgets('a stopped count-up ticks no more', (tester) async {
    final sounds = _FakeSounds();
    final stop = GameFeedback(
      sounds: sounds,
      haptics: false,
      sound: true,
    ).countUp(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 250));
    final ticked = sounds.played.length;
    stop();
    await tester.pump(const Duration(seconds: 2));
    expect(ticked, inInclusiveRange(1, 9));
    expect(sounds.played, hasLength(ticked));
  });
}
