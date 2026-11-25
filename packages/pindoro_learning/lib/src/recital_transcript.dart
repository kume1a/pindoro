import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'constants.dart';
import 'names.dart';
import 'route_questions.dart';
import 'routes.dart';

/// A piece of a recited route (SPEC §5.3 step 1): a turn word, or words that name a street or a
/// landmark.
sealed class RecitalToken {
  const RecitalToken();
}

final class TurnToken extends RecitalToken {
  const TurnToken(this.turn);

  final Turn turn;

  @override
  bool operator ==(Object other) => other is TurnToken && other.turn == turn;

  @override
  int get hashCode => turn.hashCode;

  @override
  String toString() => 'TurnToken($turn)';
}

final class NameToken extends RecitalToken {
  const NameToken(this.text);

  final String text;

  @override
  bool operator ==(Object other) => other is NameToken && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'NameToken($text)';
}

/// One step of a recital: the turn said (if any), then the street or the landmark it names.
typedef RecitalStep = ({
  Turn? turn,
  NamedStreet? street,
  RouteLandmark? landmark,
});

const Map<String, Turn> _turnWords = {
  'left': Turn.left,
  'right': Turn.right,
  'straight': Turn.straight,
  'u-turn': Turn.uTurn,
  'uturn': Turn.uTurn,
  'მარცხნივ': Turn.left,
  'მარჯვნივ': Turn.right,
  'პირდაპირ': Turn.straight,
  'მობრუნება': Turn.uTurn,
  'უკან': Turn.uTurn,
  'martskhniv': Turn.left,
  'marcxniv': Turn.left,
  'marjvniv': Turn.right,
  'pirdapir': Turn.straight,
  'mobruneba': Turn.uTurn,
  'ukan': Turn.uTurn,
};

const Map<String, Turn> _turnPairs = {
  'u turn': Turn.uTurn,
  'turn around': Turn.uTurn,
};

/// Words around the names that say nothing about the route. "And" (და) stays in a run: names
/// hold it ("ზაზა და საულ კახიანების ქუჩა"), and a run's words that name nothing are skipped.
const Set<String> _fillers = {
  'onto', 'on', 'into', 'to', 'then', 'turn', 'take', 'the', 'go', //
  'at', 'keep', 'drive', 'continue', 'along', 'until', 'till', 'past', //
  'after', 'a', 'down', 'up', 'from', 'via', 'by', //
  'მერე', 'შემდეგ', 'ვუხვევ', 'შევუხვევ', 'გავყვები', 'ვაგრძელებ', //
  'mere', 'shemdeg', 'vukhvev', 'shevukhvev', 'gavyvebi', 'vagrdzeleb',
};

/// Georgian case endings a spoken name can carry ("abashidzeze": onto Abashidze).
const List<String> _caseEndings = [
  'ზედ', 'ზე', 'დან', 'მდე', 'ით', 'ში', 'თან', 'კენ', //
  'zed', 'ze', 'dan', 'mde', 'it', 'shi', 'tan', 'ken',
];

String _bare(String word) => word.replaceAll(RegExp('[«»„“”"\'`()]'), '');

/// Splits a transcript into turn words and runs of name words (SPEC §5.3 step 1): punctuation,
/// turn words and filler words end a run.
List<RecitalToken> tokenizeRecital(String transcript) {
  final tokens = <RecitalToken>[];
  final name = <String>[];
  void flush() {
    if (name.isEmpty) return;
    tokens.add(NameToken(name.join(' ')));
    name.clear();
  }

  for (final clause in transcript.toLowerCase().split(RegExp(r'[,;.!?…\n]+'))) {
    final words = [
      for (final w in clause.split(RegExp(r'\s+')))
        if (_bare(w) case final b when b.isNotEmpty) b,
    ];
    for (var i = 0; i < words.length; i++) {
      final pair = i + 1 < words.length
          ? _turnPairs['${words[i]} ${words[i + 1]}']
          : null;
      final turn = pair ?? _turnWords[words[i]];
      if (turn != null) {
        flush();
        tokens.add(TurnToken(turn));
        if (pair != null) i++;
      } else if (_fillers.contains(words[i])) {
        flush();
      } else {
        name.add(words[i]);
      }
    }
    flush();
  }
  return tokens;
}

