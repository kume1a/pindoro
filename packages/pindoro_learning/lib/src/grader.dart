import 'dart:math';

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

  /// Grades a two-pin answer for [street]'s ends (SPEC §5.2): an end counts with a pin within
  /// `max(`[LearningConfig.extentEndMinM]`, `[LearningConfig.extentEndFraction]` × length)`,
  /// whichever pin goes with which end. Both Good (Great), one Hard (Close), none Again (Miss).
  static ExtentGrade gradeExtent({
    required (LatLng, LatLng) pins,
    required NamedStreet street,
  }) {
    final ends = streetEnds(street);
    final reach = max(
      LearningConfig.extentEndMinM,
      LearningConfig.extentEndFraction * street.lengthM,
    );
    int hits((LatLng, LatLng) to) =>
        (distanceBetween(pins.$1, to.$1) <= reach ? 1 : 0) +
        (distanceBetween(pins.$2, to.$2) <= reach ? 1 : 0);
    final count = max(hits(ends), hits((ends.$2, ends.$1)));
    return (
      ends: ends,
      hits: count,
      tier: const [Tier.miss, Tier.close, Tier.great][count],
      rating: const [Rating.again, Rating.hard, Rating.good][count],
    );
  }

  /// A bearing answer's tier (SPEC §5.2): within [LearningConfig.bearingGreatDeg] Great, within
  /// [LearningConfig.bearingCloseDeg] Close, else Miss. Not scheduled; the log row takes
  /// [ratingOfTier].
  static Tier gradeBearing(double errorDeg) =>
      errorDeg <= LearningConfig.bearingGreatDeg
      ? Tier.great
      : errorDeg <= LearningConfig.bearingCloseDeg
      ? Tier.close
      : Tier.miss;

  /// A drill's display tier from its share right (the family sweep, the crossings drill): all
  /// Great, half or more Close, else Miss.
  static Tier gradeShare(int right, int of) => right == of
      ? Tier.great
      : right * 2 >= of
      ? Tier.close
      : Tier.miss;

  /// The rating a drill's tier logs as: Perfect and Great Good, Close Hard, Miss Again.
  static Rating ratingOfTier(Tier tier) => switch (tier) {
    Tier.perfect || Tier.great => Rating.good,
    Tier.close => Rating.hard,
    Tier.miss => Rating.again,
  };

  /// A name pick (SPEC §5.2, §16.13): the street Good, another Again.
  static Rating gradeName({required bool knew}) =>
      knew ? Rating.good : Rating.again;

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

/// A two-pin answer for a street's ends: the true [ends] and how many pins
/// found one.
typedef ExtentGrade = ({
  (LatLng, LatLng) ends,
  int hits,
  Tier tier,
  Rating rating,
});

/// Degrees between two bearings, 0–180.
double bearingError(double a, double b) =>
    (((a - b) % 360 + 540) % 360 - 180).abs();

/// The name check's [LearningConfig.nameCheckOptions] choices (SPEC §5.2): [target], its
/// [confusable] streets nearest first, then the streets nearest it; one per name, shuffled with
/// [random].
List<NamedStreet> nameChoices({
  required NamedStreet target,
  required Iterable<NamedStreet> streets,
  required Set<String> confusable,
  required Random random,
}) {
  final at = target.parts.first.midpoint;
  // Each street's sort key, worked out once: confusable first, then nearest.
  final keys = {
    for (final s in streets)
      if (s.id != target.id)
        s: (
          confusable.contains(s.id) ? 0 : 1,
          distanceBetween(at, s.parts.first.midpoint),
        ),
  };
  final others = keys.keys.toList()
    ..sort((a, b) {
      final (ca, da) = keys[a]!;
      final (cb, db) = keys[b]!;
      return ca != cb ? ca.compareTo(cb) : da.compareTo(db);
    });
  final names = {normaliseName(target.name)};
  return [
    target,
    ...others
        .where((s) => names.add(normaliseName(s.name)))
        .take(LearningConfig.nameCheckOptions - 1),
  ]..shuffle(random);
}

/// Streets a pin for [target] can land on by mistake (SPEC §5.1, §16.15): other streets with the
/// same normalised name, every street a logged confusion pairs it with, and its [family]
/// (`Curriculum.familyOf`: the parent, siblings and children).
Set<String> confusablesOf(
  NamedStreet target,
  Iterable<NamedStreet> streets,
  Iterable<(String, String)> confusions, {
  Set<String> family = const {},
}) {
  final name = normaliseName(target.name);
  return {
    ...family,
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
