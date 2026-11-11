import 'package:pindoro_core/pindoro_core.dart';
import 'package:test/test.dart';

BadgeStats _stats({
  int pins = 0,
  int perfects = 0,
  int bestStreak = 0,
  int masteredDistricts = 0,
  int knownDistricts = 0,
  int roadTrips = 0,
  bool lateAnswer = false,
  int pitStopCleared = 0,
}) => (
  pins: pins,
  perfects: perfects,
  bestStreak: bestStreak,
  masteredDistricts: masteredDistricts,
  knownDistricts: knownDistricts,
  roadTrips: roadTrips,
  lateAnswer: lateAnswer,
  pitStopCleared: pitStopCleared,
);

void main() {
  test('nothing played earns nothing', () {
    for (final id in BadgeId.values) {
      expect(badgeProgress(id, _stats()).earned, isFalse, reason: id.name);
    }
  });

  test('each badge is earned exactly at its target', () {
    // One short, then reached.
    final cases = {
      BadgeId.firstPin: (_stats(), _stats(pins: 1)),
      BadgeId.bullseye: (_stats(perfects: 9), _stats(perfects: 10)),
      BadgeId.onFire: (_stats(bestStreak: 6), _stats(bestStreak: 7)),
      BadgeId.navigator: (_stats(), _stats(masteredDistricts: 1)),
      BadgeId.roadTrip: (_stats(roadTrips: 4), _stats(roadTrips: 5)),
      BadgeId.nightOwl: (_stats(), _stats(lateAnswer: true)),
      BadgeId.explorer: (_stats(knownDistricts: 4), _stats(knownDistricts: 5)),
      BadgeId.pitCrew: (_stats(pitStopCleared: 49), _stats(pitStopCleared: 50)),
    };
    expect(cases.keys.toList(), BadgeId.values);
    for (final MapEntry(key: id, value: (short, reached)) in cases.entries) {
      expect(badgeProgress(id, short).earned, isFalse, reason: id.name);
      expect(badgeProgress(id, reached).earned, isTrue, reason: id.name);
    }
  });

  test('a countable badge shows its way there, capped at the target', () {
    expect(badgeProgress(BadgeId.roadTrip, _stats(roadTrips: 2)), (
      value: 2,
      target: 5,
    ));
    expect(badgeProgress(BadgeId.bullseye, _stats(perfects: 37)), (
      value: 10,
      target: 10,
    ));
  });
}
