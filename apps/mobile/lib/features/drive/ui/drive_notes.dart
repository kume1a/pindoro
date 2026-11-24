import 'package:pindoro/features/drive/ui/drive_state.dart';
import 'package:pindoro/features/learning/data/drive_log.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// What a drive said, showed and was touched for (SPEC §16.23 item 124), saved with it: each
/// name the first time it is heard or shown, each screen when it changes.
class DriveNotes {
  DriveNotes(this._clock);

  final DateTime Function() _clock;
  final List<DriveNote> _notes = [];
  final Set<(String, String)> _named = {};
  String? _screen;

  List<DriveNote> get all => List.unmodifiable(_notes);

  /// A new drive's notes start empty.
  void clear() {
    _notes.clear();
    _named.clear();
    _screen = null;
  }

  void add(
    DriveEventKind kind, {
    String? itemKey,
    String? detail,
    double? value,
  }) => _notes.add((
    at: _clock(),
    kind: kind,
    itemKey: itemKey,
    detail: detail,
    value: value,
  ));

  /// The first time [street] is heard or shown on this drive.
  void name(NamedStreet street, {required bool heard}) {
    final how = heard ? 'heard' : 'shown';
    if (_named.add((street.id, how))) {
      add(DriveEventKind.name, itemKey: street.id, detail: how);
    }
  }

  /// The screen [r] shows, when it changed, and the street names on it: Guided's street and
  /// turn card, a recovery's next street.
  void screen(DriveRecording r) {
    final v = r.view;
    final shown = [
      r.level.name,
      if (v?.recovering ?? false) 'recovery',
      if (v?.gpsLostS != null) 'lost',
      if (r.stopped) 'stopped',
    ].join(' ');
    if (shown != _screen) {
      _screen = shown;
      add(DriveEventKind.screen, detail: shown);
    }
    if (v == null || v.gpsLostS != null) return;
    final next = v.next;
    final card = next != null && (v.prepareM != null || v.turned == null)
        ? next.street
        : v.turned?.street;
    for (final s in switch (r.level) {
      DriveLevel.guided => [v.street, card],
      _ when v.recovering => [next?.street],
      _ => const <NamedStreet?>[],
    }.nonNulls) {
      name(s, heard: false);
    }
  }
}
