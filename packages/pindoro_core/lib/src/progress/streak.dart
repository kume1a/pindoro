import 'dart:math';

/// The local date of [local] as UTC midnight, so stepping a day never meets
/// a daylight-saving shift.
DateTime calendarDay(DateTime local) =>
    DateTime.utc(local.year, local.month, local.day);

/// `YYYY-MM-DD`, how a calendar day is stored.
String dayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

DateTime parseDayKey(String key) => DateTime.parse('${key}T00:00:00Z');

/// The daily-habit rules (v1-screens.md § R2 · v1.1 Daily habit).
abstract final class StreakRules {
  static const List<int> goals = [250, 500, 1000];
  static const int defaultGoal = 500;

  /// A freeze is earned on every this-many goal days of a run.
  static const int freezeEvery = 7;
  static const int maxFreezes = 2;

  /// From this local hour an unmet day puts a live streak at risk.
  static const int riskHour = 18;
  static const int reminderHour = 19;

  /// Streak lengths that get the big celebration.
  static const Set<int> milestones = {7, 30, 100, 365};
}

enum StreakPillState { active, atRisk, frozen, off }

class StreakSummary {
  const StreakSummary({
    required this.today,
    required this.days,
    required this.best,
    required this.freezes,
    required this.metToday,
    required this.frozenDays,
  });

  final DateTime today;

  /// Goal days in the unbroken run; frozen days keep it without adding.
  final int days;
  final int best;

  /// Freezes held now.
  final int freezes;
  final bool metToday;
  final Set<DateTime> frozenDays;

  bool get yesterdayFrozen =>
      frozenDays.contains(today.subtract(const Duration(days: 1)));

  /// At risk wins over frozen: it's the more urgent of the two.
  StreakPillState pillState(DateTime now) {
    if (metToday) return StreakPillState.active;
    if (days > 0 && now.hour >= StreakRules.riskHour) {
      return StreakPillState.atRisk;
    }
    if (yesterdayFrozen) return StreakPillState.frozen;
    return StreakPillState.off;
  }
}

/// The streak on [today] from the days the goal was met. Walks every day from
/// the first goal day: a goal day grows the run (and earns a freeze on every
/// [StreakRules.freezeEvery]th), a missed past day spends a freeze or resets
/// the run. [today] unmet isn't missed yet. A later [today] forecasts what
/// missing the days in between would do.
// ponytail: walks every day since the first goal day, a few thousand at most.
StreakSummary streakOf(Set<DateTime> metDays, DateTime today) {
  var run = 0;
  var best = 0;
  var freezes = 0;
  final frozen = <DateTime>{};
  if (metDays.isNotEmpty) {
    var day = metDays.reduce((a, b) => a.isBefore(b) ? a : b);
    while (!day.isAfter(today)) {
      if (metDays.contains(day)) {
        run++;
        best = max(best, run);
        if (run % StreakRules.freezeEvery == 0) {
          freezes = min(StreakRules.maxFreezes, freezes + 1);
        }
      } else if (day != today) {
        if (freezes > 0) {
          freezes--;
          frozen.add(day);
        } else {
          run = 0;
        }
      }
      day = day.add(const Duration(days: 1));
    }
  }
  return StreakSummary(
    today: today,
    days: run,
    best: best,
    freezes: freezes,
    metToday: metDays.contains(today),
    frozenDays: frozen,
  );
}
