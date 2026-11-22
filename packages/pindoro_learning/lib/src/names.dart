import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'constants.dart';
import 'grader.dart';

/// Georgian letters in the national romanisation, apostrophes dropped as on
/// Tbilisi's street signs.
const Map<String, String> _latin = {
  'ა': 'a', 'ბ': 'b', 'გ': 'g', 'დ': 'd', 'ე': 'e', 'ვ': 'v', 'ზ': 'z', //
  'თ': 't', 'ი': 'i', 'კ': 'k', 'ლ': 'l', 'მ': 'm', 'ნ': 'n', 'ო': 'o', //
  'პ': 'p', 'ჟ': 'zh', 'რ': 'r', 'ს': 's', 'ტ': 't', 'უ': 'u', 'ფ': 'p', //
  'ქ': 'k', 'ღ': 'gh', 'ყ': 'q', 'შ': 'sh', 'ჩ': 'ch', 'ც': 'ts', 'ძ': 'dz', //
  'წ': 'ts', 'ჭ': 'ch', 'ხ': 'kh', 'ჯ': 'j', 'ჰ': 'h',
};

/// [text] with its Georgian letters in Latin ones.
String transliterate(String text) =>
    text.split('').map((c) => _latin[c] ?? c).join();

/// Words that say what kind of street it is, in either script; a typed name
/// is matched without them.
final RegExp _kindWords = RegExp(
  r'\b(street|st|avenue|ave|lane|dead end|passage|square|embankment|highway|'
  r'road|alley|ascent|descent|kucha|gamziri|shesakhvevi|chikhi|gasasvleli|'
  r'moedani|sanapiro)\b|'
  'ქუჩა|გამზირი|შესახვევი|ჩიხი|გასასვლელი|ხეივანი|მოედანი|აღმართი|დაღმართი|'
  'სანაპირო|გზატკეცილი',
);

