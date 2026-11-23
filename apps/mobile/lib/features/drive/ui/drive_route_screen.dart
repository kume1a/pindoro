import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/navigation.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/drive/ui/drive_controller.dart';
import 'package:pindoro/features/drive/ui/route_ends.dart';
import 'package:pindoro/features/learning/ui/drive_labels.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The drive's route (the stopped bar's Route, Coached and Quiet's Route at a touch; SPEC §16.23
/// items 116, 134): where it goes now and how far, its stops on the way, a new destination or
/// stop. It stays open at any speed (a passenger changes it) and closes when the drive ends.
class DriveRouteScreen extends ConsumerWidget {
  const DriveRouteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    ref.listen(driveControllerProvider, (_, next) {
      if (next is! DriveRecording) popIfCurrent(context);
    });
    final r = ref.watch(driveControllerProvider);
    if (r is! DriveRecording) return const Scaffold();
    final left = r.view?.leftM;
    return PageScaffold(
      title: l10n.driveRouteTitle,
      children: [
        DriveRouteEnds(to: targetName(r.target, settings)),
        if (left != null)
          Text(
            l10n.driveLeft(formatDistance(left, l10n)),
            style: PindoroType.bodyMd.copyWith(
              color: PindoroTheme.of(context).colors.textSecondary,
            ),
          ),
      ],
    );
  }
}
