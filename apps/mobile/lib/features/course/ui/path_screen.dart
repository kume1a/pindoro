import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/course/data/course_data.dart';
import 'package:pindoro/features/course/ui/path_sheets.dart';
import 'package:pindoro/features/course/ui/path_stops.dart';
import 'package:pindoro/features/course/ui/widgets/path_states.dart';
import 'package:pindoro/features/course/ui/widgets/path_unit.dart';
import 'package:pindoro/features/course/ui/widgets/path_unlock.dart';
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

class _PathScreenState extends ConsumerState<PathScreen>
    with SingleTickerProviderStateMixin {
  final _currentKey = GlobalKey();
  bool _shownCurrent = false;
  late final UnlockPlayer _unlock = UnlockPlayer(
    vsync: this,
    onUnitFlip: () => ref.read(feedbackProvider).unitDone(),
    onPaved: ({required unitOpens}) {
      if (!unitOpens) ref.read(feedbackProvider).unlock();
      _toCurrent(animate: true);
    },
    onFrame: () => setState(() {}),
  );

  @override
  void dispose() {
    _unlock.dispose();
    super.dispose();
  }

  /// Plays the unlock from the stop Lesson complete just finished, once the
  /// Path shows and the course has the result.
  void _startUnlock(CourseData data) {
    final finished = ref.read(pathUnlockProvider.notifier).take();
    final next = data.units.current;
    if (finished == null || next == null || !mounted) return;
    final u = data.units.indexWhere((p) => p.unit.id == finished.unitId);
    final done = u < 0
        ? -1
        : data.units[u].stops.indexWhere(
            (s) =>
                s.kind == finished.kind &&
                s.lesson == finished.lesson &&
                s.done,
          );
    if (done < 0 || MediaQuery.disableAnimationsOf(context)) {
      return _toCurrent(animate: false);
    }
    _unlock.play((
      unit: u,
      done: done,
      next: next,
      unitOpens: finished.kind == StopKind.finalDrive && next.unit != u,
    ));
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
    // The unlock waits until this tab shows (offstage tabs have no tickers).
    if (ref.watch(pathUnlockProvider) != null &&
        data != null &&
        TickerMode.valuesOf(context).enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startUnlock(data));
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PlayTopBar(city: city, xp: XpPill(xp)),
            Expanded(
              child: course.hasValue
                  ? data == null
                        ? const PathNoDistricts()
                        : _path(data)
                  : course.hasError
                  ? PathLoadError(
                      onRetry: () => ref.invalidate(coursePlanProvider),
                    )
                  : PathLoading(
                      city: context.localName(ka: city.nameKa, en: city.nameEn),
                    ),
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
    final coach =
        data.fresh &&
            current == (unit: 0, stop: 0) &&
            !ref.watch(pathCoachProvider)
        ? _startHere(l10n, data.units.first.unit, settings)
        : null;
    return Listener(
      onPointerDown: coach == null
          ? null
          : (_) => ref.read(pathCoachProvider.notifier).hide(),
      child: _units(data, current, coach, settings, c),
    );
  }

  /// A new course's coach mark on its first lesson (canvas R4-10, new city
  /// and new player).
  ({int stop, LockedNote note}) _startHere(
    AppLocalizations l10n,
    CourseUnit unit,
    Settings? settings,
  ) => (
    stop: 0,
    note: (
      title: l10n.pathCoachTitle,
      body: l10n.pathCoachBody(
        unit.lessons.first.streets.length,
        districtName(unit.district, settings),
      ),
    ),
  );

  Widget _units(
    CourseData data,
    ({int unit, int stop})? current,
    ({int stop, LockedNote note})? coach,
    Settings? settings,
    PindoroColors c,
  ) {
    final l10n = context.l10n;
    final sheets = PathSheets(context, ref, data, settings);
    return CustomScrollView(
      primary: true,
      // Every unit is built, so the current stop has a context to scroll to
      // even when placement puts it many units down.
      // ponytail: fine for a city's ~10 units; jump to an estimated offset
      // first if a city ever has many more.
      scrollCacheExtent: const ScrollCacheExtent.pixels(_wholeCourse),
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
                    child: _unlock.signpost(
                      u,
                      progress.open,
                      (locked) => _signpost(
                        progress,
                        settings,
                        locked: locked,
                        onLockedTap: () => sheets.lockedUnit(
                          u,
                          onKeepGoing: () => _toCurrent(animate: true),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: ContentColumn(
                  child: PathUnit(
                    stops: _unlock.stops(u, [
                      for (final (i, stop) in progress.stops.indexed)
                        if (stopView(l10n, data, progress, stop, settings)
                            case final view)
                          // The coach mark speaks for its stop's tip.
                          u == 0 && i == coach?.stop
                              ? view.copyWith(tip: () => null)
                              : view,
                    ]),
                    coach: u == 0 ? coach : null,
                    driven: _unlock.driven(u, drivenOf(progress)),
                    scaleOf: (i) => _unlock.scale(u, i) ?? 1,
                    burst: _unlock.burst(u),
                    roadOpacity: _unlock.roadOpacity(u, progress),
                    stopKeys: {
                      if (current?.unit == u) current!.stop: _currentKey,
                    },
                    lockedNote: (i) =>
                        lockedNote(l10n, data.units, u, i, settings),
                    onStop: (i) => sheets.stop(u, i),
                  ),
                ),
              ),
            ],
          ),
        const SliverToBoxAdapter(child: SizedBox(height: PindoroSpace.s6)),
      ],
    );
  }

  Widget _signpost(
    UnitProgress progress,
    Settings? settings, {
    required bool locked,
    required VoidCallback onLockedTap,
  }) {
    final l10n = context.l10n;
    final unit = progress.unit;
    final district = districtName(unit.district, settings);
    final total = unit.lessons.length;
    return Signpost(
      number: unit.number,
      line: !locked
          ? l10n.pathUnitLine(progress.lessonsDone, total)
          : l10n.pathUnitLocked,
      title: district,
      locked: locked,
      semanticLabel: !locked
          ? l10n.a11ySignpost(
              unit.number,
              district,
              progress.lessonsDone,
              total,
            )
          : l10n.a11ySignpostLocked(unit.number, district),
      onTap: progress.open ? null : onLockedTap,
      onGuide: progress.open
          ? () {
              ref.read(feedbackProvider).tap();
              unawaited(context.push(Routes.unitGuideOf(unit.id)));
            }
          : null,
      guideLabel: l10n.pathUnitGuide,
    );
  }
}

/// Far enough past the viewport to build a whole course.
const double _wholeCourse = 100000;
