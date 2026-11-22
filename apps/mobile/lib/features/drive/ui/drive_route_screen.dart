import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/navigation.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/drive/ui/destination_search.dart';
import 'package:pindoro/features/drive/ui/drive_controller.dart';
import 'package:pindoro/features/learning/data/drive_places.dart';
import 'package:pindoro/features/learning/ui/drive_labels.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Route and destination while stopped (the stopped bar's Route, SPEC §16.23 item 116): where
/// the drive goes and a new one, Home and Work first. A parked screen: it closes itself the
/// moment the car moves, or the drive ends.
class DriveRouteScreen extends ConsumerWidget {
  const DriveRouteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    ref.listen(driveControllerProvider, (_, next) {
      if (next is! DriveRecording || !next.stopped) popIfCurrent(context);
    });
    final r = ref.watch(driveControllerProvider);
    if (r is! DriveRecording) return const Scaffold();
    final view = r.view;
    final places = ref.watch(drivePlacesProvider).value;
    void pick(DriveDest dest) => unawaited(() async {
      await ref.read(driveControllerProvider.notifier).changeDestination(dest);
      if (context.mounted) popIfCurrent(context);
    }());
    ListRow anchor(PindoroGlyph glyph, String title, DriveTarget place) =>
        ListRow(
          leading: RowTile(glyph),
          title: title,
          subtitle: targetName(place, settings),
          trailing: const PindoroIcon(PindoroGlyph.chevronRight),
          onTap: () => pick((
            street: place.street,
            place: place.place,
            junction: place.junction,
          )),
        );
    final home = places?.home;
    final work = places?.work;
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
          onPick: pick,
          quick: [
            if (home != null) anchor(PindoroGlyph.home, l10n.driveHome, home),
            if (work != null)
              anchor(PindoroGlyph.briefcase, l10n.driveWork, work),
          ],
        ),
      ],
    );
  }
}
