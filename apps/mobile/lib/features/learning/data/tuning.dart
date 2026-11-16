import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// What the Memory model screen shows (SPEC §12): the calibration bins, the
/// reviews that moved a card, tier C relief now, and the minutes a day it
/// is measured against.
typedef MemoryModel = ({
  List<CalibrationBin> bins,
  int reviews,
  ({bool on, int meanS}) relief,
  int minutesPerDay,
});

final memoryModelProvider = FutureProvider.autoDispose<MemoryModel>((
  ref,
) async {
  final log = await ref.watch(learningDaoProvider).log();
  final minutes = (await ref.watch(settingsProvider.future)).minutesPerDay;
  return (
    bins: calibration(log),
    reviews: log.where(changesSchedule).length,
    relief: tierCRelief(
      log,
      minutesPerDay: minutes,
      now: ref.watch(clockProvider)(),
    ),
    minutesPerDay: minutes,
  );
});
