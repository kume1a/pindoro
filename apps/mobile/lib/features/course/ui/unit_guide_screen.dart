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
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// A unit at a glance (canvas R4-13): its signpost, a map of its streets with
/// a tip, and its stops. A done lesson's row shows just its streets on the
/// map; the next stop's row starts it. [lesson] opens with that lesson shown.
class UnitGuideScreen extends ConsumerStatefulWidget {
  const UnitGuideScreen({super.key, required this.unitId, this.lesson});

  final String unitId;
  final int? lesson;

  @override
  ConsumerState<UnitGuideScreen> createState() => _UnitGuideScreenState();
}

class _UnitGuideScreenState extends ConsumerState<UnitGuideScreen> {
  late int? _selected = widget.lesson;
  final GlobalKey _selectedRow = GlobalKey();
  bool _scrolled = false;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(courseProvider).value;
    final settings = ref.watch(settingsProvider).value;
    if (data == null) return const Scaffold();
    final u = data.units.indexWhere((p) => p.unit.id == widget.unitId);
    final area = u < 0
        ? null
        : DistrictsArea({widget.unitId}).shapeIn(data.plan.pack);
    if (area == null || !data.units[u].open) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(Routes.path);
      });
      return const Scaffold();
    }
    _scrollToSelected();
    final l10n = context.l10n;
    final progress = data.units[u];
    final unit = progress.unit;
    final district = districtName(unit.district, settings);
    final shown = _selected == null
        ? unit.streets
        : unit.lessons[_selected! - 1].streets;
    return PageScaffold(
      title: l10n.unitGuideTitle,
      children: [
        Signpost(
          number: unit.number,
          line: l10n.pathUnitLine(progress.lessonsDone, unit.lessons.length),
          title: district,
          semanticLabel: l10n.a11ySignpost(
            unit.number,
            district,
            progress.lessonsDone,
            unit.lessons.length,
          ),
        ),
        _MapCard(
          area: area,
          streets: shown,
          framed: _selected != null,
          mapLabel: l10n.unitGuideMap(district),
          tip: l10n.unitGuideTip(_axisKey(mainAxis(unit.streets)), district),
        ),
        SectionTitle(l10n.unitGuideLessons),
        ListGroup(
          children: [
            for (final stop in progress.stops)
              _row(context, data, progress, stop, settings),
          ],
        ),
      ],
    );
  }

  /// Brings the lesson the guide opened at into view, once.
  void _scrollToSelected() {
    if (_scrolled || _selected == null) return;
    _scrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _selectedRow.currentContext;
      if (row != null && row.mounted) {
        unawaited(Scrollable.ensureVisible(row, alignment: 0.5));
      }
    });
  }

  Widget _row(
    BuildContext context,
    CourseData data,
    UnitProgress progress,
    CourseStop stop,
    Settings? settings,
  ) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final unit = progress.unit;
    final locked = RowTile(
      switch (stop.kind) {
        StopKind.lesson => PindoroGlyph.lock,
        StopKind.pitStop => PindoroGlyph.wrench,
        StopKind.finalDrive => PindoroGlyph.trophy,
      },
      face: c.pathNodeLockedFill,
      ink: c.pathNodeLockedIcon,
    );
    RowTile next(PindoroGlyph glyph) => RowTile(
      glyph,
      face: c.primaryBase,
      ink: c.primaryOn,
      lip: c.primaryLip,
    );
    RowTile perfect(PindoroGlyph glyph) => RowTile(
      glyph,
      face: c.feedbackPerfectFill,
      ink: c.feedbackPerfectOn,
      lip: c.feedbackPerfectLip,
    );
    const chevron = PindoroIcon(PindoroGlyph.chevronRight);
    void open(String route) {
      ref.read(feedbackProvider).tap();
      unawaited(context.push(route));
    }

    // Every row is its own node: a row without a label would merge into the
    // group, and screen readers would get one button for the whole list.
    /// [opens] another screen (a chevron) rather than selecting the row.
    ListRow row(
      String title,
      String subtitle,
      Widget leading, {
      VoidCallback? onTap,
      bool opens = false,
      bool selected = false,
      Key? key,
    }) => ListRow(
      key: key,
      title: title,
      subtitle: subtitle,
      semanticsLabel: [
        title,
        subtitle,
        if (selected) l10n.unitGuideOnMap,
      ].join('. '),
      leading: leading,
      trailing: selected
          ? PindoroIcon(PindoroGlyph.map, color: c.primaryText)
          : opens
          ? chevron
          : null,
      onTap: onTap,
    );

    switch (stop.kind) {
      case StopKind.pitStop:
        final title = l10n.unitGuidePitStop;
        return switch (stop.state) {
          StopState.locked => row(
            title,
            l10n.unitGuideOpensAfter(unit.pitStopAfter),
            locked,
          ),
          StopState.current => row(
            title,
            l10n.unitGuideTuneUp(data.pitStops[unit.id]?.length ?? 0),
            RowTile(
              PindoroGlyph.wrench,
              face: c.pathNodeReviewFill,
              ink: c.pathNodeReviewIcon,
              lip: c.pathNodeReviewLip,
            ),
            onTap: () => open(Routes.unitPitStop(unit.id)),
            opens: true,
          ),
          _ => row(
            title,
            l10n.unitGuideStopDone,
            const RowTile(PindoroGlyph.check),
          ),
        };
      case StopKind.finalDrive:
        final title = l10n.unitGuideFinalDrive;
        return switch (stop.state) {
          StopState.locked => row(
            title,
            l10n.unitGuideOpensAfter(unit.lessons.length),
            locked,
          ),
          StopState.current => row(
            title,
            l10n.unitGuideTrips(
              progress.tripsPassed,
              CourseRules.finalDriveTrips,
            ),
            next(PindoroGlyph.trophy),
            onTap: () => open(Routes.driveOf(unit.id)),
            opens: true,
          ),
          _ => row(title, l10n.unitGuidePassed, perfect(PindoroGlyph.trophy)),
        };
      case StopKind.lesson:
        final lesson = unit.lessons[stop.lesson! - 1];
        final title = l10n.unitGuideLessonTitle(
          lesson.number,
          lessonTitle(l10n, lesson, settings),
        );
        final count = lesson.streets.length;
        final result = data.firstResults[(unit.id, lesson.number)];
        final selected = _selected == lesson.number;
        void select() {
          ref.read(feedbackProvider).tap();
          setState(() => _selected = selected ? null : lesson.number);
        }

        return switch (stop.state) {
          StopState.current => row(
            title,
            l10n.unitGuideNext(
              lesson.streets.map((s) => streetName(s, settings)).join(', '),
            ),
            next(PindoroGlyph.play),
            onTap: () => open(Routes.lessonOf(unit.id, lesson.number)),
            opens: true,
          ),
          StopState.locked => row(title, l10n.unitGuideLocked, locked),
          StopState.perfect => row(
            title,
            l10n.unitGuidePerfect(count),
            perfect(PindoroGlyph.star),
            onTap: select,
            selected: selected,
            key: selected ? _selectedRow : null,
          ),
          StopState.done => row(
            title,
            result == null
                ? l10n.unitGuidePlaced(count)
                : l10n.unitGuideDone(
                    formatNumber(lessonAccuracy(result)),
                    count,
                  ),
            const RowTile(PindoroGlyph.check),
            onTap: select,
            selected: selected,
            key: selected ? _selectedRow : null,
          ),
        };
    }
  }
}

