import 'package:pindoro_core/src/progress/streak.dart';

/// The weekly leagues (v1-screens.md § R5 · v2.1 Leagues). The server ranks
/// and moves players; the app needs the week, the tiers and the name rule.
/// `apps/api/src/modules/leagues/leagues.rules.ts` holds the same rules;
/// both pass `shared/fixtures/league_vectors.json`.
abstract final class LeagueRules {
  /// Alley, Lane, Street, Avenue, Boulevard, Highway.
  static const int tiers = 6;
  static const int nameMin = 2;
  static const int nameMax = 20;

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

/// [raw] trimmed, with runs of whitespace as one space.
String leagueName(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

final _nameShape = RegExp(r"^\p{L}[\p{L}\p{M} .'’-]*$", unicode: true);

/// Whether a [leagueName] may be used: 2–20 characters, a letter first, then
/// letters (with their marks), spaces and `. ' ’ -`.
bool isLeagueName(String name) {
  final length = name.runes.length;
  return length >= LeagueRules.nameMin &&
      length <= LeagueRules.nameMax &&
      _nameShape.hasMatch(name);
}
