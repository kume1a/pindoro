import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Reads a street's name aloud (Hear the name, canvas R4-20).
abstract interface class Speech {
  /// Whether the device has a voice for [languageTag] ("ka-GE").
  Future<bool> canSpeak(String languageTag);

  Future<void> speak(String text, String languageTag);
}

/// The device's text to speech; tests override it.
final speechProvider = Provider<Speech>((ref) => _TtsSpeech());

/// Whether a name in [languageTag] can be heard; asked once per tag.
final canSpeakProvider = FutureProvider.family<bool, String>(
  (ref, languageTag) => ref.watch(speechProvider).canSpeak(languageTag),
);

/// `ka-GE` for a name in Georgian letters, else `en-US`.
String speechLanguage(String name) =>
    RegExp('[Ⴀ-ჿᲐ-Ჿ]').hasMatch(name) ? 'ka-GE' : 'en-US';

class _TtsSpeech implements Speech {
  final FlutterTts _tts = FlutterTts();

  @override
  Future<bool> canSpeak(String languageTag) async {
    try {
      return await _tts.isLanguageAvailable(languageTag) == true;
    } on Exception {
      return false;
    }
  }

  @override
  Future<void> speak(String text, String languageTag) async {
    await _tts.setLanguage(languageTag);
    await _tts.speak(text);
  }
}
