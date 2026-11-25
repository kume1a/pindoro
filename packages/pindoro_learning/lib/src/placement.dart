import 'package:pindoro_core/pindoro_core.dart';

import 'constants.dart';
import 'curriculum.dart';
import 'fsrs.dart';

/// One placement run (SPEC §6.2) over [Curriculum.placement]: streets already carded are not
/// asked, and a raion's sample that passes brings the rest of its grid right after it. A pass is
/// Good or Easy; "I don't know this one" (a null rating) is not.
class Placement {
  Placement(
    this._curriculum, {
    required int seed,
    Set<String> carded = const {},
  }) : _carded = carded {
    for (final id in _curriculum.placement(seed)) {
      if (carded.contains(id)) continue;
      streets.add(id);
      if (_curriculum.tierOf(id) == StreetTier.a) {
        _mainRoads++;
      } else if (_curriculum.raionOf(id) case final raion?) {
        _samples.putIfAbsent(raion, () => []).add(id);
      }
    }
  }

  final Curriculum _curriculum;
  final Set<String> _carded;

  /// The streets to ask, in order; a sweep joins after the sample answer that earns it.
  final List<String> streets = [];
  final _samples = <String, List<String>>{};
  final _answered = <String, int>{};
  final _passes = <String, int>{};
  int _mainRoads = 0;
  int _mainRoadsPassed = 0;
  int _passed = 0;

  static bool passes(Rating? rating) => rating?.passes ?? false;

  /// Records [id]'s answer and returns the sweep it added (usually none).
  List<String> answer(String id, Rating? rating) {
    final pass = passes(rating);
    if (pass) _passed++;
    if (_curriculum.tierOf(id) == StreetTier.a) {
      if (pass) _mainRoadsPassed++;
      return const [];
    }
    final raion = _curriculum.raionOf(id);
    final sample = _samples[raion];
    if (raion == null || sample == null || !sample.contains(id)) {
      return const [];
    }
    final answered = _answered.update(raion, (n) => n + 1, ifAbsent: () => 1);
    final passed = _passes.update(
      raion,
      (n) => n + (pass ? 1 : 0),
      ifAbsent: () => pass ? 1 : 0,
    );
    final enough =
        passed * LearningConfig.placementSamplePerDistrict >=
        sample.length * LearningConfig.placementPassMin;
    if (answered < sample.length || !enough) return const [];
    final sweep = [
      for (final s in _curriculum.placementSweep(raion, sample))
        if (!_carded.contains(s)) s,
    ];
    streets.insertAll(streets.indexOf(id) + 1, sweep);
    return sweep;
  }

  /// Main roads placed of those asked ("71 of 88").
  ({int passed, int of}) get mainRoads =>
      (passed: _mainRoadsPassed, of: _mainRoads);

  /// Raions sampled.
  int get raions => _samples.length;

  /// Streets placed: each became a review card.
  int get passed => _passed;
}
