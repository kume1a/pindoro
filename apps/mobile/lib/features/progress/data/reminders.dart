import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/progress/data/streak.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:timezone/timezone.dart' as tz;

/// When the next reminder fires and the streak it names.
typedef ReminderPlan = ({DateTime at, int streakDays});

/// The next 19:00 whose day's goal isn't met: today's while it's ahead and
/// unmet, else tomorrow's. It names the streak at stake that day.
ReminderPlan nextReminder(Set<DateTime> metDays, DateTime now) {
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
  return (at: at, streakDays: streakOf(metDays, calendarDay(at)).days);
}

typedef ReminderNotice = ({DateTime at, String body, String channel});

/// The reminder to schedule now, in the app's language; null with the
/// reminder off.
final reminderProvider = FutureProvider<ReminderNotice?>((ref) async {
  final settings = await ref.watch(settingsProvider.future);
  if (!settings.reminder) return null;
  final streak = await ref.watch(streakProvider.future);
  final plan = nextReminder(streak.metDays, DateTime.now());
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

/// The one daily reminder, through the platform's local notifications.
class Reminders {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _ready;

  static const int _id = 1;

  Future<void> _init() => _ready ??= _plugin
      .initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      )
      .then((_) {});

  /// Asks to show notifications (Android 13+, iOS); true when allowed.
  Future<bool> requestPermission() async {
    await _init();
    final granted = switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission(),
      TargetPlatform.iOS =>
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true),
      _ => false,
    };
    return granted ?? false;
  }

  /// Replaces the scheduled reminder. A fixed instant in UTC needs no time
  /// zone database; inexact delivery needs no exact-alarm permission.
  Future<void> schedule(ReminderNotice notice) async {
    await _init();
    await _plugin.zonedSchedule(
      id: _id,
      scheduledDate: tz.TZDateTime.from(notice.at.toUtc(), tz.UTC),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails('reminder', notice.channel),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      body: notice.body,
    );
  }

  Future<void> cancel() async {
    await _init();
    await _plugin.cancel(id: _id);
  }
}

/// Overridden in tests: the plugin has no platform side there.
final remindersProvider = Provider<Reminders>((ref) => Reminders());
