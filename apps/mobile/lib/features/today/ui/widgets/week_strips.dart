import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/cards.dart';
import 'package:pindoro/features/progress/data/streak.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// What comes due on each of the next 7 days (Next 7 days strip), with how
/// the week reads: the daily average, the week's total, the catch-up day or
/// tomorrow's count.
class NextWeek extends ConsumerWidget {
  const NextWeek({super.key, required this.plan, required this.done});

  final SessionPlan plan;
  final bool done;

  static const int _days = 7;

  /// From this daily average the strip reads it as a rate, not a total.
  static const int _perDayFrom = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final now = ref.watch(clockProvider)();
    final cards = ref.watch(reviewedCardsProvider).value ?? const [];
    final counts = forecast(cards, now, days: _days);
    final days = [for (var d = 0; d < _days; d++) now.add(Duration(days: d))];
    final total = counts.fold(0, (a, b) => a + b);
    final average = (total / _days).round();
    final minutes = ref.watch(settingsProvider).value?.minutesPerDay ?? 20;
    final caughtUp = now.add(
      Duration(
        days: catchUpDays(dueCount: plan.dueCount, minutesPerDay: minutes),
      ),
    );
    final meta = done
        ? l10n.todayWeekTomorrow(formatNumber(counts[1]))
        : plan.backlog
        ? l10n.todayWeekCaughtUp(
            (caughtUp.difference(now).inDays < _days
                    ? DateFormat.EEEE(locale)
                    : DateFormat.MMMd(locale))
                .format(caughtUp),
          )
        : average >= _perDayFrom
        ? l10n.todayWeekPerDay(formatNumber(average))
        : l10n.todayWeekTotal(total);
    return WeekBars(
      counts: counts,
      labels: [
        l10n.progressToday,
        for (final day in days.skip(1)) DateFormat.E(locale).format(day),
      ],
      title: l10n.todayNextWeek,
      meta: meta,
      format: formatNumber,
      semanticsLabel: l10n.a11yNextWeek(
        [
          for (final (i, day) in days.indexed)
            '${i == 0 ? l10n.progressToday : DateFormat.EEEE(locale).format(day)} ${formatNumber(counts[i])}',
        ].join(', '),
      ),
    );
  }
}

/// Today's done state: the last 7 days of the streak.
class LastWeek extends ConsumerWidget {
  const LastWeek({super.key});

  static const int _days = 7;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final view = ref.watch(streakProvider).value;
    if (view == null) return const SizedBox.shrink();
    final today = view.summary.today;
    final days = [
      for (var d = _days - 1; d >= 0; d--)
        calendarDay(today.subtract(Duration(days: d))),
    ];
    final states = [
      for (final day in days)
        view.metDays.contains(day)
            ? StreakDay.met
            : view.summary.frozenDays.contains(day)
            ? StreakDay.frozen
            : StreakDay.missed,
    ];
    final counted = formatNumber(
      states.where((s) => s == StreakDay.met).length,
    );
    return StreakWeek(
      days: states,
      labels: [
        for (final day in days.take(_days - 1))
          DateFormat.E(locale).format(day),
        l10n.progressToday,
      ],
      title: l10n.todayLastWeek,
      meta: l10n.todayLastWeekCounted(counted),
      semanticsLabel: l10n.a11yLastWeek(counted),
    );
  }
}
