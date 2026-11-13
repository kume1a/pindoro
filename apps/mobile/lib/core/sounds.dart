import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The sound kit (canvas M-60): `assets/sounds/<snake_name>.wav`, finished with
/// `just sounds`.
enum Sound {
  tap,
  pinTok,
  confirm,
  tierPerfect,
  tierGreat,
  tierClose,
  tierMiss,
  countTick,
  land,
  levelupFanfare,
  errorSoft,
  launchTok,
  unlock,
  streak;

  /// Relative to `assets/`, as [AssetSource] wants it.
  String get path =>
      'sounds/${name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}')}.wav';
}

/// Ambient on iOS (the ringer switch mutes Pindoro, music keeps playing);
/// game sounds without audio focus on Android, so nothing ducks.
final _mixIn = AudioContext(
  android: const AudioContextAndroid(
    contentType: AndroidContentType.sonification,
    usageType: AndroidUsageType.game,
    audioFocus: AndroidAudioFocus.none,
  ),
  iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
);

/// The kit, preloaded and played with low latency (Android's SoundPool). Silent
/// until [load] finishes, and for good when it fails, so audio never stops a
/// round.
class Sounds {
  final _players = <Sound, AudioPlayer>{};
  final _speeds = <Sound, double>{};

  Future<void> load() async {
    try {
      await AudioPlayer.global.setAudioContext(_mixIn);
      // All at once: launch_tok plays about half a second after launch.
      await Future.wait(
        Sound.values.map((sound) async {
          final player = AudioPlayer();
          await player.setPlayerMode(PlayerMode.lowLatency);
          await player.setReleaseMode(ReleaseMode.stop);
          await player.setSource(AssetSource(sound.path));
          _players[sound] = player;
        }),
      );
    } on Exception catch (e) {
      debugPrint('Sounds off: $e');
    }
  }

  /// Frees the players (a restore starts the app again with a new kit).
  void dispose() {
    for (final player in _players.values) {
      unawaited(player.dispose());
    }
    _players.clear();
  }

  /// Restarts [sound] if it is still playing; [speed] above 1 raises the pitch.
  void play(Sound sound, {double speed = 1}) {
    final player = _players[sound];
    if (player == null) return;
    final setSpeed = _speeds[sound] != speed;
    _speeds[sound] = speed;
    unawaited(() async {
      await player.stop();
      if (setSpeed) await player.setPlaybackRate(speed);
      await player.resume();
    }());
  }
}

final soundsProvider = Provider<Sounds>((ref) {
  final sounds = Sounds();
  ref.onDispose(sounds.dispose);
  return sounds;
});
