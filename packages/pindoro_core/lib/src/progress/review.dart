import 'dart:math';

import '../scoring/scoring.dart';

/// The Pit stop's spaced repetition (v1-screens.md § R3 · v1.2 Pit stop).
abstract final class ReviewRules {
  /// Days until a street at each step comes back; steps run 1 to 4.
  static const List<int> intervals = [1, 3, 7, 21];
  static int get steps => intervals.length;

  /// Great-or-better answers in a row that take a street out.
  static const int graduateAfter = 2;

  /// Streets one Pit stop round asks, most overdue first.
  static const int pitStopSize = 10;
}

/// A street in the Pit stop: its step (1–4), Great-or-better answers in a
/// row, and the calendar day it's due.
typedef ReviewState = ({int step, int greatRun, DateTime dueOn});

/// The street's review after an answer of [tier] on calendar [day]; null
/// when it isn't (or is no longer) in the Pit stop. Close and Miss bring a
/// street in at step 1; a Miss sends it back there. Close advances a step
/// but breaks the run of Greats; Great or Perfect advances it and, on the
/// [ReviewRules.graduateAfter]th in a row, graduates it.
ReviewState? nextReview(ReviewState? current, Tier tier, DateTime day) {
  ReviewState at(int step, int greatRun) => (
    step: step,
    greatRun: greatRun,
    dueOn: day.add(Duration(days: ReviewRules.intervals[step - 1])),
  );
  final next = current == null ? 1 : min(current.step + 1, ReviewRules.steps);
  return switch (tier) {
    Tier.miss => at(1, 0),
    Tier.close => at(next, 0),
    Tier.great || Tier.perfect when current == null => null,
    Tier.great || Tier.perfect
        when current!.greatRun + 1 >= ReviewRules.graduateAfter =>
      null,
    Tier.great || Tier.perfect => at(next, current!.greatRun + 1),
  };
}
