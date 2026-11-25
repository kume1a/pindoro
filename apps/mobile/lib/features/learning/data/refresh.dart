import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/features/learning/data/cards.dart';
import 'package:pindoro/features/learning/data/memory_summary.dart';
import 'package:pindoro/features/learning/data/progress.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/learning/data/today_plan.dart';

/// Reloads what the tabs show from the learning tables, after anything that
/// may have written to them (a session, a round, another tab). Learning
/// providers read with futures, so writers invalidate them.
void refreshLearning(WidgetRef ref) => ref
  ..invalidate(learnCityProvider)
  ..invalidate(asksCardProvider)
  ..invalidate(cityCardsProvider)
  ..invalidate(reviewedCardsProvider)
  ..invalidate(todayPlanProvider)
  ..invalidate(cityMemoryProvider)
  ..invalidate(progressProvider)
  ..invalidate(runsProvider)
  ..invalidate(todayRunProvider)
  ..invalidate(mixUpsYesterdayProvider);
