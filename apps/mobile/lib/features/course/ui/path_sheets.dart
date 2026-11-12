import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/course/data/course_data.dart';
import 'package:pindoro/features/course/ui/lesson_title.dart';
import 'package:pindoro/features/course/ui/widgets/stop_sheet.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The Path's sheets (canvas R4-12, R4-40), opened from [context]: a stop's,
/// a locked unit's and the Final drive's.
class PathSheets {
  const PathSheets(this.context, this.ref, this.data, this.settings);

  final BuildContext context;
  final WidgetRef ref;
  final CourseData data;
  final Settings? settings;

  /// A locked unit's sheet (canvas R4-12): keep going ([onKeepGoing]), or
  /// Jump ahead by passing its Final drive.
  void lockedUnit(int u, {required VoidCallback onKeepGoing}) {
    ref.read(feedbackProvider).tap();
    final l10n = context.l10n;
    final unit = data.units[u].unit;
    final district = districtName(unit.district, settings);
    final current = data.units.current;
    final here = current == null
        ? null
        : districtName(data.units[current.unit].unit.district, settings);
    final previous = districtName(data.units[u - 1].unit.district, settings);
    unawaited(
      showStopSheet(
        context,
        kicker: l10n.pathSheetUnitLockedKicker(unit.number),
        title: district,
        body: l10n.pathSheetUnitLockedBody(previous, district),
        action: here == null ? l10n.commonContinue : l10n.pathKeepGoing(here),
        onAction: onKeepGoing,
        secondary: l10n.pathJumpAhead,
        onSecondary: () async {
          final explained = await _explainNoRoadGraph(
            kicker: l10n.pathSheetDriveKicker(unit.number, district),
            title: l10n.pathSheetDriveTitle(district),
          );
          if (explained || !context.mounted) return;
          unawaited(context.push(Routes.driveOf(unit.id)));
        },
      ),
    );
  }

  /// Stop [i] of unit [u]'s sheet.
  void stop(int u, int i) {
    ref.read(feedbackProvider).tap();
    final progress = data.units[u];
    final stop = progress.stops[i];
    switch (stop.kind) {
      case StopKind.finalDrive:
        unawaited(_finalDrive(u));
      case StopKind.pitStop:
        _pitStop(progress.unit);
      case StopKind.lesson:
        final lesson = progress.unit.lessons[stop.lesson! - 1];
        if (stop.state == StopState.current) {
          _nextLesson(progress.unit, lesson);
        } else {
          _playedLesson(progress.unit, lesson, stop);
        }
    }
  }

  /// The pack is known to have no road graph (an older format).
  bool get _noRoadGraph {
    final graph = ref.read(roadGraphProvider);
    return graph.hasValue && graph.value == null;
  }

  /// Road trips need a pack with a road graph: without one, a sheet says so
  /// and this is true, so no Final drive starts (nor once the Path is gone).
  Future<bool> _explainNoRoadGraph({
    required String kicker,
    required String title,
  }) async {
    final graph = await ref.read(roadGraphProvider.future);
    if (!context.mounted) return true;
    if (graph != null) return false;
    final city = data.plan.pack.city();
    unawaited(
      showStopSheet(
        context,
        kicker: kicker,
        title: title,
        body: context.l10n.pathSheetDriveNoGraph(
          context.localName(ka: city.nameKa, en: city.nameEn),
        ),
        action: context.l10n.commonContinue,
        onAction: () {},
      ),
    );
    return true;
  }

  /// The current Final drive's sheet (canvas R4-12, R4-40).
  Future<void> _finalDrive(int u) async {
    final l10n = context.l10n;
    final progress = data.units[u];
    final unit = progress.unit;
    final district = districtName(unit.district, settings);
    final next = data.units.elementAtOrNull(u + 1)?.unit;
    final left = CourseRules.finalDriveTrips - progress.tripsPassed;
    final kicker = l10n.pathSheetDriveKicker(unit.number, district);
    final title = l10n.pathSheetDriveTitle(district);
    final explained = await _explainNoRoadGraph(kicker: kicker, title: title);
    if (explained || !context.mounted) return;
    unawaited(
      showStopSheet(
        context,
        kicker: kicker,
        title: title,
        body: [
          l10n.pathSheetDriveBody,
          if (next != null)
            l10n.pathSheetDriveOpens(
              next.number,
              districtName(next.district, settings),
            ),
          if (progress.tripsPassed > 0)
            l10n.pathSheetDrivePassed(progress.tripsPassed),
        ].join(' '),
        chips: [
          (glyph: PindoroGlyph.car, label: l10n.pathChipTrips(left)),
          (
            glyph: PindoroGlyph.xp,
            label: l10n.pathChipUpToXp(
              formatNumber(
                left * ScoringConfig.perfectXp + CourseRules.unitBonusXp,
              ),
            ),
          ),
        ],
        action: l10n.pathStartDrive,
        onAction: () => context.push(Routes.driveOf(unit.id)),
      ),
    );
  }

