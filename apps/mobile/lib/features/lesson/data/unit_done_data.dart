import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/features/course/data/course_data.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// A finished unit, the next one to play (null when none is left; placement
/// can have done the units right after it), what was earned and driven in it
/// and the player's XP in all.
typedef UnitDone = ({
  CourseUnit unit,
  CourseUnit? next,
  ({int xp, int trips}) summary,
  int totalXp,
});

/// What Unit complete shows for one unit; null when the course changed.
final unitDoneProvider = FutureProvider.autoDispose.family<UnitDone?, String>((
  ref,
  unitId,
) async {
  final dao = ref.watch(progressDaoProvider);
  final course = await ref.watch(courseProvider.future);
  final units = course?.units ?? const <UnitProgress>[];
  final i = units.indexWhere((u) => u.unit.id == unitId);
  if (course == null || i < 0) return null;
  return (
    unit: units[i].unit,
    next: units.skip(i + 1).where((u) => !u.done).firstOrNull?.unit,
    summary: await dao.unitSummary(course.plan.pack.city().id, unitId),
    totalXp: await dao.totalXp(),
  );
});
