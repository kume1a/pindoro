import 'package:pindoro_core/pindoro_core.dart';
import 'package:test/test.dart';

final _today = DateTime.utc(2026, 11, 20);

DateTime _ago(int days) => _today.subtract(Duration(days: days));

/// Met days from [from] days ago up to [to] days ago, both included.
Set<DateTime> _run(int from, int to) => {
  for (var d = from; d >= to; d--) _ago(d),
};

void main() {
  test('no goal days: nothing to show', () {
    final s = streakOf({}, _today);
    expect((s.days, s.best, s.freezes, s.metToday), (0, 0, 0, false));
  });

  test('days in a row ending today', () {
    final s = streakOf(_run(2, 0), _today);
    expect((s.days, s.best, s.metToday), (3, 3, true));
  });

  test('a run ending yesterday is still alive until today ends', () {
    final s = streakOf(_run(3, 1), _today);
    expect((s.days, s.metToday), (3, false));
  });

  test('a missed day without a freeze resets; best keeps the old run', () {
    final s = streakOf({..._run(10, 6), ..._run(2, 0)}, _today);
    expect((s.days, s.best), (3, 5));
  });

  test('seven days earn a freeze that covers the next missed day', () {
    final s = streakOf({..._run(9, 3), ..._run(1, 0)}, _today);
    expect(s.frozenDays, {_ago(2)});
    expect((s.days, s.freezes), (9, 0));
  });

  test('freezes cap at two', () {
    expect(streakOf(_run(13, 0), _today).freezes, 2);
    expect(streakOf(_run(20, 0), _today).freezes, 2);
  });

  test('two missed days with one freeze reset the streak', () {
    final s = streakOf({..._run(10, 4), ..._run(1, 0)}, _today);
    expect(s.frozenDays, {_ago(3)});
    expect((s.days, s.best), (2, 7));
  });

  test('today unplayed is not missed yet', () {
    final s = streakOf(_run(3, 1), _today);
    expect(s.frozenDays, isEmpty);
    expect(s.freezes, 0);
  });

  test('tomorrow forecasts a missed today: a freeze covers it', () {
    final tomorrow = _today.add(const Duration(days: 1));
    final s = streakOf(_run(7, 1), tomorrow);
    expect(s.frozenDays, {_today});
    expect(s.days, 7);
  });

  group('pill state', () {
    DateTime at(int hour, [int minute = 0]) =>
        DateTime(_today.year, _today.month, _today.day, hour, minute);

    test('goal met today is active, even late', () {
      expect(
        streakOf(_run(1, 0), _today).pillState(at(23)),
        StreakPillState.active,
      );
    });

    test('a live streak turns at risk at 18:00', () {
      final s = streakOf(_run(3, 1), _today);
      expect(s.pillState(at(17, 59)), StreakPillState.off);
      expect(s.pillState(at(18)), StreakPillState.atRisk);
    });

    test('after a frozen yesterday the pill is frozen until 18:00', () {
      final s = streakOf(_run(8, 2), _today);
      expect(s.yesterdayFrozen, isTrue);
      expect(s.pillState(at(9)), StreakPillState.frozen);
      expect(s.pillState(at(19)), StreakPillState.atRisk);
    });

    test('no streak is off, even in the evening', () {
      expect(streakOf({}, _today).pillState(at(20)), StreakPillState.off);
    });
  });

  test('day keys round-trip as calendar dates', () {
    expect(dayKey(DateTime.utc(2026, 3, 7)), '2026-03-07');
    expect(parseDayKey('2026-03-07'), DateTime.utc(2026, 3, 7));
    expect(calendarDay(DateTime(2026, 3, 7, 23, 59)), DateTime.utc(2026, 3, 7));
  });
}
