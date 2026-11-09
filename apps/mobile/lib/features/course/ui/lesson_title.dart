import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// "Vazha-Pshavela Avenue and 3 more": a lesson named after its longest
/// street.
String lessonTitle(
  AppLocalizations l10n,
  CourseLesson lesson,
  Settings? settings,
) {
  final longest = lesson.streets.reduce(
    (a, b) => b.lengthM > a.lengthM ? b : a,
  );
  return l10n.lessonTitle(
    streetName(longest, settings),
    lesson.streets.length - 1,
  );
}
