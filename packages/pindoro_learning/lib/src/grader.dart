import 'package:pindoro_core/pindoro_core.dart';

import 'constants.dart';
import 'fsrs.dart';

/// What a pin answer shows and how it rates (SPEC §5.1).
class PinGrade {
  const PinGrade({
    required this.tier,
    required this.rating,
    required this.distanceM,
    required this.snapStreetId,
    required this.isMixUp,
  });

  final Tier tier;
  final Rating rating;

  /// From the pin to the nearest point of the target.
  final double distanceM;

  /// The street nearest the pin within [LearningConfig.snapSearchM]; null if none.
  final String? snapStreetId;

  /// The pin landed on a street the target is confused with; log the pair.
  final bool isMixUp;
}

abstract final class Grader {
  /// Grades a pin dropped for [target] (SPEC §5.1, §16.3). The pin may snap to the target or to
  /// any of [nearby]; [confusable] comes from [confusablesOf]; [priorSuccesses] counts the card's
  /// earlier P reviews rated Hard or better.
  static PinGrade gradePin({
    required LatLng pin,
    required NamedStreet target,
    required Iterable<NamedStreet> nearby,
    required Set<String> confusable,
    required int rtMs,
    required int priorSuccesses,
  }) {
    final onTarget = target.nearest(pin);
    final d = onTarget.distanceM;
    final snap = _snap(pin, target, d, nearby);
    final thresholds = TierThresholds.forStreet(
      onTarget.part.roadClass,
      Difficulty.medium,
    );
    final byDistance = thresholds.tierFor(d);

    PinGrade graded(Tier tier, Rating rating, {bool mixUp = false}) => PinGrade(
      tier: tier,
      rating: rating,
      distanceM: d,
      snapStreetId: snap,
      isMixUp: mixUp,
    );

    if (snap != null && snap != target.id && confusable.contains(snap)) {
      return graded(Tier.miss, Rating.again, mixUp: true);
    }
    if (d > LearningConfig.pinGoodMaxM) return graded(byDistance, Rating.again);
    if (snap != target.id) return graded(Tier.great, Rating.hard);
    if (rtMs > LearningConfig.rtHardMs) return graded(byDistance, Rating.hard);
    if (d <= thresholds.perfect &&
        rtMs <= LearningConfig.rtEasyMs &&
        priorSuccesses >= LearningConfig.easyMinSuccesses) {
      return graded(Tier.perfect, Rating.easy);
    }
    return graded(byDistance, Rating.good);
  }

  // Nearest street within the snap radius; a tie goes to the target, the player's benefit.
  static String? _snap(
    LatLng pin,
    NamedStreet target,
    double targetDistanceM,
    Iterable<NamedStreet> nearby,
  ) {
    const radius = LearningConfig.snapSearchM;
    final projection = LocalProjection(pin);
    final sw = projection.unproject((-radius, -radius));
    final ne = projection.unproject((radius, radius));
    final reach = Bbox(sw.lat, sw.lon, ne.lat, ne.lon);

    String? best = targetDistanceM <= radius ? target.id : null;
    var bestM = targetDistanceM <= radius ? targetDistanceM : double.infinity;
    bool inReach(NamedStreet s) =>
        s.id != target.id && s.parts.any((p) => p.bbox.intersects(reach));
    for (final street in nearby.where(inReach)) {
      final d = street.nearest(pin).distanceM;
      if (d <= radius && d < bestM) {
        best = street.id;
        bestM = d;
      }
    }
    return best;
  }
}

/// Streets a pin for [target] can land on by mistake (SPEC §5.1, §16.15): other streets with the
/// same normalised name, and every street a logged confusion pairs it with. Family siblings and
/// the parent join in M2.
Set<String> confusablesOf(
  NamedStreet target,
  Iterable<NamedStreet> streets,
  Iterable<(String, String)> confusions,
) {
  final name = normaliseName(target.name);
  return {
    for (final s in streets)
      if (s.id != target.id && normaliseName(s.name) == name) s.id,
    for (final (a, b) in confusions)
      if (a == target.id && b != target.id)
        b
      else if (b == target.id && a != target.id)
        a,
  };
}

/// The pipeline's `normalise_name`: lower case, no quotes, single spaces.
String normaliseName(String raw) => raw
    .toLowerCase()
    .replaceAll(RegExp('[«»„“”"\'`]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
