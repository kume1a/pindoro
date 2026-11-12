import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/course/data/course_data.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro/features/setup/ui/widgets/whats_new_road.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// What's new (canvas R4-50), once for a player who played Free play before
/// the course existed; then placement from the streets they already know.
/// Leaving it opens the Path, whose course then starts unplaced.
class WhatsNewScreen extends ConsumerStatefulWidget {
  const WhatsNewScreen({super.key});

  @override
  ConsumerState<WhatsNewScreen> createState() => _WhatsNewScreenState();
}

class _WhatsNewScreenState extends ConsumerState<WhatsNewScreen> {
  /// The placement to offer; null shows the intro.
  Placement? _placement;
  bool _busy = false;

  Future<void> _showPath() async {
    ref.read(feedbackProvider).tap();
    setState(() => _busy = true);
    // Listening keeps the auto-disposed provider alive while it loads.
    final sub = ref.listenManual(placementProvider, (_, _) {});
    Placement? p;
    try {
      p = await ref.read(placementProvider.future);
    } on Object {
      p = null;
    } finally {
      sub.close();
    }
    if (!mounted) return;
    if (p == null || p.placed.isEmpty) return context.go(Routes.path);
    // Checks only in later, locked units leave lesson 1 current: nothing to
    // choose, so the placement is just saved.
    if (p.units.current == (unit: 0, stop: 0)) return _place(p);
    setState(() {
      _busy = false;
      _placement = p;
    });
  }

  /// Saves [p] and opens the Path, then [lesson] of the current unit.
  Future<void> _place(Placement p, {int? lesson}) async {
    setState(() => _busy = true);
    await ref.read(progressDaoProvider).place(p.plan.pack.city().id, p.placed);
    if (!mounted) return;
    final router = GoRouter.of(context)..go(Routes.path);
    final current = p.units.current;
    if (lesson != null && current != null) {
      unawaited(
        router.push(Routes.lessonOf(p.units[current.unit].unit.id, lesson)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final placement = _placement;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _busy) return;
        if (_placement != null) {
          setState(() => _placement = null);
        } else {
          context.go(Routes.path);
        }
      },
      child: placement == null ? _intro(context) : _placed(context, placement),
    );
  }

  String _cityName(BuildContext context) =>
      switch (ref.watch(packRepositoryProvider).value?.city()) {
        final city? => context.localName(ka: city.nameKa, en: city.nameEn),
        null => '',
      };

  Widget _intro(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    return PageScaffold(
      footer: PindoroButton(
        label: l10n.whatsNewShowPath,
        onPressed: _busy ? null : _showPath,
      ),
      children: [
        const _Top(WhatsNewRoad()),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: LipBox(
            face: c.primarySoft,
            radius: PindoroRadius.full,
            padding: const EdgeInsets.symmetric(
              horizontal: PindoroSpace.s3,
              vertical: PindoroSpace.s1,
            ),
            child: Text(
              l10n.whatsNewChip,
              style: PindoroType.labelMd.copyWith(color: c.primaryText),
            ),
          ),
        ),
        _Headline(l10n.whatsNewTitle(_cityName(context))),
        Text(
          l10n.whatsNewBody,
          style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
        ),
        ListGroup(
          children: [
            ListRow(
              leading: const RowTile(PindoroGlyph.road),
              title: l10n.whatsNewLessons,
              subtitle: l10n.whatsNewLessonsLine,
            ),
            ListRow(
              leading: const RowTile(PindoroGlyph.car),
              title: l10n.whatsNewTrips,
              subtitle: l10n.whatsNewTripsLine,
            ),
            ListRow(
              leading: const RowTile(PindoroGlyph.map),
              title: l10n.whatsNewFreePlay,
              subtitle: l10n.whatsNewFreePlayLine,
            ),
          ],
        ),
      ],
    );
  }

  Widget _placed(BuildContext context, Placement p) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final units = p.units;
    final current = units.current;
    String unitTitle(UnitProgress u) => l10n.placementUnit(
      u.unit.number,
      districtName(u.unit.district, settings),
    );
    ListRow complete(UnitProgress u) => ListRow(
      leading: const RowTile(PindoroGlyph.check),
      title: unitTitle(u),
      subtitle: l10n.placementComplete(
        u.unit.streets.where((s) => p.known.contains(s.id)).length,
        u.unit.streets.length,
      ),
    );
    final here = current == null ? null : units[current.unit];
    final stop = current == null ? null : here!.stops[current.stop];
    final lesson = stop?.kind == StopKind.lesson ? stop!.lesson : null;
    final next = current == null
        ? null
        : units.elementAtOrNull(current.unit + 1);
    return PageScaffold(
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s2,
        children: [
          if (here != null)
            PindoroButton(
              label: l10n.placementFromUnit1,
              variant: PindoroButtonVariant.tertiary,
              onPressed: _busy ? null : () => context.go(Routes.path),
            ),
          PindoroButton(
            label: lesson == null
                ? l10n.whatsNewShowPath
                : l10n.placementStartLesson(lesson),
            onPressed: _busy ? null : () => _place(p, lesson: lesson),
          ),
        ],
      ),
      children: [
        const _Top(Center(child: Pindo(PindoExpression.proud, height: 104))),
        _Headline(
          here == null
              ? l10n.placementAllTitle
              : l10n.placementTitle(here.unit.number),
          center: true,
        ),
        Text(
          l10n.placementBody(formatNumber(p.known.length), _cityName(context)),
          textAlign: TextAlign.center,
          style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
        ),
        ListGroup(
          children: [
            if (here == null)
              complete(units.last)
            else ...[
              if (current!.unit > 0) complete(units[current.unit - 1]),
              ListRow(
                leading: RowTile(
                  PindoroGlyph.play,
                  face: c.primaryBase,
                  ink: c.primaryOn,
                  lip: c.primaryLip,
                ),
                title: unitTitle(here),
                subtitle: lesson == null
                    ? null
                    : l10n.placementCurrent(
                        here.lessonsDone,
                        here.unit.lessons.length,
                        lesson,
                      ),
              ),
              if (next != null)
                ListRow(
                  leading: RowTile(
                    PindoroGlyph.lock,
                    face: c.pathNodeLockedFill,
                    ink: c.pathNodeLockedIcon,
                  ),
                  title: unitTitle(next),
                  subtitle: l10n.placementOpensAfter(
                    districtName(here.unit.district, settings),
                  ),
                ),
            ],
          ],
        ),
      ],
    );
  }
}

/// The first child, a little lower: these pages have no title row.
class _Top extends StatelessWidget {
  const _Top(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: PindoroSpace.s2),
    child: child,
  );
}

class _Headline extends StatelessWidget {
  const _Headline(this.text, {this.center = false});

  final String text;
  final bool center;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: PindoroType.headlineLg.copyWith(
        color: PindoroTheme.of(context).colors.textPrimary,
      ),
    ),
  );
}