/// A street or a landmark a phrase can name, with the forms it's recognised by.
typedef _Entry = ({
  Set<String> forms,
  NamedStreet? street,
  RouteLandmark? landmark,
});

/// The ways [phrase] may be meant: as said, without a case ending, in Latin letters.
Set<String> _variants(String phrase) {
  final base = nameBase(phrase);
  final out = {base};
  for (final ending in _caseEndings) {
    if (base.endsWith(ending) && base.length - ending.length >= 3) {
      out.add(base.substring(0, base.length - ending.length));
    }
  }
  return {
    for (final v in out) ...{v, transliterate(v)},
  }..remove('');
}

double _phraseDistance(Set<String> variants, Set<String> forms) => [
  for (final v in variants)
    for (final f in forms) nameDistanceWithin(v, f),
].fold(1, min);

/// How far [entry] lies from [previous]: the nearest of its points to that street's line.
double _apart(_Entry entry, NamedStreet previous) {
  double to(LatLng p) =>
      pointToPolylineDistance(p, previous.geometry).distanceMeters;
  return switch (entry) {
    (street: final s?, landmark: _, forms: _) =>
      s.geometry.expand((line) => line).map(to).reduce(min),
    (landmark: final l?, street: _, forms: _) => to(l.at),
    _ => double.infinity,
  };
}

/// [e]'s names in full, kind words kept.
Set<String> _fullNames(_Entry e) => {
  if (e.street case final s?) ...[
    normaliseName(s.name),
    if (s.nameEn case final en?) normaliseName(en),
  ],
  if (e.landmark case final l?) normaliseName(l.name),
};

/// Resolves [tokens] into steps (SPEC §5.3 step 2): each run of name words is split greedily into
/// the longest phrases naming a street or a landmark within [LearningConfig.fuzzyNameMax] (in
/// Georgian, English or Latin letters, with or without a case ending); among near-equal matches
/// the one nearest the previous street wins ([from] before the first). A turn word goes with the
/// next name; words that name nothing are skipped.
List<RecitalStep> resolveRecital(
  List<RecitalToken> tokens, {
  required Iterable<NamedStreet> streets,
  Iterable<RouteLandmark> landmarks = const [],
  NamedStreet? from,
}) {
  final entries = <_Entry>[
    for (final s in streets) (forms: nameForms(s), street: s, landmark: null),
    for (final l in landmarks)
      (forms: placeForms(l.name, l.nameEn), street: null, landmark: l),
  ];
  final steps = <RecitalStep>[];
  var previous = from;
  Turn? turn;
  _Entry? match(String phrase) {
    final variants = _variants(phrase);
    final found = [
      for (final e in entries)
        if (_phraseDistance(variants, e.forms) case final d
            when d <= LearningConfig.fuzzyNameMax)
          (entry: e, d: d),
    ];
    if (found.isEmpty) return null;
    final best = found.map((f) => f.d).reduce(min);
    final ties = [
      for (final f in found)
        if (f.d <= best + LearningConfig.recitalNameTieSlack) f.entry,
    ];
    // Kind words don't count in a match, so a lane and its street tie: the
    // full name said settles it.
    final whole = normaliseName(phrase);
    final exact = ties.where((e) => _fullNames(e).contains(whole)).toList();
    final near = previous;
    if (exact.length == 1 || (exact.isNotEmpty && near == null)) {
      return exact.first;
    }
    if (ties.length == 1 || near == null) {
      return found.firstWhere((f) => f.d == best).entry;
    }
    return (exact.isEmpty ? ties : exact)
        .map((e) => (entry: e, m: _apart(e, near)))
        .reduce((a, b) => b.m < a.m ? b : a)
        .entry;
  }

  for (final token in tokens) {
    switch (token) {
      case TurnToken(turn: final said):
        turn = said;
      case NameToken(:final text):
        final words = text.split(' ');
        var i = 0;
        while (i < words.length) {
          var taken = 0;
          for (
            var n = min(LearningConfig.recitalNameWordsMax, words.length - i);
            n > 0;
            n--
          ) {
            final entry = match(words.sublist(i, i + n).join(' '));
            if (entry == null) continue;
            steps.add((
              turn: turn,
              street: entry.street,
              landmark: entry.landmark,
            ));
            turn = null;
            if (entry.street case final s?) previous = s;
            taken = n;
            break;
          }
          i += max(taken, 1);
        }
    }
  }
  return steps;
}
