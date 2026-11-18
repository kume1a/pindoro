import 'dart:math';

import 'constants.dart';

/// The badges (design system Badge), in shelf order; City memory milestones
/// are ids of their own ([cityMemoryBadge]).
enum BadgeId {
  firstPin,
  bullseye,
  onFire,
  navigator,
  local,
  keeper,
  clearRoad,
  nightOwl,
  explorer,
  roadTrip,
  pitCrew;

  /// Earned ones still show; nobody earns them now (SPEC §16.8).
  bool get retired => this == roadTrip || this == pitCrew;
}

/// What badges are measured on, gathered from the player's progress.
typedef BadgeStats = ({
  /// Pins dropped: sessions, placement and Explore rounds.
  int pins,

  /// Explore answers that were Perfect.
  int perfects,
  int bestStreak,

  /// Raions whose every core street is Mastered (SPEC §8), in any city.
  int masteredDistricts,

  /// Neighbourhoods whose every core street is Mastered.
  int masteredNeighbourhoods,

  /// The most raions with a known street in one city.
  int knownDistricts,

  /// Days that counted towards the streak, in a row or not.
  int goalDays,

  /// A street became a leech once and no leech is left.
  bool leechesCleared,

  /// Any answer before [LearningConfig.nightOwlBefore] local time.
  bool lateAnswer,

  /// The open city's City memory, in streets.
  int cityMemory,
});

/// Where a badge stands; [value] never shows past [target].
typedef BadgeProgress = ({int value, int target});

extension BadgeProgressRules on BadgeProgress {
  bool get earned => value >= target;
}

/// A retired badge never moves: it was earned before, or it stays hidden.
BadgeProgress badgeProgress(BadgeId id, BadgeStats s) {
  final (value, target) = switch (id) {
    BadgeId.firstPin => (s.pins, 1),
    BadgeId.bullseye => (s.perfects, LearningConfig.bullseyeBadgePerfects),
    BadgeId.onFire => (s.bestStreak, LearningConfig.onFireBadgeDays),
    BadgeId.navigator => (s.masteredDistricts, 1),
    BadgeId.local => (s.masteredNeighbourhoods, 1),
    BadgeId.keeper => (s.goalDays, LearningConfig.maintenanceBadgeDays),
    BadgeId.clearRoad => (s.leechesCleared ? 1 : 0, 1),
    BadgeId.nightOwl => (s.lateAnswer ? 1 : 0, 1),
    BadgeId.explorer => (
      s.knownDistricts,
      LearningConfig.explorerBadgeDistricts,
    ),
    BadgeId.roadTrip || BadgeId.pitCrew => (0, 1),
  };
  return (value: min(value, target), target: target);
}

/// The City memory milestones reached at [cityMemory] streets, smallest first.
List<int> cityMemoryMilestones(int cityMemory) => [
  for (
    var m = LearningConfig.cityMemoryMilestone;
    m <= cityMemory;
    m += LearningConfig.cityMemoryMilestone
  )
    m,
];

/// The milestone after [cityMemory], with the way there ("1 292 of 1 500").
BadgeProgress nextCityMemoryMilestone(int cityMemory) => (
  value: cityMemory,
  target:
      (cityMemory ~/ LearningConfig.cityMemoryMilestone + 1) *
      LearningConfig.cityMemoryMilestone,
);

/// The stored id of the [milestone] badge.
String cityMemoryBadge(int milestone) => 'cityMemory$milestone';

/// The milestone a stored badge id names; null for any other badge.
int? cityMemoryBadgeTarget(String id) => id.startsWith('cityMemory')
    ? int.tryParse(id.substring('cityMemory'.length))
    : null;
