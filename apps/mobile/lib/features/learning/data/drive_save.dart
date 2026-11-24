import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/features/learning/data/drive_log.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/route_book.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Reviews a drive's [decisions]' J cards ([creditDrive], [hesitated] alike in order) and saves
/// the reviews and the evidence; the reviews that were a success ([credited]) and Again
/// ([failed]), and what each decision did to its card ([effects], item 124).
Future<({int credited, int failed, List<String?> effects})> saveDriveCredit(
  Ref ref,
  List<PassedDecision> decisions,
  List<bool> hesitated,
  DateTime now,
) async {
  final dao = ref.read(learningDaoProvider);
  final book = (await ref.read(routeBookProvider.future)).questions;
  final since = now.subtract(
    const Duration(days: LearningConfig.habitWindowDays),
  );
  final passes = <String, List<DateTime>>{};
  for (final r in await ref.read(driveLogDaoProvider).decisions()) {
    if (r.itemKey case final key? when r.at.isAfter(since)) {
      passes.putIfAbsent(key, () => []).add(r.at);
    }
  }
  final (:evidence, :reviews, :effects) = creditDrive(
    decisions,
    hesitated,
    cards: {for (final c in await dao.cards()) c.itemId: c},
    isTurn: (key) => book[key] is TurnQuestion,
    lastCredited: {
      for (final e in await dao.log(since: since))
        if (e.source == ReviewSource.drive && e.rating.isSuccess)
          e.itemId: e.ts,
    },
    passes: passes,
    now: now,
  );
  if (evidence.isNotEmpty || reviews.isNotEmpty) {
    await dao.saveTest(
      source: ReviewSource.drive,
      at: now,
      evidence: evidence,
      reviews: reviews,
    );
  }
  final credited = reviews.where((r) => r.log.rating.isSuccess).length;
  return (
    credited: credited,
    failed: reviews.length - credited,
    effects: effects,
  );
}
