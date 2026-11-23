import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/drive/ui/debrief_screen.dart';
import 'package:pindoro/features/drive/ui/drive_controller.dart';
import 'package:pindoro/features/learning/data/drive_history.dart';
import 'package:pindoro/features/learning/data/drive_log.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/learning/ui/drive_labels.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Every drive by week, the latest first (board V32-60): the route, the day, the level, the
/// outcome in a few words and the tier (none for Guided, watched only). Only [route]'s when
/// given (Progress's routes). A drive whose track is still kept opens.
class PastDrivesScreen extends ConsumerWidget {
  const PastDrivesScreen({super.key, this.route});

  final String? route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final drives = ref.watch(pastDrivesProvider).value;
    final history = ref.watch(driveHistoryProvider).value;
    final settings = ref.watch(settingsProvider).value;
    final streets = ref.watch(cityStreetsProvider).value ?? const {};
    final places = ref.watch(packPlacesProvider).value ?? const {};
    final now = ref.watch(clockProvider)();
    final locale = Localizations.localeOf(context).toLanguageTag();
    final route = this.route;
    String name(String r) => routeName(
      l10n,
      r,
      places: places,
      streets: streets,
      settings: settings,
    );
    final title = route == null ? l10n.pastDrivesTitle : name(route);
    if (drives == null || history == null) {
      return PageScaffold(
        title: title,
        children: const [Center(child: LaneLoader())],
      );
    }
    final routes = {
      for (final (i, d) in history.drives.indexed)
        d.id: history.summaries[i].route,
    };
    final weeks = <DateTime, List<({DriveRow drive, bool tracked})>>{};
    for (final d in drives) {
      if (route != null && routes[d.drive.id] != route) continue;
      weeks.putIfAbsent(weekOf(d.drive.startedAt), () => []).add(d);
    }
    final thisWeek = weekOf(now);
    final lastWeek = weekOf(thisWeek.subtract(const Duration(days: 1)));
    String weekTitle(DateTime w) => w == thisWeek
        ? l10n.pastDrivesThisWeek
        : w == lastWeek
        ? l10n.pastDrivesLastWeek
        : l10n.pastDrivesWeekOf(DateFormat.MMMd(locale).format(w));
    return PageScaffold(
      title: title,
      children: [
        if (weeks.isEmpty)
          Text(l10n.pastDrivesEmpty, style: PindoroType.bodyMd),
        for (final MapEntry(key: week, value: list) in weeks.entries) ...[
          SectionTitle(weekTitle(week)),
          ListGroup(
            children: [
              for (final d in list)
                _DriveRow(
                  drive: d.drive,
                  title: switch (routes[d.drive.id]) {
                    final r? => name(r),
                    null => switch (streets[d.drive.targetStreet]) {
                      final s? => l10n.pastDriveTo(streetName(s, settings)),
                      null => l10n.driveTitle,
                    },
                  },
                  decisions:
                      history.decisions[d.drive.id] ??
                      const <DriveDecisionRow>[],
                  opens: d.tracked,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _DriveRow extends StatelessWidget {
  const _DriveRow({
    required this.drive,
    required this.title,
    required this.decisions,
    required this.opens,
  });

  final DriveRow drive;
  final String title;
  final List<DriveDecisionRow> decisions;
  final bool opens;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final own = decisions
        .map(
          (r) => turnMark(
            ok: r.ok,
            help: r.help,
            recentHelp: r.recentHelp,
            hesitated: r.hesitated,
          ),
        )
        .where((m) => m == TurnMark.good || m == TurnMark.hard)
        .length;
    final line = [
      DateFormat.MMMEd(locale).add_Hm().format(drive.startedAt.toLocal()),
      levelLabel(l10n, drive.level),
      if (drive.outcome == DriveOutcome.abandoned)
        l10n.pastDriveAbandoned
      else if (drive.rescued)
        l10n.pastDriveRescued
      else if (decisions.isNotEmpty)
        l10n.pastDriveOwn(own, decisions.length),
      if (drive.gpsGaps > 0) l10n.pastDriveGpsLost(drive.gpsGaps),
    ].join(' · ');
    final guided = drive.level == DriveLevel.guided;
    final tier = drive.tier;
    return ListRow(
      title: title,
      subtitle: line,
      leading: const RowTile(PindoroGlyph.car),
      trailing: switch ((guided, tier)) {
        (true, _) => TierChip(tier: null, label: l10n.pastDriveNoTier),
        (false, final t?) => TierChip(tier: t, label: tierWord(l10n, t)),
        _ => null,
      },
      onTap: opens
          ? () => unawaited(context.push(Routes.pastDriveOf(drive.id)))
          : null,
    );
  }
}

/// A past drive replayed from its track on today's graph, with the turns
/// and GPS gaps it was saved with; null once its track or destination is
/// gone.
final pastDriveProvider = FutureProvider.autoDispose
    .family<DriveReview?, String>((ref, id) async {
      final dao = ref.watch(driveLogDaoProvider);
      final drive = await dao.drive(id);
      final fixes = await dao.track(id);
      final graph = await ref.watch(drivingGraphProvider.future);
      final streets = await ref.watch(cityStreetsProvider.future);
      final byNode = await ref.watch(junctionsByNodeProvider.future);
      final street = streets[drive?.targetStreet];
      final junction = byNode[drive?.targetNode];
      if (drive == null ||
          fixes == null ||
          graph == null ||
          street == null ||
          junction == null) {
        return null;
      }
      final match = matchDrive(graph, fixes);
      final (:graded, :stoppedM) = gradeDrive(
        graph,
        match,
        junction,
        streets: streets,
      );
      return DriveReview(
        id: id,
        rescued: drive.rescued,
        target: (
          junction: junction,
          street: street,
          place: null,
          at: switch ((drive.targetLat, drive.targetLon)) {
            (final lat?, final lon?) => LatLng(lat, lon),
            _ => null,
          },
        ),
        match: match,
        graded: graded,
        stoppedM: stoppedM,
        credited: drive.credited,
        failed: drive.failed,
        gaps: (
          count: drive.gpsGaps,
          longest: Duration(seconds: drive.longestGapS),
        ),
      );
    });

/// One past drive (V32-60): its debrief, offered while fresh.
class PastDriveScreen extends StatelessWidget {
  const PastDriveScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context) =>
      DebriefScreen(id: id, onDone: () => context.pop());
}
