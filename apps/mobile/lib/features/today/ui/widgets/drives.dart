import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/core/toast.dart';
import 'package:pindoro/features/learning/data/drive_history.dart';
import 'package:pindoro/features/learning/ui/drive_labels.dart';
import 'package:pindoro/features/learning/ui/drive_week_card.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Drives on Today (board V32-71, SPEC §16.23 item 122), once there is a drive: the drive
/// waiting to be gone through, the week's goal with what was planned, a nudge when a frequent
/// route can step down a level, and once a week "Pick your two drives".
class TodayDrives extends ConsumerWidget {
  const TodayDrives({super.key, required this.onOpen});

  final Future<void> Function(String route) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final history = ref.watch(driveHistoryProvider).value;
    if (history == null || history.drives.isEmpty) {
      return const SizedBox.shrink();
    }
    final settings = ref.watch(settingsProvider).value;
    final streets = ref.watch(cityStreetsProvider).value ?? const {};
    final places = ref.watch(packRepositoryProvider).value?.landmarks() ?? [];
    final pending = ref.watch(pendingDebriefProvider).value;
    final routes = ref.watch(routeLevelsProvider).value ?? const [];
    final plan = ref.watch(drivePlanProvider);
    final yours = ref.watch(yourRouteItemsProvider).value?.routes.length ?? 0;
    String name(String route) => routeName(
      l10n,
      route,
      places: places,
      streets: streets,
      settings: settings,
    );
    final nudge = routes
        .where((r) => r.suggested.index > r.last.index)
        .firstOrNull;
    final planned = plan.value?.routes ?? const <String>[];
    final note = PindoroType.bodySm.copyWith(color: c.textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: PindoroSpace.s3,
      children: [
        SectionTitle(l10n.todayDrives),
        if (pending != null)
          SuggestionCard(
            glyph: PindoroGlyph.car,
            title: l10n.todayDebriefTitle,
            line: l10n.todayDebriefLine,
            action: l10n.debriefGo,
            onAction: () => unawaited(onOpen(Routes.pastDriveOf(pending))),
          ),
        DriveWeekCard(
          below: [
            if (planned.isNotEmpty)
              Text(
                l10n.todayPlanned(planned.map(name).join(', ')),
                style: note,
              ),
            if (yours > 0) Text(l10n.todayFromDrives(yours), style: note),
          ],
        ),
        if (nudge != null)
          SuggestionCard(
            glyph: PindoroGlyph.compass,
            title: l10n.todayNudge(
              name(nudge.route),
              levelLabel(l10n, nudge.suggested),
            ),
            line: l10n.driveYours(nudge.yours, nudge.turns),
          ),
        if (plan case AsyncData(value: null) when routes.isNotEmpty)
          _PickDrives(routes: routes, name: name),
      ],
    );
  }
}

/// "Pick your two drives" (V32-71): the frequent routes at their suggested level, the first
/// two ticked; planned for the week, or "Not this week".
class _PickDrives extends ConsumerStatefulWidget {
  const _PickDrives({required this.routes, required this.name});

  final List<RouteLevels> routes;
  final String Function(String route) name;

  @override
  ConsumerState<_PickDrives> createState() => _PickDrivesState();
}

class _PickDrivesState extends ConsumerState<_PickDrives> {
  late Set<int> _picked = {
    for (var i = 0; i < widget.routes.length && i < _limit; i++) i,
  };

  int get _limit => widget.routes.length < LearningConfig.weekQuietDrives
      ? widget.routes.length
      : LearningConfig.weekQuietDrives;

  Future<void> _save(List<String> routes) async {
    final week = weekOf(ref.read(clockProvider)());
    await ref
        .read(settingsDaoProvider)
        .setDrivePlan(encodeDrivePlan((week: week, routes: routes)));
    ref.invalidate(drivePlanProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final routes = widget.routes;
    final left = _limit - _picked.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: PindoroSpace.s3,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.todayPickTitle,
            style: PindoroType.titleMd.copyWith(color: c.textPrimary),
          ),
        ),
        Text(
          l10n.todayPickLine,
          style: PindoroType.bodySm.copyWith(color: c.textSecondary),
        ),
        PlanChecklist(
          items: [
            for (final r in routes)
              (
                title: l10n.todayPickRoute(
                  widget.name(r.route),
                  levelLabel(l10n, r.suggested),
                ),
                subtitle: l10n.driveYours(r.yours, r.turns),
              ),
          ],
          picked: _picked,
          limit: _limit,
          onChanged: (picked) => setState(() => _picked = picked),
          onLimit: () => showToast(context, l10n.todayPickLimit),
        ),
        PindoroButton(
          label: left > 0
              ? l10n.todayPickMore(left)
              : l10n.todayPickPlan(formatNumber(_picked.length)),
          onPressed: left > 0
              ? null
              : () => unawaited(
                  _save([
                    for (final i in _picked.toList()..sort()) routes[i].route,
                  ]),
                ),
        ),
        PindoroButton(
          label: l10n.todayPickSkip,
          variant: PindoroButtonVariant.tertiary,
          onPressed: () => unawaited(_save(const [])),
        ),
      ],
    );
  }
}
