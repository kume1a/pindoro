import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/drive/ui/destination_search.dart';
import 'package:pindoro/features/drive/ui/drive_controller.dart';
import 'package:pindoro/features/learning/ui/drive_labels.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Route and destination while stopped (the stopped bar's Route, SPEC §16.23 item 116): where
/// the drive goes and a new destination. A parked screen: it closes itself the moment the car
/// moves, or the drive ends.
class DriveRouteScreen extends ConsumerWidget {
  const DriveRouteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    ref.listen(driveControllerProvider, (_, next) {
      if ((next is! DriveRecording || !next.stopped) && context.mounted) {
        Navigator.of(context).pop();
      }
    });
    final r = ref.watch(driveControllerProvider);
    if (r is! DriveRecording) return const Scaffold();
    final view = r.view;
    return PageScaffold(
      title: l10n.driveRouteTitle,
      children: [
        ListGroup(
          children: [
            ListRow(
              leading: const RowTile(PindoroGlyph.flag),
              title: targetName(r.target, settings),
              subtitle: switch (view?.leftM) {
                final m? => l10n.driveLeft(formatDistance(m, l10n)),
                null => null,
              },
            ),
          ],
        ),
        SectionTitle(l10n.driveChangeDest),
        DestinationSearch(
          here: view?.at,
          onPick: (dest) => unawaited(() async {
            await ref
                .read(driveControllerProvider.notifier)
                .changeDestination(dest);
            if (context.mounted) Navigator.of(context).pop();
          }()),
        ),
      ],
    );
  }
}
