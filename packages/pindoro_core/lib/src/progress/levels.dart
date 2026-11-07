import '../scoring/scoring.dart';

/// XP needed to go from level [n] to n + 1.
int requirement(int n) =>
    ScoringConfig.levelBaseXp + ScoringConfig.levelStepXp * (n - 1);

/// Cumulative XP at which level [n] starts (level 1 starts at 0).
int totalXpToReach(int n) =>
    ScoringConfig.levelBaseXp * (n - 1) +
    ScoringConfig.levelStepXp * (n - 1) * (n - 2) ~/ 2;

int levelForXp(int xp) {
  var n = 1;
  while (totalXpToReach(n + 1) <= xp) {
    n++;
  }
  return n;
}

typedef LevelProgress = ({int level, int xpIntoLevel, int xpForLevel});

extension LevelFraction on LevelProgress {
  /// How far into the level, 0–1.
  double get fraction => xpIntoLevel / xpForLevel;
}

LevelProgress progressWithinLevel(int xp) {
  final level = levelForXp(xp);
  return (
    level: level,
    xpIntoLevel: xp - totalXpToReach(level),
    xpForLevel: requirement(level),
  );
}
