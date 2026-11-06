import 'dart:math';

import '../geo/geo.dart';
import '../pack/models.dart';
import '../scoring/scoring.dart';
import 'named_street.dart';

/// What the player has shown about a street (by name, per city).
enum StreetKnowledge { unknown, missed, known }

/// Known after any Great or Perfect; it never reverts in the MVP.
StreetKnowledge knowledgeFrom(Tier? bestTier) => switch (bestTier) {
  null => StreetKnowledge.unknown,
  Tier.perfect || Tier.great => StreetKnowledge.known,
  Tier.close || Tier.miss => StreetKnowledge.missed,
};

bool isKnownTier(Tier tier) => tier == Tier.perfect || tier == Tier.great;

/// Best tier per name, from best tiers per street id and the ids' names.
Map<String, Tier> bestTierByName(
  Map<String, Tier> bestById,
  Map<String, String> nameById,
) {
  final best = <String, Tier>{};
  for (final MapEntry(key: id, value: tier) in bestById.entries) {
    final name = nameById[id];
    if (name == null) continue;
    final current = best[name];
    if (current == null || tier.index < current.index) best[name] = tier;
  }
  return best;
}

/// Names with a Great or Perfect in a round that weren't known before it.
Set<String> newlyKnown({
  required Set<String> knownBefore,
  required Iterable<({String name, Tier tier})> roundAnswers,
}) => {
  for (final a in roundAnswers)
    if (isKnownTier(a.tier) && !knownBefore.contains(a.name)) a.name,
};

typedef KnownCount = ({int known, int total});

/// Known / total street names for the city and each district.
({KnownCount city, Map<String, KnownCount> byDistrict}) knownCounts({
  required Set<String> cityNames,
  required Map<String, Set<String>> namesByDistrict,
  required Set<String> knownNames,
}) {
  KnownCount count(Set<String> names) =>
      (known: names.where(knownNames.contains).length, total: names.length);
  return (
    city: count(cityNames),
    byDistrict: {
      for (final MapEntry(key: id, value: names) in namesByDistrict.entries)
        id: count(names),
    },
  );
}

sealed class QuestionSelection {
  const QuestionSelection();
}

final class SelectedQuestions extends QuestionSelection {
  const SelectedQuestions(this.streetIds);

  /// One id per picked name: its longest in-area part.
  final List<String> streetIds;
}

final class NotEnoughStreets extends QuestionSelection {
  const NotEnoughStreets(this.count);

  final int count;
}

class QuestionSelector {
  QuestionSelector({Random? random}) : _random = random ?? Random();

  static const int roundSize = 10;

  /// Names whose in-area parts add up to less than this are skipped.
  static const double minTotalLengthM = 150;
  static const int gridSize = 3;

  final Random _random;

  /// Picks [count] distinct names from [inArea] (the area's streets at the
  /// round's difficulties), spread over a 3 × 3 grid of [bounds]: the cells
  /// are shuffled once, then visited round-robin, each giving its best-ranked
  /// name (unknown, missed, known; then not in [recentNames]; then random).
  QuestionSelection select(
    List<Street> inArea, {
    required Bbox bounds,
    Map<String, StreetKnowledge> knowledge = const {},
    Set<String> recentNames = const {},
    int count = roundSize,
  }) {
    final longestByName = <String, NamedStreet>{};
    for (final s in groupByName(inArea)) {
      if (s.lengthM < minTotalLengthM) continue;
      if (s.lengthM > (longestByName[s.name]?.lengthM ?? 0)) {
        longestByName[s.name] = s;
      }
    }
    final candidates = longestByName.values.toList();
    if (candidates.length < count) return NotEnoughStreets(candidates.length);

    final cells = <int, List<({NamedStreet street, List<num> rank})>>{};
    for (final s in candidates) {
      final rank = [
        (knowledge[s.name] ?? StreetKnowledge.unknown).index,
        if (recentNames.contains(s.name)) 1 else 0,
        _random.nextDouble(),
      ];
      cells.putIfAbsent(_cellOf(s.parts.first.midpoint, bounds), () => []).add((
        street: s,
        rank: rank,
      ));
    }
    for (final cell in cells.values) {
      cell.sort((a, b) => _compareRanks(a.rank, b.rank));
    }

    final order = cells.keys.toList()..shuffle(_random);
    final picked = <String>[];
    for (var round = 0; picked.length < count; round++) {
      for (final key in order) {
        final cell = cells[key]!;
        if (round < cell.length && picked.length < count) {
          picked.add(cell[round].street.id);
        }
      }
    }
    return SelectedQuestions(picked);
  }

  static int _cellOf(LatLng p, Bbox b) {
    int index(double v, double lo, double hi) => hi <= lo
        ? 0
        : ((v - lo) / (hi - lo) * gridSize).floor().clamp(0, gridSize - 1);
    return index(p.lat, b.minLat, b.maxLat) * gridSize +
        index(p.lon, b.minLon, b.maxLon);
  }

  static int _compareRanks(List<num> a, List<num> b) {
    for (var i = 0; i < a.length; i++) {
      final c = a[i].compareTo(b[i]);
      if (c != 0) return c;
    }
    return 0;
  }
}
