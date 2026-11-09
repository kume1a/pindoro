import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/features/course/data/course_data.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// A finished unit, the one after it (null after the last) and what was
/// earned and driven in it.
typedef UnitDone = ({
  CourseUnit unit,
  CourseUnit? next,
  ({int xp, int trips}) summary,
});

/// What Unit complete shows for one unit; null when the course changed.
final unitDoneProvider = FutureProvider.autoDispose.family<UnitDone?, String>((
  ref,
  unitId,
) async {
  final dao = ref.watch(progressDaoProvider);
  final plan = await ref.watch(coursePlanProvider.future);
  final units = plan?.units ?? const <CourseUnit>[];
  final i = units.indexWhere((u) => u.id == unitId);
  if (plan == null || i < 0) return null;
  return (
    unit: units[i],
    next: units.elementAtOrNull(i + 1),
    summary: await dao.unitSummary(plan.pack.city().id, unitId),
  );
});