/// A name as typed names are compared: normalised, without the kind of street
/// and its punctuation.
String nameBase(String name) => normaliseName(name)
    .replaceAll(_kindWords, ' ')
    .replaceAll(RegExp(r'[.,\-–]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// [name] without its kind of street, case kept ("Chavchavadze Avenue" → "Chavchavadze"): how turn
/// prompts say it (SPEC §16.23 item 117). A name that is only a kind stays whole.
String withoutKind(String name) {
  final short = name
      .replaceAll(RegExp(_kindWords.pattern, caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return short.isEmpty ? name : short;
}

const Map<String, String> _shortKinds = {
  'avenue': 'Ave',
  'street': 'St',
  'square': 'Sq',
  'lane': 'Ln',
  'road': 'Rd',
  'highway': 'Hwy',
  'embankment': 'Emb',
  'გამზირი': 'გამზ.',
  'ქუჩა': 'ქ.',
};

/// [name] with its kind of street shortened ("Chavchavadze Avenue" → "Chavchavadze Ave"): how
/// the drive screens show it, so it fits their 54 dp type (board V32-20).
String shortKind(String name) => name.replaceAllMapped(
  RegExp(
    '(?<![\\p{L}])(${_shortKinds.keys.join('|')})(?![\\p{L}])',
    caseSensitive: false,
    unicode: true,
  ),
  (m) => _shortKinds[m[1]!.toLowerCase()]!,
);

/// Levenshtein distance over the longer length: 0 same, 1 nothing shared.
double nameDistance(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 0;
  var row = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final next = [i, ...List.filled(b.length, 0)];
    for (var j = 1; j <= b.length; j++) {
      next[j] = min(
        min(next[j - 1] + 1, row[j] + 1),
        row[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
      );
    }
    row = next;
  }
  return row[b.length] / max(a.length, b.length);
}

/// The forms [street] is recognised by: its Georgian name, that name in Latin
/// letters, and its English name.
Set<String> nameForms(NamedStreet street) {
  final ka = nameBase(street.name);
  return {ka, transliterate(ka), if (street.nameEn case final en?) nameBase(en)}
    ..remove('');
}

/// A typed [base] as it is matched: itself and in Latin letters.
Set<String> _typedForms(String base) => {base, transliterate(base)};

/// A typed name counts for [street] within [LearningConfig.fuzzyNameMax] of
/// any of its forms (SPEC §5.2).
bool nameMatches(String typed, NamedStreet street) {
  final base = nameBase(typed);
  if (base.isEmpty) return false;
  final forms = nameForms(street);
  return [
        for (final t in _typedForms(base))
          for (final f in forms) nameDistance(t, f),
      ].fold<double>(1, min) <=
      LearningConfig.fuzzyNameMax;
}

/// The forms a place named [ka] (and [en]) is recognised by, as [nameForms] for a street.
Set<String> placeForms(String ka, String? en) {
  final base = nameBase(ka);
  return {base, transliterate(base), if (en != null) nameBase(en)}..remove('');
}

/// How far [typed] is from the start of [name] (or all of it), a little more the longer
/// [name] runs past it.
double _startDistance(String typed, String name) =>
    min(
      nameDistance(
        typed,
        name.length > typed.length ? name.substring(0, typed.length) : name,
      ),
      nameDistance(typed, name),
    ) +
    (name.length - typed.length).abs() / 1000;

/// How well every word of [typed] starts a word of [name], in any order ("kazbegi" for
/// "aleksandre kazbegis", "chavchavadze ilia"): the mean of each word's best, or 1 when a word
/// starts none within [LearningConfig.fuzzyNameMax]. A later word costs a little more.
double _wordsDistance(List<String> typed, List<String> name) {
  var total = 0.0;
  for (final t in typed) {
    var best = 1.0;
    for (final (i, w) in name.indexed) {
      best = min(best, _startDistance(t, w) + i / 1000);
    }
    if (best > LearningConfig.fuzzyNameMax) return 1;
    total += best;
  }
  return total / typed.length;
}

/// The [items] [typed] names best, best first and at most [limit]: a fuzzy match of the whole
/// name or its start, or every typed word starting one of its words, within
/// [LearningConfig.fuzzyNameMax]; none under two letters. [forms] gives an item's names (see
/// [nameForms], [placeForms]).
List<T> searchNames<T>(
  String typed,
  Iterable<T> items,
  Set<String> Function(T item) forms, {
  int limit = 8,
}) {
  final base = nameBase(typed);
  if (base.length < 2) return const [];
  final typedForms = [
    for (final t in _typedForms(base)) (whole: t, words: t.split(' ')),
  ];
  final scored = <(double, int, T)>[];
  for (final (i, item) in items.indexed) {
    final score = [
      for (final t in typedForms)
        for (final f in forms(item)) ...[
          _startDistance(t.whole, f),
          _wordsDistance(t.words, f.split(' ')),
        ],
    ].fold<double>(1, min);
    if (score <= LearningConfig.fuzzyNameMax) scored.add((score, i, item));
  }
  scored.sort((a, b) {
    final byScore = a.$1.compareTo(b.$1);
    return byScore != 0 ? byScore : a.$2.compareTo(b.$2);
  });
  return [for (final s in scored.take(limit)) s.$3];
}

/// The street [typed] names best among [streets]: a fuzzy match, else the
/// nearest start of a name (what's typed so far); null under two letters.
NamedStreet? suggestStreet(String typed, Iterable<NamedStreet> streets) {
  final base = nameBase(typed);
  if (base.length < 2) return null;
  final typedForms = _typedForms(base);
  double score(NamedStreet s) {
    final forms = nameForms(s);
    return [
      for (final t in typedForms)
        for (final f in forms)
          nameDistance(t, f.length > t.length ? f.substring(0, t.length) : f) +
              (f.length - t.length).abs() / 1000,
    ].fold(1, min);
  }

  NamedStreet? best;
  var bestScore = LearningConfig.fuzzyNameMax;
  for (final s in streets) {
    final d = score(s);
    if (d < bestScore ||
        (d == bestScore && best != null && s.id.compareTo(best.id) < 0)) {
      (best, bestScore) = (s, d);
    }
  }
  return best;
}
