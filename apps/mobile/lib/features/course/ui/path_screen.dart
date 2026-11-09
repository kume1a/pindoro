import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/course/data/course_data.dart';
import 'package:pindoro/features/course/ui/lesson_title.dart';
import 'package:pindoro/features/course/ui/widgets/path_unit.dart';
import 'package:pindoro/features/course/ui/widgets/stop_sheet.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/pack/ui/pack_pending.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro/features/progress/ui/play_top_bar.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The course (canvas R4-10 to R4-12): a signpost per unit, the road and its
/// stops; a tap opens a stop's sheet, a locked stop says what opens it. It
/// opens scrolled to the current stop, and a tap on the open Path tab
/// scrolls back to it.
class PathScreen extends ConsumerStatefulWidget {
  const PathScreen({super.key});

  @override
  ConsumerState<PathScreen> createState() => _PathScreenState();
}

class _PathScreenState extends ConsumerState<PathScreen> {
  final _currentKey = GlobalKey();
  final Map<String, ValueNotifier<LockedNote?>> _signNotes = {};
  bool _shownCurrent = false;

  @override
  void dispose() {
    for (final n in _signNotes.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _toCurrent({required bool animate}) {
    final target = _currentKey.currentContext;
    if (target == null) return;
    final calm = MediaQuery.disableAnimationsOf(context);
    unawaited(
      Scrollable.ensureVisible(
        target,
        alignment: 0.35,
        duration: animate && !calm ? PindoroMotion.durationBase : Duration.zero,
        curve: PindoroMotion.easeDecelerate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pack = ref.watch(packRepositoryProvider);
    final city = pack.value?.city();
    if (city == null) return PackPending(pack: pack);
    ref.listen(pathRetapProvider, (_, _) => _toCurrent(animate: true));
    final course = ref.watch(courseProvider);
    final xp = ref.watch(totalXpProvider).value ?? 0;
    final data = course.value;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PlayTopBar(city: city, xp: XpPill(xp)),
            Expanded(
              child: course.hasValue
                  ? data == null
                        ? const _NoDistricts()
                        : _path(data)
                  : course.hasError
                  ? _LoadError(
                      onRetry: () => ref.invalidate(coursePlanProvider),
                    )
                  : const _Loading(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _path(CourseData data) {
    if (!_shownCurrent) {
      _shownCurrent = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _toCurrent(animate: false),
      );
    }
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final c = PindoroTheme.of(context).colors;
    final current = data.units.current;
    return CustomScrollView(
      primary: true,
      slivers: [
        for (final (u, progress) in data.units.indexed)
          SliverMainAxisGroup(
            slivers: [
              PinnedHeaderSliver(
                child: Container(
                  color: c.surfaceBase,
                  padding: const EdgeInsets.fromLTRB(
                    PindoroSpace.s4,
                    PindoroSpace.s3,
                    PindoroSpace.s4,
                    PindoroSpace.s2,
                  ),
                  child: ContentColumn(
                    child: _signpost(data, u, progress, settings),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: ContentColumn(
                  child: PathUnit(
                    stops: [
                      for (final (i, stop) in progress.stops.indexed)
                        _view(l10n, data, progress, i, stop, settings),
                    ],
                    driven: _driven(progress),
                    dim: !progress.open,
                    stopKeys: {
                      if (current?.unit == u) current!.stop: _currentKey,
                    },
                    lockedNote: (i) => _lockedNote(l10n, data, u, i, settings),
                    onStop: (i) => _openStop(data, progress, i, settings),
                    bubbleAtTop: _signNotes.putIfAbsent(
                      progress.unit.id,
                      () => ValueNotifier(null),
                    ),
                  ),
                ),
              ),
            ],
          ),
        const SliverToBoxAdapter(child: SizedBox(height: PindoroSpace.s6)),
      ],
    );
  }

  /// The asphalt reaches the last stop that is done or current.
  static double _driven(UnitProgress progress) =>
      1.0 +
      progress.stops.lastIndexWhere(
        (s) => s.done || s.state == StopState.current,
      );

  Widget _signpost(
    CourseData data,
    int u,
    UnitProgress progress,
    Settings? settings,
  ) {
    final l10n = context.l10n;
    final unit = progress.unit;
    final district = districtName(unit.district, settings);
    final total = unit.lessons.length;
    return Signpost(
      number: unit.number,
      line: progress.open
          ? l10n.pathUnitLine(progress.lessonsDone, total)
          : l10n.pathUnitLocked,
      title: district,
      locked: !progress.open,
      semanticLabel: progress.open
          ? l10n.a11ySignpost(
              unit.number,
              district,
              progress.lessonsDone,
              total,
            )
          : l10n.a11ySignpostLocked(unit.number, district),
      onTap: progress.open
          ? null
          : () {
              ref.read(feedbackProvider).tap();
              _signNotes[unit.id]?.value = null;
              _signNotes[unit.id]?.value = _unitLockedNote(
                l10n,
                data,
                u,
                settings,
              );
            },
    );
  }

  LockedNote _unitLockedNote(
    AppLocalizations l10n,
    CourseData data,
    int u,
    Settings? settings,
  ) => (
    title: l10n.pathLockedUnit(data.units[u].unit.number),
    body: u == 0
        ? null
        : l10n.pathFinishUnit(
            districtName(data.units[u - 1].unit.district, settings),
          ),
  );

  StopView _view(
    AppLocalizations l10n,
    CourseData data,
    UnitProgress progress,
    int i,
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
          look: switch (stop.state) {
            StopState.done => PathStopLook.done,
            StopState.perfect => PathStopLook.perfect,
            StopState.current => PathStopLook.current,
            StopState.locked => PathStopLook.locked,
          },
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
          look: PathStopLook.locked,
          glyph: PindoroGlyph.trophy,
          big: true,
          ring: null,
          tip: null,
          label:
              '${l10n.a11yStopFinalDrive} ${l10n.a11yStopLocked} '
              '${l10n.pathFinalDriveSoon}',
        );
    }
  }

  LockedNote? _lockedNote(
    AppLocalizations l10n,
    CourseData data,
    int u,
    int i,
    Settings? settings,
  ) {
    final progress = data.units[u];
    final stop = progress.stops[i];
    if (stop.kind == StopKind.finalDrive) {
      return (
        title: l10n.pathFinalDriveSoon,
        body: l10n.pathFinalDriveSoonBody,
      );
    }
    if (stop.kind == StopKind.pitStop && stop.done) {
      return (title: l10n.pathPitStopDone, body: null);
    }
    if (stop.state != StopState.locked) return null;
    if (!progress.open) return _unitLockedNote(l10n, data, u, settings);
    final before = progress.stops[i - 1];
    final title = stop.kind == StopKind.pitStop
        ? l10n.pathLockedPitStop
        : l10n.pathLockedLesson(stop.lesson!);
    return (
      title: title,
      body: before.kind == StopKind.pitStop
          ? l10n.pathFinishPitStop
          : l10n.pathFinishLesson(before.lesson!),
    );
  }

  void _openStop(
    CourseData data,
    UnitProgress progress,
    int i,
    Settings? settings,
  ) {
    ref.read(feedbackProvider).tap();
    final l10n = context.l10n;
    final unit = progress.unit;
    final stop = progress.stops[i];
    final district = districtName(unit.district, settings);
    final total = unit.lessons.length;
    if (stop.kind == StopKind.pitStop) {
      final count = data.pitStops[unit.id]?.length ?? 0;
      unawaited(
        showStopSheet(
          context,
          kicker: l10n.pathSheetPitKicker(unit.number, district),
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
      return;
    }
    final lesson = unit.lessons[stop.lesson! - 1];
    final title = lessonTitle(l10n, lesson, settings);
    if (stop.state == StopState.current) {
      unawaited(
        showStopSheet(
          context,
          kicker: l10n.pathSheetLessonKicker(
            lesson.number,
            total,
            unit.number,
            district,
          ),
          title: title,
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
              label: l10n.pathChipUpToXp(formatNumber(LessonRules.maxXp)),
            ),
          ],
          action: l10n.pathStartLesson,
          onAction: () => context.push(Routes.lessonOf(unit.id, lesson.number)),
        ),
      );
      return;
    }
    final result = data.firstResults[(unit.id, lesson.number)];
    final perfect = stop.state == StopState.perfect;
    final xp = formatNumber(result?.xp ?? 0);
    final outcome = result == null
        ? null
        : perfect
        ? l10n.pathSheetPerfectResult(xp)
        : l10n.pathSheetDoneResult(
            formatNumber(_accuracy(result)),
            xp,
            formatMinSec(context, Duration(milliseconds: result.durationMs)),
          );
    unawaited(
      showStopSheet(
        context,
        kicker: perfect
            ? l10n.pathSheetPerfectKicker(lesson.number, total)
            : l10n.pathSheetDoneKicker(lesson.number, total),
        title: title,
        body: [?outcome, l10n.pathSheetPractiseBody].join(' '),
        action: l10n.pathPractiseAgain,
        onAction: () => context.push(
          Routes.lessonOf(unit.id, lesson.number, practice: true),
        ),
      ),
    );
  }
}

/// Tests right first time, in percent.
int _accuracy(LessonResult r) =>
    r.tests == 0 ? 0 : (r.rightFirst * 100 / r.tests).round();

/// Nothing for 300 ms, then thinking Pindo and the lane loader.
class _Loading extends StatefulWidget {
  const _Loading();

  @override
  State<_Loading> createState() => _LoadingState();
}

class _LoadingState extends State<_Loading> {
  bool _show = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_show
      ? const SizedBox.expand()
      : const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: PindoroSpace.s4,
            children: [
              Pindo(PindoExpression.thinking, height: 96),
              SizedBox(width: 160, child: LaneLoader()),
            ],
          ),
        );
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.actions});

  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(PindoroSpace.s4),
        child: ContentColumn(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: PindoroSpace.s4,
            children: [
              const Pindo(PindoExpression.encouraging, height: 96),
              Text(
                text,
                textAlign: TextAlign.center,
                style: PindoroType.titleMd.copyWith(color: c.textPrimary),
              ),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Message(
      text: l10n.pathLoadError,
      actions: [
        PindoroButton(label: l10n.commonTryAgain, onPressed: onRetry),
        PindoroButton(
          label: l10n.pathOpenFreePlay,
          variant: PindoroButtonVariant.tertiary,
          onPressed: () => context.go(Routes.home),
        ),
      ],
    );
  }
}

class _NoDistricts extends StatelessWidget {
  const _NoDistricts();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Message(
      text: l10n.pathNoDistricts,
      actions: [
        PindoroButton(
          label: l10n.pathOpenFreePlay,
          onPressed: () => context.go(Routes.home),
        ),
      ],
    );
  }
}
