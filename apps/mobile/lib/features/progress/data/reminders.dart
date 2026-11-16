import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

typedef ReminderNotice = ({DateTime at, String body, String channel});

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
