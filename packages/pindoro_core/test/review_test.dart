import 'package:pindoro_core/pindoro_core.dart';
import 'package:test/test.dart';

final _day = DateTime.utc(2026, 11, 20);

DateTime _plus(int days) => _day.add(Duration(days: days));

ReviewState _at(int step, {int greatRun = 0}) =>
    (step: step, greatRun: greatRun, dueOn: _day);

void main() {
  test('a Great or Perfect on a new street is nothing to review', () {
    expect(nextReview(null, Tier.great, _day), isNull);
    expect(nextReview(null, Tier.perfect, _day), isNull);
  });

  test('Close and Miss enter at step 1, due the next day', () {
    for (final tier in [Tier.close, Tier.miss]) {
      expect(nextReview(null, tier, _day), (
        step: 1,
        greatRun: 0,
        dueOn: _plus(1),
      ));
    }
  });

  test('a Great advances a step and starts the run', () {
    expect(nextReview(_at(1), Tier.great, _day), (
      step: 2,
      greatRun: 1,
      dueOn: _plus(3),
    ));
  });

  test('two Greats in a row graduate the street', () {
    expect(nextReview(_at(2, greatRun: 1), Tier.perfect, _day), isNull);
  });

  test('Close advances a step but breaks the run', () {
    expect(nextReview(_at(2, greatRun: 1), Tier.close, _day), (
      step: 3,
      greatRun: 0,
      dueOn: _plus(7),
    ));
  });

  test('the step stops at 4, every 21 days', () {
    expect(nextReview(_at(4), Tier.close, _day), (
      step: 4,
      greatRun: 0,
      dueOn: _plus(21),
    ));
  });

  test('a Miss sends the street back to step 1', () {
    expect(nextReview(_at(3, greatRun: 1), Tier.miss, _day), (
      step: 1,
      greatRun: 0,
      dueOn: _plus(1),
    ));
  });
}
