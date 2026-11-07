import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/progress/data/streak.dart';
import 'package:pindoro/features/progress/ui/daily_goal.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The streak in full (canvas R2-02): count and best, this month's calendar,
/// freezes held, the daily goal with Change, and Play a round.
class StreakScreen extends ConsumerWidget {
  const StreakScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(streakProvider).value;
    if (view == null) return const Scaffold();
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final summary = view.summary;
    final days = formatNumber(summary.days);
    final best = l10n.streakBest(summary.best, formatNumber(summary.best));
    final xp = formatNumber(view.todayXp);
    final goal = formatNumber(view.goal);
    return PageScaffold(
      title: l10n.streakTitle,
      footer: PindoroButton(
        label: l10n.streakPlay,
        icon: PindoroGlyph.play,
        hero: true,
        onPressed: () => context.push(Routes.round),
      ),
      children: [
        Semantics(
          label: '${l10n.streakDays(days)}. $best',
          excludeSemantics: true,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: PindoroSpace.s3,
            children: [
              PindoroIcon(
                PindoroGlyph.flame,
                size: PindoroSize.nodeCurrent - PindoroSpace.s2,
                color: c.streakFlame,
                accent: c.streakCore,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    days,
                    style: PindoroType.numericXl.copyWith(color: c.streakText),
                  ),
                  Text(
                    l10n.streakDayStreak,
                    style: PindoroType.titleMd.copyWith(color: c.textPrimary),
                  ),
                ],
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: PindoroSpace.s1),
                  child: Text(
                    best,
                    style: PindoroType.bodySm.copyWith(color: c.textSecondary),
                  ),
                ),
              ),
            ],
          ),
        ),
        LipBox(
          border: c.lineBase,
          padding: const EdgeInsets.all(PindoroSpace.s4),
          child: Column(
            spacing: PindoroSpace.s3,
            children: [
              _MonthHeader(month: summary.today),
              _MonthCalendar(view: view),
            ],
          ),
        ),
        if (summary.freezes > 0)
          StreakFreezeCard(
            title: l10n.streakFreezeHeld(
              summary.freezes,
              StreakRules.maxFreezes,
            ),
            body: l10n.streakFreezeBody,
          )
        else
          StreakFreezeCard(
            title: l10n.streakFreezeNone,
            body: l10n.streakFreezeNoneBody,
          ),
        LipBox(
          border: c.lineBase,
          padding: const EdgeInsetsDirectional.fromSTEB(
            PindoroSpace.s4,
            PindoroSpace.s3,
            PindoroSpace.s3,
            PindoroSpace.s3,
          ),
          child: Row(
            spacing: PindoroSpace.s3,
            children: [
              GoalRing(view),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.dailyGoalTitle(goal),
                      style: PindoroType.titleMd.copyWith(color: c.textPrimary),
                    ),
                    Text(
                      summary.metToday
                          ? l10n.dailyGoalMetToday(xp)
                          : l10n.dailyGoalToday(xp, goal),
                      style: PindoroType.bodySm.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              PindoroButton(
                label: l10n.dailyGoalChange,
                variant: PindoroButtonVariant.secondary,
                onPressed: () => showDailyGoalSheet(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Row(
      spacing: PindoroSpace.s3,
      children: [
        Expanded(
          child: Text(
            DateFormat.MMMM(locale).format(month),
            style: PindoroType.titleMd.copyWith(color: c.textPrimary),
          ),
        ),
        Flexible(
          child: Text(
            context.l10n.streakLegend,
            textAlign: TextAlign.end,
            style: PindoroType.labelMd.copyWith(color: c.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// This month: goal days, frozen days, missed days since the first goal day,
/// and today ringed; one screen-reader label lists them.
class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({required this.view});

  final StreakView view;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final material = MaterialLocalizations.of(context);
    final today = view.summary.today;
    final first = view.metDays.isEmpty
        ? null
        : view.metDays.reduce((a, b) => a.isBefore(b) ? a : b);
    DateTime dateOf(int day) => DateTime.utc(today.year, today.month, day);
    StreakDay stateOf(int day) {
      final date = dateOf(day);
      if (view.metDays.contains(date)) return StreakDay.met;
      if (view.summary.frozenDays.contains(date)) return StreakDay.frozen;
      if (date.isAfter(today) || first == null || date.isBefore(first)) {
        return StreakDay.plain;
      }
      return StreakDay.missed;
    }

    final monthDays = DateUtils.getDaysInMonth(today.year, today.month);
    List<int> daysIn(StreakDay state) => [
      for (var d = 1; d <= monthDays; d++)
        if (stateOf(d) == state) d,
    ];
    final met = daysIn(StreakDay.met);
    final frozen = daysIn(StreakDay.frozen);
    final narrow = material.narrowWeekdays;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final label = [
      DateFormat.MMMM(locale).format(today),
      if (met.isEmpty)
        l10n.streakCalendarNone
      else
        l10n.streakCalendarMet(met.join(', ')),
      if (frozen.isNotEmpty) l10n.streakCalendarFrozen(frozen.join(', ')),
      l10n.streakCalendarToday('${today.day}'),
    ].join('. ');
    return StreakCalendar(
      month: today,
      today: today.day,
      dayState: stateOf,
      // MaterialLocalizations lists weekdays from Sunday, index 0.
      weekdays: [...narrow.skip(1), narrow.first],
      firstWeekday: material.firstDayOfWeekIndex == 0
          ? DateTime.sunday
          : material.firstDayOfWeekIndex,
      semanticLabel: label,
    );
  }
}
