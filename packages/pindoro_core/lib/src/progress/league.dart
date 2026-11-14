import 'package:pindoro_core/src/progress/streak.dart';

/// The weekly leagues (v1-screens.md § R5 · v2.1 Leagues). The server ranks
/// and moves players; the app needs the week and the tiers.
/// `apps/api/src/modules/leagues/leagues.rules.ts` holds the same rules;
/// both pass `shared/fixtures/league_vectors.json`.
abstract final class LeagueRules {
  /// Alley, Lane, Street, Avenue, Boulevard, Highway.
  static const int tiers = 6;

  /// Weeks run on Tbilisi time, which has no daylight saving.
  static const Duration offset = Duration(hours: 4);
}

/// A league week: its Monday as `YYYY-MM-DD` and its UTC bounds.
typedef LeagueWeek = ({String key, DateTime start, DateTime end});

/// The league week holding [now].
LeagueWeek leagueWeek(DateTime now) {
  final local = now.toUtc().add(LeagueRules.offset);
  final monday = DateTime.utc(
    local.year,
    local.month,
    local.day - (local.weekday - DateTime.monday),
  );
  final start = monday.subtract(LeagueRules.offset);
  return (
    key: dayKey(monday),
    start: start,
    end: start.add(const Duration(days: DateTime.daysPerWeek)),
  );
}
