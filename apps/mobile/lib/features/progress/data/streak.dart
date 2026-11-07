import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// What the streak pill, the daily goal ring, the Streak screen and the
/// reminder show.
typedef StreakView = ({
  StreakSummary summary,
  Set<DateTime> metDays,
  int goal,
  int todayXp,

  /// The round that met today's goal; null before then, or when lowering the
  /// goal met it.
  String? goalRoundId,
});

extension StreakViewGoal on StreakView {
  /// Today's XP over the goal, 0–1.
  double get goalProgress => (todayXp / goal).clamp(0, 1).toDouble();
}

/// Reloads with progress and the daily goal; the app root also refreshes it
/// on resume, when the date may have changed.
final streakProvider = FutureProvider<StreakView>((ref) async {
  ref.watch(progressChangesProvider);
  final goal = await ref.watch(
    settingsProvider.selectAsync((s) => s.dailyGoal),
  );
  final dao = ref.watch(progressDaoProvider);
  final today = calendarDay(DateTime.now());
  final rounds = await dao.goalDayRounds();
  final metDays = rounds.keys.toSet();
  return (
    summary: streakOf(metDays, today),
    metDays: metDays,
    goal: goal,
    todayXp: await dao.xpOn(today),
    goalRoundId: rounds[today],
  );
});
