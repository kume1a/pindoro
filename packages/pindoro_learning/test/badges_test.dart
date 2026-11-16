import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

BadgeStats _stats({
  int pins = 0,
  int perfects = 0,
  int bestStreak = 0,
  int masteredDistricts = 0,
  int masteredNeighbourhoods = 0,
  int knownDistricts = 0,
  int goalDays = 0,
  bool leechesCleared = false,
  bool lateAnswer = false,
  int cityMemory = 0,
}) => (
  pins: pins,
  perfects: perfects,
  bestStreak: bestStreak,
  masteredDistricts: masteredDistricts,
  masteredNeighbourhoods: masteredNeighbourhoods,
  knownDistricts: knownDistricts,
  goalDays: goalDays,
  leechesCleared: leechesCleared,
  lateAnswer: lateAnswer,
  cityMemory: cityMemory,
);

void main() {
  final live = BadgeId.values.where((id) => !id.retired);

  test('nothing played earns nothing', () {
    for (final id in BadgeId.values) {
      expect(badgeProgress(id, _stats()).earned, isFalse, reason: id.name);
    }
  });

  test('each live badge is earned exactly at its target (SPEC §8, §16.8)', () {
    final cases = {
      BadgeId.firstPin: (_stats(), _stats(pins: 1)),
      BadgeId.bullseye: (_stats(perfects: 9), _stats(perfects: 10)),
      BadgeId.onFire: (_stats(bestStreak: 6), _stats(bestStreak: 7)),
      BadgeId.navigator: (_stats(), _stats(masteredDistricts: 1)),
      BadgeId.local: (_stats(), _stats(masteredNeighbourhoods: 1)),
      BadgeId.keeper: (_stats(goalDays: 99), _stats(goalDays: 100)),
      BadgeId.clearRoad: (_stats(), _stats(leechesCleared: true)),
      BadgeId.nightOwl: (_stats(), _stats(lateAnswer: true)),
      BadgeId.explorer: (_stats(knownDistricts: 4), _stats(knownDistricts: 5)),
    };
    expect(cases.keys, live);
    for (final MapEntry(key: id, value: (short, reached)) in cases.entries) {
      expect(badgeProgress(id, short).earned, isFalse, reason: id.name);
      expect(badgeProgress(id, reached).earned, isTrue, reason: id.name);
    }
  });

  test('road trip and pit crew are retired: nobody earns them now', () {
    expect(BadgeId.values.where((id) => id.retired), [
      BadgeId.roadTrip,
      BadgeId.pitCrew,
    ]);
  });

  test('a countable badge shows its way there, capped at the target', () {
    expect(badgeProgress(BadgeId.keeper, _stats(goalDays: 40)), (
      value: 40,
      target: 100,
    ));
    expect(badgeProgress(BadgeId.bullseye, _stats(perfects: 30)), (
      value: 10,
      target: 10,
    ));
  });

  test('City memory milestones: one per 500 streets, the next one locked', () {
    expect(cityMemoryMilestones(499), isEmpty);
    expect(cityMemoryMilestones(1292), [500, 1000]);
    expect(nextCityMemoryMilestone(1292), (value: 1292, target: 1500));
    expect(cityMemoryBadge(1000), 'cityMemory1000');
    expect(cityMemoryBadgeTarget('cityMemory1500'), 1500);
    expect(cityMemoryBadgeTarget('bullseye'), isNull);
  });
}
