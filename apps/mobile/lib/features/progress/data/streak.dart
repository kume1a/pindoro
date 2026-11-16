import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// What the streak pill, the Streak screen and the reminder show.
typedef StreakView = ({
  StreakSummary summary,
  Set<DateTime> metDays,

  /// The Explore round whose answer made today count; null before then, or
  /// when a session did.
  String? todayRoundId,
});

/// Reloads with progress; the app root also refreshes it on resume, when the
/// date may have changed. Which days count is decided as answers come
/// (`markDayIfCounts`).
final streakProvider = FutureProvider<StreakView>((ref) async {
  ref.watch(progressChangesProvider);
  final rounds = await ref.watch(progressDaoProvider).goalDayRounds();
  final today = calendarDay(DateTime.now());
  final metDays = rounds.keys.toSet();
  return (
    summary: streakOf(metDays, today),
    metDays: metDays,
    todayRoundId: rounds[today],
  );
});
