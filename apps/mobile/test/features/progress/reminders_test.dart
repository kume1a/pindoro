import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/features/progress/data/reminders.dart';

void main() {
  final today = DateTime.utc(2026, 11, 20);
  DateTime ago(int days) => today.subtract(Duration(days: days));
  DateTime at(int day, int hour) => DateTime(2026, 11, day, hour);

  /// Goal days from 3 days ago to yesterday: a live 3-day streak.
  final live = {ago(3), ago(2), ago(1)};

  test('before 19:00 with today unmet: today, naming the live streak', () {
    expect(nextReminder(live, at(20, 9)), (at: at(20, 19), streakDays: 3));
  });

  test('today met: tomorrow, naming the streak with today in it', () {
    expect(nextReminder({...live, today}, at(20, 9)), (
      at: at(21, 19),
      streakDays: 4,
    ));
  });

  test('after 19:00 with today unmet: tomorrow, once the streak has ended', () {
    expect(nextReminder(live, at(20, 20)), (at: at(21, 19), streakDays: 0));
  });

  test('no streak: still reminds, with nothing at stake', () {
    expect(nextReminder({}, at(20, 9)), (at: at(20, 19), streakDays: 0));
  });
}
