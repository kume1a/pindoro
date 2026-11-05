import 'dart:math';

import '../geo/geo.dart';

/// What the player has shown about a street so far.
enum StreetKnowledge { unknown, missed, known }

class QuestionCandidate {
  const QuestionCandidate({
    required this.streetId,
    required this.midpoint,
    this.knowledge = StreetKnowledge.unknown,
  });

  final String streetId;
  final LatLng midpoint;
  final StreetKnowledge knowledge;
}

sealed class QuestionSelection {
  const QuestionSelection();
}

final class SelectedQuestions extends QuestionSelection {
  const SelectedQuestions(this.streetIds);

  final List<String> streetIds;
}

final class NotEnoughStreets extends QuestionSelection {
  const NotEnoughStreets(this.count);

  final int count;
}

class QuestionSelector {
  QuestionSelector({Random? random}) : _random = random ?? Random();

  static const int roundSize = 10;
  static const double minConsecutiveDistanceM = 300;

  static double weightOf(StreetKnowledge k) => switch (k) {
    StreetKnowledge.unknown => 3,
    StreetKnowledge.missed => 2,
    StreetKnowledge.known => 0.5,
  };

  final Random _random;

  /// Weighted pick of [count] distinct streets without replacement.
  ///
  /// Recently asked streets are excluded unless that would leave fewer than
  /// [count]; the 300 m consecutive-midpoint rule is relaxed for a pick only
  /// when no remaining street satisfies it (tiny areas).
  QuestionSelection select(
    List<QuestionCandidate> pool, {
    Set<String> recentlyAsked = const {},
    int count = roundSize,
  }) {
    if (pool.length < count) return NotEnoughStreets(pool.length);
    final fresh = [
      for (final c in pool)
        if (!recentlyAsked.contains(c.streetId)) c,
    ];
    final remaining = fresh.length >= count ? fresh : [...pool];

    final picked = <QuestionCandidate>[];
    while (picked.length < count) {
      final last = picked.isEmpty ? null : picked.last;
      final spaced = last == null
          ? remaining
          : [
              for (final c in remaining)
                if (distanceBetween(last.midpoint, c.midpoint) >=
                    minConsecutiveDistanceM)
                  c,
            ];
      final choice = _weightedPick(spaced.isEmpty ? remaining : spaced);
      picked.add(choice);
      remaining.remove(choice);
    }
    return SelectedQuestions([for (final c in picked) c.streetId]);
  }

  QuestionCandidate _weightedPick(List<QuestionCandidate> from) {
    final total = from.fold<double>(0, (s, c) => s + weightOf(c.knowledge));
    var r = _random.nextDouble() * total;
    for (final c in from) {
      r -= weightOf(c.knowledge);
      if (r < 0) return c;
    }
    return from.last;
  }
}
