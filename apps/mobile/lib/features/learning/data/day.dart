import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/hold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/today_plan.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro/features/progress/data/reminders.dart';
import 'package:pindoro/features/progress/data/streak.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Marks today on the streak once it counts (SPEC §8): something answered,
/// then nothing the pack asks due before midnight or the day's minutes
/// spent. Called after every learning answer; [roundId] names an Explore
/// round, [asks] is a session's [asksCardProvider] filter, read once for it.
Future<void> markDayIfCounts(Ref ref, {String? roundId, AsksCard? asks}) async {
  final now = ref.read(clockProvider)();
  final learning = ref.read(learningDaoProvider);
  final settings = await ref.read(settingsDaoProvider).read();
  final asked = asks ?? await ref.hold<AsksCard>(asksCardProvider.future);
  final counts = dayCounts(
    cards: (await learning.cards()).where(asked),
    today: await learning.log(since: startOfDay(now)),
    minutesPerDay: settings.minutesPerDay,
    now: now,
  );
  if (!counts) return;
  await ref.read(progressDaoProvider).markDay(now, roundId: roundId);
}

/// When the next reminder fires and the streak it names.
typedef ReminderPlan = ({DateTime at, int streakDays});

/// The next 19:00 whose day hasn't counted: today's while it's ahead, else
/// tomorrow's. Null when no review is due by the end of that day ([dueBy]
/// says whether any is due before a time): the reminder is for reviews.
ReminderPlan? nextReminder(
  Set<DateTime> metDays,
  DateTime now, {
  required bool Function(DateTime before) dueBy,
}) {
  DateTime reminderOn(int dayOffset) => DateTime(
    now.year,
    now.month,
    now.day + dayOffset,
    StreakRules.reminderHour,
  );
  final today = reminderOn(0);
  final at = now.isBefore(today) && !metDays.contains(calendarDay(now))
      ? today
      : reminderOn(1);
  if (!dueBy(nextMidnight(at))) return null;
  return (at: at, streakDays: streakOf(metDays, calendarDay(at)).days);
}

/// The reminder to schedule now, in the app's language; null with the
/// reminder off or nothing due.
final reminderProvider = FutureProvider<ReminderNotice?>((ref) async {
  final settings = await ref.watch(settingsProvider.future);
  if (!settings.reminder) return null;
  final streak = await ref.watch(streakProvider.future);
  final asks = await ref.watch(asksCardProvider.future);
  final cards = (await ref.read(learningDaoProvider).cards()).where(asks);
  final plan = nextReminder(
    streak.metDays,
    ref.read(clockProvider)(),
    dueBy: (t) => cards.any((c) => isDueBefore(c, t)),
  );
  if (plan == null) return null;
  final l10n = lookupAppLocalizations(_reminderLocale(settings));
  return (
    at: plan.at,
    body: plan.streakDays > 0
        ? l10n.reminderStreak(formatNumber(plan.streakDays))
        : l10n.reminderNoStreak,
    channel: l10n.reminderChannel,
  );
});

/// The app's language, or the device's when it's one the app speaks.
Locale _reminderLocale(Settings settings) =>
    settings.locale ??
    (PlatformDispatcher.instance.locale.languageCode == 'ka'
        ? const Locale('ka')
        : const Locale('en'));
