/// The start of the calendar day after [now], in [now]'s time zone (SPEC §16.3).
DateTime nextMidnight(DateTime now) => daysAfter(now, 1);

/// The start of [now]'s calendar day, in [now]'s time zone (SPEC §16.3).
DateTime startOfDay(DateTime now) => daysAfter(now, 0);

/// Midnight [days] calendar days from [now]'s day, in [now]'s time zone; calendar arithmetic
/// keeps DST days right.
DateTime daysAfter(DateTime now, int days) => now.isUtc
    ? DateTime.utc(now.year, now.month, now.day + days)
    : DateTime(now.year, now.month, now.day + days);

/// Calendar days from [from] to [to], both midnights (DST days count once).
int calendarDaysBetween(DateTime from, DateTime to) =>
    (to.difference(from).inHours / 24).round();
