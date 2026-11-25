import 'package:pindoro_core/pindoro_core.dart';

import 'fsrs.dart';
import 'planner.dart';
import 'today.dart';

/// One graded answer of a session, for Session done: the street a mix-up confused it with in
/// [mixUp].
typedef SessionAnswer = ({
  StepKind kind,
  Rating rating,
  Tier tier,
  String streetId,
  String? mixUp,
});

/// Session done's figures from the session's [answers] (a crossings drill's are not graded)
/// answered at [times]: the reviews, the share recalled, the mix-ups (the street's id, the
/// other's), the streets Close twice or more, and the minutes played.
({
  int reviews,
  int recalledPercent,
  List<(String, String)> mixUps,
  List<String> closeTwice,
  int minutes,
})
summarizeSession(List<SessionAnswer> answers, List<DateTime> times) {
  final graded = [
    for (final a in answers)
      if (a.kind != StepKind.crossings) a,
  ];
  final passed = graded.where((a) => a.rating.isSuccess).length;
  final closes = <String, int>{};
  for (final a in graded.where((a) => a.tier == Tier.close)) {
    closes.update(a.streetId, (n) => n + 1, ifAbsent: () => 1);
  }
  return (
    reviews: graded
        .where(
          (a) => a.kind == StepKind.review || a.kind == StepKind.familySweep,
        )
        .length,
    recalledPercent: graded.isEmpty
        ? 0
        : (100 * passed / graded.length).round(),
    mixUps: [
      for (final a in graded)
        if (a.mixUp case final hit?) (a.streetId, hit),
    ],
    closeTwice: [
      for (final MapEntry(:key, :value) in closes.entries)
        if (value >= 2) key,
    ],
    minutes: (activeSeconds(times) / 60).ceil(),
  );
}
