import 'dart:math';

import '../geo/geo.dart';
import '../pack/models.dart';
import 'knowledge.dart';
import 'named_street.dart';

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

  /// Picks [roundSize] distinct names from [inArea] (the area's streets at the
  /// round's difficulties), spread over a 3 × 3 grid of [bounds]: the cells
  /// are shuffled once, then visited round-robin, each giving its best-ranked
  /// name (unknown, missed, known; then not in [recentStreets]; then random).
  /// [knowledge] and [recentStreets] use the street ids of [cityStreets].
  QuestionSelection select(
    List<Street> inArea, {
    required Bbox bounds,
    Map<String, NamedStreet> cityStreets = const {},
    Map<String, StreetKnowledge> knowledge = const {},
    Set<String> recentStreets = const {},
  }) {
    const count = roundSize;
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
      final id = cityStreets[s.id]?.id ?? s.id;
      final rank = [
        (knowledge[id] ?? StreetKnowledge.unknown).index,
        if (recentStreets.contains(id)) 1 else 0,
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