/// The map of the unit's [streets] in yellow, framed on them when [framed]
/// (else on the district), and Pindo with the [tip] under it.
class _MapCard extends ConsumerWidget {
  const _MapCard({
    required this.area,
    required this.streets,
    required this.framed,
    required this.mapLabel,
    required this.tip,
  });

  final AreaShape area;
  final List<NamedStreet> streets;
  final bool framed;
  final String mapLabel;
  final String tip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PindoroTheme.of(context).colors;
    final lines = [for (final s in streets) ...s.geometry];
    return LipBox(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PindoroRadius.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: mapLabel,
              image: true,
              child: SizedBox(
                height: 176,
                child: ref.watch(pindoroMapBuilderProvider)(
                  PindoroMap(
                    area: area,
                    truth: lines,
                    showControls: false,
                    ownsGestures: true,
                    frame: framed ? [for (final l in lines) ...l] : null,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: PindoroSpace.s4,
                vertical: PindoroSpace.s3,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: PindoroSpace.s3,
                children: [
                  const Pindo(PindoExpression.happy, height: 51),
                  Expanded(
                    child: Text(
                      tip,
                      style: PindoroType.bodySm.copyWith(color: c.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The tip's `axis` select key.
String _axisKey(StreetAxis? axis) => switch (axis) {
  StreetAxis.northSouth => 'ns',
  StreetAxis.northeastSouthwest => 'nesw',
  StreetAxis.eastWest => 'ew',
  StreetAxis.northwestSoutheast => 'nwse',
  null => 'none',
};