  void _pitStop(CourseUnit unit) {
    final l10n = context.l10n;
    final count = data.pitStops[unit.id]?.length ?? 0;
    unawaited(
      showStopSheet(
        context,
        kicker: l10n.pathSheetPitKicker(
          unit.number,
          districtName(unit.district, settings),
        ),
        title: l10n.pathSheetPitTitle(count),
        body: l10n.pathSheetPitBody(unit.pitStopAfter, unit.pitStopAfter + 1),
        chips: [
          (glyph: PindoroGlyph.wrench, label: l10n.pathChipStreets(count)),
          (
            glyph: PindoroGlyph.xp,
            label: l10n.pathChipUpToXp(
              formatNumber(count * ScoringConfig.perfectXp),
            ),
          ),
        ],
        action: l10n.pathStartPitStop,
        onAction: () => context.push(Routes.unitPitStop(unit.id)),
      ),
    );
  }

  void _nextLesson(CourseUnit unit, CourseLesson lesson) {
    final l10n = context.l10n;
    final district = districtName(unit.district, settings);
    unawaited(
      showStopSheet(
        context,
        kicker: l10n.pathSheetLessonKicker(
          lesson.number,
          unit.lessons.length,
          unit.number,
          district,
        ),
        title: lessonTitle(l10n, lesson, settings),
        body: l10n.pathSheetLessonBody(lesson.streets.length, district),
        chips: [
          (
            glyph: PindoroGlyph.gauge,
            label: difficultyName(
              l10n,
              settings?.difficulty ?? Difficulty.medium,
            ),
          ),
          (
            glyph: PindoroGlyph.signpost,
            label: l10n.pathChipNewStreets(lesson.streets.length),
          ),
          (
            glyph: PindoroGlyph.xp,
            // A pack without a road graph plays no road trip.
            label: l10n.pathChipUpToXp(
              formatNumber(
                _noRoadGraph
                    ? LessonRules.maxXp - LessonRules.tripXp
                    : LessonRules.maxXp,
              ),
            ),
          ),
        ],
        action: l10n.pathStartLesson,
        onAction: () => context.push(Routes.lessonOf(unit.id, lesson.number)),
      ),
    );
  }

  /// A done lesson's sheet: its first result, Practise again, its streets.
  void _playedLesson(CourseUnit unit, CourseLesson lesson, CourseStop stop) {
    final l10n = context.l10n;
    final total = unit.lessons.length;
    final result = data.firstResults[(unit.id, lesson.number)];
    final perfect = stop.state == StopState.perfect;
    final xp = formatNumber(result?.xp ?? 0);
    final outcome = result == null
        ? data.placed.contains((unit.id, lesson.number))
              ? l10n.pathSheetPlacedBody
              : null
        : perfect
        ? l10n.pathSheetPerfectResult(xp)
        : l10n.pathSheetDoneResult(
            formatNumber(lessonAccuracy(result)),
            xp,
            formatMinSec(context, Duration(milliseconds: result.durationMs)),
          );
    unawaited(
      showStopSheet(
        context,
        kicker: perfect
            ? l10n.pathSheetPerfectKicker(lesson.number, total)
            : l10n.pathSheetDoneKicker(lesson.number, total),
        title: lessonTitle(l10n, lesson, settings),
        body: [?outcome, l10n.pathSheetPractiseBody].join(' '),
        action: l10n.pathPractiseAgain,
        onAction: () => context.push(
          Routes.lessonOf(unit.id, lesson.number, practice: true),
        ),
        secondary: l10n.pathSeeStreets,
        onSecondary: () =>
            context.push(Routes.unitGuideOf(unit.id, lesson: lesson.number)),
      ),
    );
  }
}
