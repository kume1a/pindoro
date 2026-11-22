import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/drive/ui/drive_controller.dart';
import 'package:pindoro/features/drive/ui/drive_screen.dart';
import 'package:pindoro/features/learning/data/drive_log.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Every drive, the latest first (board V32-60): where to, when, how far,
/// how it went and whether GPS dropped out. A graded drive whose track is
/// still kept opens its review.
class PastDrivesScreen extends ConsumerWidget {
  const PastDrivesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final drives = ref.watch(pastDrivesProvider).value;
    return PageScaffold(
      title: l10n.pastDrivesTitle,
      children: [
        if (drives case final drives? when drives.isEmpty)
          Text(l10n.pastDrivesEmpty, style: PindoroType.bodyMd)
        else if (drives != null)
          ListGroup(
            children: [
              for (final d in drives)
                _DriveRow(
                  drive: d.drive,
                  opens: d.tracked && d.drive.tier != null,
                ),
            ],
          ),
      ],
    );
  }
}

class _DriveRow extends ConsumerWidget {
  const _DriveRow({required this.drive, required this.opens});

  final DriveRow drive;
  final bool opens;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final street = ref.watch(cityStreetsProvider).value?[drive.targetStreet];
    final locale = Localizations.localeOf(context).toLanguageTag();
    final line = [
      DateFormat.MMMEd(locale).add_Hm().format(drive.startedAt.toLocal()),
      formatDistance(drive.drivenM, l10n),
      switch ((drive.outcome, drive.tier)) {
        (DriveOutcome.abandoned, _) => l10n.pastDriveAbandoned,
        (_, final tier?) => tierLabel(l10n, tier),
        _ => l10n.driveNoTrack,
      },
      if (drive.gpsGaps > 0) l10n.pastDriveGpsLost(drive.gpsGaps),
    ].join(' · ');
    return ListRow(
      title: street == null
          ? l10n.driveTitle
          : l10n.pastDriveTo(streetName(street, settings)),
      subtitle: line,
      leading: const RowTile(PindoroGlyph.car),
      trailing: opens ? const PindoroIcon(PindoroGlyph.chevronRight) : null,
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
        target: (junction: junction, street: street),
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

/// One past drive's review (Past drives).
class PastDriveScreen extends ConsumerWidget {
  const PastDriveScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final review = ref.watch(pastDriveProvider(id));
    return switch (review) {
      AsyncData(value: final review?) => DriveReviewView(
        review: review,
        onDone: () => context.pop(),
      ),
      AsyncLoading() => const Scaffold(body: SizedBox.expand()),
      _ => PageScaffold(
        title: context.l10n.pastDrivesTitle,
        children: [Text(context.l10n.pastDriveGone, style: PindoroType.bodyMd)],
      ),
    };
  }
}
