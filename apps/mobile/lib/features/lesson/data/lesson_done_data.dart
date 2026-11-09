import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/features/course/data/course_data.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';

typedef LessonDone = ({
  LessonResult result,

  /// Null when the course changed since (another city's pack, say).
  CourseUnit? unit,
  CourseLesson? lesson,
  int totalXp,
  int fixes,
  int fixXp,

  /// Different streets answered.
  int streets,

  /// This result reached today's daily goal: the streak grew with it.
  bool grewStreak,
});

/// What Lesson complete shows for one lesson result.
final lessonDoneProvider = FutureProvider.autoDispose
    .family<LessonDone, String>((ref, resultId) async {
      final dao = ref.watch(progressDaoProvider);
      final result = await dao.lessonResult(resultId);
      final answers = await dao.lessonAnswersOf(resultId);
      final plan = await ref.watch(coursePlanProvider.future);
      final settings = await ref.read(settingsDaoProvider).read();
      final unit = plan?.units.where((u) => u.id == result.unitId).firstOrNull;
      final goal = settings.dailyGoal;
      final today = await dao.xpOn(calendarDay(result.finishedAt));
      final fixes = [
        for (final a in answers)
          if (a.fix) a,
      ];
      return (
        result: result,
        unit: unit,
        lesson: unit?.lessons
            .where((l) => l.number == result.lesson)
            .firstOrNull,
        totalXp: await dao.totalXp(),
        fixes: fixes.length,
        fixXp: fixes.fold(0, (sum, a) => sum + a.xp),
        streets: {for (final a in answers) a.streetId}.length,
        grewStreak: today >= goal && today - result.xp < goal,
      );
    });
