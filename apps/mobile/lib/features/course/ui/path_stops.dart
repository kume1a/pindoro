import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/features/course/data/course_data.dart';
import 'package:pindoro/features/course/ui/lesson_title.dart';
import 'package:pindoro/features/course/ui/widgets/path_unit.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// How [stop] draws and reads on the Path.
StopView stopView(
  AppLocalizations l10n,
  CourseData data,
  UnitProgress progress,
  CourseStop stop,
  Settings? settings,
) {
  final current = stop.state == StopState.current;
  final stateLabel = switch (stop.state) {
    StopState.current => l10n.a11yStopCurrent,
    StopState.done when stop.kind == StopKind.pitStop =>
      l10n.a11yStopPitStopDone,
    StopState.done => l10n.a11yStopDone,
    StopState.perfect => l10n.a11yStopPerfect,
    StopState.locked => l10n.a11yStopLocked,
  };
  switch (stop.kind) {
    case StopKind.lesson:
      final lesson = progress.unit.lessons[stop.lesson! - 1];
      return (
        look: lookOf(stop.state),
        glyph: switch (stop.state) {
          StopState.done => PindoroGlyph.check,
          StopState.perfect => PindoroGlyph.star,
          StopState.current => PindoroGlyph.play,
          StopState.locked => PindoroGlyph.lock,
        },
        big: current,
        ring: current ? 0 : null,
        tip: current ? l10n.pathTipStart : null,
        label:
            '${l10n.a11yStopLesson(lesson.number, lessonTitle(l10n, lesson, settings))} '
            '$stateLabel',
      );
    case StopKind.pitStop:
      final count = data.pitStops[progress.unit.id]?.length ?? 0;
      return (
        look: stop.state == StopState.locked
            ? PathStopLook.locked
            : PathStopLook.review,
        glyph: PindoroGlyph.wrench,
        big: current,
        ring: current ? 0 : null,
        tip: current ? l10n.pathTipTuneUp : null,
        label: '${l10n.a11yStopPitStop(current ? count : 0)} $stateLabel',
      );
    case StopKind.finalDrive:
      return (
        look: lookOf(stop.state),
        glyph: PindoroGlyph.trophy,
        big: true,
        ring: current
            ? progress.tripsPassed / CourseRules.finalDriveTrips
            : null,
        tip: current ? l10n.pathTipFinalDrive : null,
        label: [
          l10n.a11yStopFinalDrive,
          if (stop.done) l10n.a11yStopPassed else stateLabel,
          if (current) l10n.a11yStopFinalDriveTrips(progress.tripsPassed),
        ].join(' '),
      );
  }
}

PathStopLook lookOf(StopState state) => switch (state) {
  StopState.done => PathStopLook.done,
  StopState.perfect => PathStopLook.perfect,
  StopState.current => PathStopLook.current,
  StopState.locked => PathStopLook.locked,
};

/// What stop [i] of unit [u] in [units] says when tapped instead of opening
/// a sheet; null when it opens one.
LockedNote? lockedNote(
  AppLocalizations l10n,
  List<UnitProgress> units,
  int u,
  int i,
  Settings? settings,
) {
  final progress = units[u];
  final stop = progress.stops[i];
  if (stop.kind == StopKind.finalDrive && stop.done) {
    return (title: l10n.pathFinalDriveDone, body: null);
  }
  if (stop.kind == StopKind.pitStop && stop.done) {
    return (title: l10n.pathPitStopDone, body: null);
  }
  if (stop.state != StopState.locked) return null;
  if (!progress.open) {
    return (
      title: l10n.pathLockedUnit(progress.unit.number),
      body: u == 0
          ? null
          : l10n.pathFinishUnit(
              districtName(units[u - 1].unit.district, settings),
            ),
    );
  }
  // Placement can mark a later lesson done first: the stop to finish is the
  // current one, not always the one just before.
  final blocker =
      progress.stops.where((s) => s.state == StopState.current).firstOrNull ??
      progress.stops[i - 1];
  return (
    title: switch (stop.kind) {
      StopKind.pitStop => l10n.pathLockedPitStop,
      StopKind.finalDrive => l10n.pathLockedFinalDrive,
      StopKind.lesson => l10n.pathLockedLesson(stop.lesson!),
    },
    body: blocker.kind == StopKind.pitStop
        ? l10n.pathFinishPitStop
        : l10n.pathFinishLesson(blocker.lesson!),
  );
}

/// The asphalt reaches the last stop that is done or current (in road
/// points: stop k is point k + 1).
double drivenOf(UnitProgress progress) =>
    1.0 +
    progress.stops.lastIndexWhere(
      (s) => s.done || s.state == StopState.current,
    );

/// The road while the unlock paves it, [t] from 0 to 1: from the finished
/// stop [done] to the one that opens, [next]. Asphalt already [driven]
/// further (a later lesson placed) stays where it is.
double pavedTo({
  required int done,
  required int next,
  required double driven,
  required double t,
}) {
  final from = done + 1.0, to = next + 1.0;
  return driven > to ? driven : from + (to - from) * t;
}
