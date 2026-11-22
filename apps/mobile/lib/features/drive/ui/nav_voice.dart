import 'dart:math';

import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// What navigation says (board V32-21, SPEC §16.23 items 117, 127) in [l10n], names in Georgian
/// letters with a Georgian voice ([georgian]) and in Latin ones otherwise, turn prompts without
/// the kind of street.
class NavWords {
  const NavWords(this.l10n, {required this.georgian});

  final AppLocalizations l10n;
  final bool georgian;

  String name(NamedStreet s) =>
      georgian ? s.name : (s.nameEn ?? transliterate(s.name));

  String _place(RouteLandmark l) =>
      georgian ? l.name : (l.nameEn ?? transliterate(l.name));

  String _turn(Turn? turn) => switch (turn) {
    Turn.left => l10n.navLeft,
    Turn.right => l10n.navRight,
    Turn.uTurn => l10n.navUTurn,
    Turn.straight || null => l10n.navStraight,
  };

  /// "left onto Chavchavadze", or the turn alone on a street with no name.
  String _move(NavDecision? d) {
    if (d == null) return l10n.navKeepGoing;
    final street = d.street;
    final turn = _turn(d.turn);
    return street == null
        ? turn
        : l10n.navOnto(turn, withoutKind(name(street)));
  }

  String _distance(double m) {
    // To 50 m; what rounds to 1000 is said in kilometres.
    final rounded = (m / 50).round() * 50;
    if (rounded < 1000) return l10n.navMetres(max(50, rounded));
    final km = (m / 1000).toStringAsFixed(1);
    return l10n.navKilometres(km.endsWith('.0') ? km.split('.').first : km);
  }

  String _direction(double? heading) => l10n.compassWord(
    heading == null ? 'other' : compassPointOf(heading).name,
  );

  /// The words for [p], said at [level].
  String words(NavPrompt p, DriveLevel level) {
    final d = p.decision;
    return switch (p.kind) {
      PromptKind.prepare => switch (_lead(p)) {
        final lead? => l10n.navPrepare(lead, _move(d)),
        null => l10n.navMove(_capital(_move(d))),
      },
      PromptKind.action => l10n.navHere(_capital(_turn(d?.turn))),
      PromptKind.recovery =>
        level == DriveLevel.guided
            ? l10n.navNewRoute(_move(d))
            : l10n.navNewWay(_move(d)),
      PromptKind.confirmation => l10n.navConfirm(
        name(p.street!),
        _direction(p.headingDeg),
      ),
      PromptKind.district => l10n.navDistrict(
        p.district!,
        _direction(p.headingDeg),
      ),
      PromptKind.guard => l10n.navGuard,
      PromptKind.stillFinding => l10n.navStillFinding,
      PromptKind.camera => l10n.navCamera(p.limitKmh ?? 0),
    };
  }

  /// "At Vake Park", "At the lights" or "In 200 metres"; null when the prompt has none.
  String? _lead(NavPrompt p) {
    final d = p.decision;
    if (d?.landmark case final l?) return l10n.navAt(_place(l));
    if (d?.signals ?? false) return l10n.navAtLights;
    if (p.distanceM case final m?) return l10n.navIn(_distance(m));
    return null;
  }

  String arrived(NamedStreet street) => l10n.navArrived(name(street));

  /// Rescue's "Guiding you from here".
  String get rescued => l10n.navRescued;

  /// A sentence's first letter up; Georgian has no case.
  String _capital(String s) =>
      georgian || s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Navigation's lines said one at a time by [say] (SPEC §16.23 item 117): the phone drops
/// (Android) or loses track of (iOS) a line started over another. An action line drops the
/// lesser ones still waiting (prepare, confirmation, district), stale once the turn is here.
/// [onSpeaking] while there are lines.
class SpeechQueue {
  SpeechQueue(this.say, {required this.onSpeaking});

  final Future<void> Function(String text) say;
  final void Function(bool speaking) onSpeaking;

  final List<({PromptKind? kind, String text})> _lines = [];
  Future<void>? _talking;

  /// Says [text] after the lines before it; completes once every line is said.
  Future<void> add(String text, {PromptKind? kind}) {
    if (kind == PromptKind.action) {
      _lines.removeWhere(
        (l) => (l.kind?.index ?? -1) >= PromptKind.prepare.index,
      );
    }
    _lines.add((kind: kind, text: text));
    return _talking ??= _talk();
  }

  /// Drops the lines waiting; the one being said plays on.
  void clear() => _lines.clear();

  Future<void> _talk() async {
    onSpeaking(true);
    try {
      while (_lines.isNotEmpty) {
        await say(_lines.removeAt(0).text);
      }
    } finally {
      _talking = null;
      onSpeaking(false);
    }
  }
}
