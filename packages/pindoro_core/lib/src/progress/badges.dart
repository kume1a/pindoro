import 'dart:math';

/// The starter badges (design system component Badge), in shelf order.
enum BadgeId {
  firstPin,
  bullseye,
  onFire,
  navigator,
  roadTrip,
  nightOwl,
  explorer,
  pitCrew,
}

/// What badges are measured on, gathered from the player's progress.
typedef BadgeStats = ({
  /// Pins dropped in rounds and lesson pin steps.
  int pins,

  /// Of those, Perfect.
  int perfects,
  int bestStreak,

  /// Raions with every street known, in every city.
  int masteredDistricts,

  /// The most raions with a known street in one city.
  int knownDistricts,

  /// Road trips answered: lesson trips and Final drive trips.
  int roadTrips,

  /// Any answer or lesson finished before [BadgeRules.lateBefore] local time.
  bool lateAnswer,

  /// Streets cleared from the Pit stop.
  int pitStopCleared,
});

/// Where a badge stands; [value] never shows past [target].
typedef BadgeProgress = ({int value, int target});

extension BadgeProgressRules on BadgeProgress {
  bool get earned => value >= target;
}

abstract final class BadgeRules {
  /// Night owl: an answer from midnight until this local hour.
  static const int lateBefore = 4;
}

BadgeProgress badgeProgress(BadgeId id, BadgeStats s) {
  final (value, target) = switch (id) {
    BadgeId.firstPin => (s.pins, 1),
    BadgeId.bullseye => (s.perfects, 10),
    BadgeId.onFire => (s.bestStreak, 7),
    BadgeId.navigator => (s.masteredDistricts, 1),
    BadgeId.roadTrip => (s.roadTrips, 5),
    BadgeId.nightOwl => (s.lateAnswer ? 1 : 0, 1),
    BadgeId.explorer => (s.knownDistricts, 5),
    BadgeId.pitCrew => (s.pitStopCleared, 50),
  };
  return (value: min(value, target), target: target);
}
