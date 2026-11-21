import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:pindoro/core/sounds.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// The phone during a navigated drive (SPEC §16.23 items 117, 127): spoken prompts that duck
/// other audio (music over CarPlay) while they play, the speed chime, and the screen kept on.
/// Tests override it.
abstract interface class DriveDevice {
  /// Whether the device has a voice for [languageTag] ("ka-GE").
  Future<bool> canSpeak(String languageTag);

  /// Before the first prompt: the navigation audio session.
  Future<void> start();

  /// Completes once said.
  Future<void> say(String text, String languageTag);

  Future<void> chime();

  Future<void> keepScreenOn({required bool on});

  /// After the drive: back to the app's ambient sounds, the screen free to sleep; a prompt
  /// still playing plays on.
  Future<void> stop();
}

final driveDeviceProvider = Provider<DriveDevice>((ref) => _Phone());

class _Phone implements DriveDevice {
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _chime = AudioPlayer();

  bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<bool> canSpeak(String languageTag) async {
    try {
      return await _tts.isLanguageAvailable(languageTag) == true;
    } on Exception {
      return false;
    }
  }

  @override
  Future<void> start() async {
    await _tts.awaitSpeakCompletion(true);
    if (!_ios) return;
    // Active only while speaking, so music ducks for a prompt and comes back after it.
    await _tts.setSharedInstance(true);
    await _tts.autoStopSharedSession(true);
    await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
      IosTextToSpeechAudioCategoryOptions.duckOthers,
      IosTextToSpeechAudioCategoryOptions.interruptSpokenAudioAndMixWithOthers,
    ], IosTextToSpeechAudioMode.voicePrompt);
  }

  @override
  Future<void> say(String text, String languageTag) async {
    await _tts.setLanguage(languageTag);
    // Android: transient focus that lets music duck, as navigation guidance.
    await _tts.speak(text, focus: true);
  }

  @override
  Future<void> chime() async {
    await _chime.stop();
    await _chime.play(AssetSource(Sound.errorSoft.path));
  }

  @override
  Future<void> keepScreenOn({required bool on}) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } on Exception catch (e) {
      debugPrint('screen lock unchanged: $e');
    }
  }

  @override
  Future<void> stop() async {
    await keepScreenOn(on: false);
    if (_ios) {
      await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.ambient, [
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      ]);
    }
  }
}
