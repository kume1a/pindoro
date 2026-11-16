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

double _distance(String typed, NamedStreet street) {
  final base = nameBase(typed);
  final typedForms = {base, transliterate(base)};
  return [
    for (final t in typedForms)
      for (final f in nameForms(street)) nameDistance(t, f),
  ].fold(1, min);
}

/// A typed name counts for [street] within [LearningConfig.fuzzyNameMax] of
/// any of its forms (SPEC §5.2).
bool nameMatches(String typed, NamedStreet street) =>
    nameBase(typed).isNotEmpty &&
    _distance(typed, street) <= LearningConfig.fuzzyNameMax;

/// The street [typed] names best among [streets]: a fuzzy match, else the
/// nearest start of a name (what's typed so far); null under two letters.
NamedStreet? suggestStreet(String typed, Iterable<NamedStreet> streets) {
  final base = nameBase(typed);
  if (base.length < 2) return null;
  final typedForms = {base, transliterate(base)};
  double score(NamedStreet s) => [
    for (final t in typedForms)
      for (final f in nameForms(s))
        nameDistance(t, f.length > t.length ? f.substring(0, t.length) : f) +
            (f.length - t.length).abs() / 1000,
  ].fold(1, min);
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
