import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/drive/ui/drive_controller.dart';
import 'package:pindoro/features/drive/ui/drive_map_screen.dart';
import 'package:pindoro/features/drive/ui/route_place_screen.dart';
import 'package:pindoro/features/learning/ui/drive_labels.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Where the drive set up or driven runs (RouteEnds, SPEC §16.23 item 134): from here through
/// its stops on the way to [to]. To and Add stop open the search; a stop's button drops it.
class DriveRouteEnds extends ConsumerWidget {
  const DriveRouteEnds({required this.to, super.key});

  /// The destination's name.
  final String to;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final controller = ref.read(driveControllerProvider.notifier);
    final via = switch (ref.watch(driveControllerProvider)) {
      DriveSetup(:final via) || DriveRecording(:final via) => via,
      DriveReview() => const <DriveTarget>[],
    };
    // Only the controller after the search: this widget may be gone by then (Guided's routes
    // overview closes 10 s after the last touch).
    void choose(MapPick pick) => unawaited(() async {
      final dest = await pickRoutePlace(context, pick);
      if (dest == null) return;
      await (pick == MapPick.stop
          ? controller.addStop(dest)
          : controller.goTo(dest));
    }());
    return RouteEnds(
      fromLabel: l10n.driveFrom,
      from: l10n.driveFromHere,
      toLabel: l10n.driveTo,
      to: to,
      stops: [
        for (final (i, t) in via.indexed)
          (
            label: l10n.driveStopN(i + 1),
            name: targetName(t, settings),
            removeLabel: l10n.a11yRemoveStop(targetName(t, settings)),
          ),
      ],
      onRemove: controller.removeStop,
      onTo: () => choose(MapPick.drive),
      addLabel: via.length < LearningConfig.navViaMax
          ? l10n.driveAddStop
          : null,
      onAdd: () => choose(MapPick.stop),
    );
  }
}
