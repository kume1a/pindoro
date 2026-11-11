import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/core/toast.dart';
import 'package:pindoro/features/lesson/ui/drive_controller.dart';
import 'package:pindoro/features/map/ui/route_view.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// A unit's Final drive (canvas R4-40), also Jump ahead on a locked unit:
/// road trips across the raion, a bar of 3, ✕ or back asks first. The third
/// trip passed opens Unit complete.
class DriveScreen extends ConsumerStatefulWidget {
  const DriveScreen({super.key, required this.unitId});

  final String unitId;

  @override
  ConsumerState<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends ConsumerState<DriveScreen> {
  @override
  void initState() {
    super.initState();
    // Providers can't change while the tree builds; begin right after.
    Future.microtask(
      () => ref.read(driveControllerProvider.notifier).start(widget.unitId),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(driveControllerProvider, (previous, next) {
      switch (next) {
        case DrivePassed(:final unitId, :final xp):
          ref.read(feedbackProvider).unitDone();
          context.go(Routes.unitDoneOf(unitId, xp: xp));
        case DriveMissing():
          showToast(context, context.l10n.driveMissing);
          context.go(Routes.path);
        case DrivePlaying(:final score?)
            when !(previous is DrivePlaying && previous.answered):
          ref.read(feedbackProvider).tier(score.tier);
        default:
      }
    });
    return switch (ref.watch(driveControllerProvider)) {
      final DrivePlaying p => _DriveView(p),
      _ => const Scaffold(body: Center(child: LaneLoader())),
    };
  }
}

class _DriveView extends ConsumerWidget {
  const _DriveView(this.play);

  final DrivePlaying play;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(driveControllerProvider.notifier);
    final feedback = ref.read(feedbackProvider);
    final score = play.score;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave(context));
      },
      child: RouteView(
        area: play.shape,
        questionKey: play.number,
        ask: l10n.driveAsk(driveStep(play)),
        trip: play.trip,
        draft: play.draft,
        reveal: score == null
            ? null
            : (
                key: play.number,
                score: score,
                chips: const [],
                action: !play.passes
                    ? l10n.routeTryAgain
                    : play.completes
                    ? l10n.commonContinue
                    : l10n.commonNext,
                celebration: celebrationFor(
                  score.tier,
                  perfectsThisRound: 0,
                  inARow: 0,
                ),
              ),
        topBar: _DriveTopBar(play, onLeave: () => _leave(context)),
        showBody: l10n.routeShowDriveBody,
        ghost: play.firstTrip,
        onDraft: controller.drawTo,
        onCheck: () {
          feedback.confirm();
          controller.checkRoute();
        },
        onShow: controller.showRoute,
        onNext: controller.next,
      ),
    );
  }

  Future<void> _leave(BuildContext context) async {
    final l10n = context.l10n;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => PindoroDialog(
        title: l10n.driveLeaveTitle,
        body: l10n.driveLeaveBody,
        primary: l10n.routeKeepDriving,
        secondary: l10n.lessonLeave,
      ),
    );
    if ((leave ?? false) && context.mounted) context.go(Routes.path);
  }
}

/// ✕, a segment per trip (passed ones filled) and the XP of this drive.
class _DriveTopBar extends StatelessWidget {
  const _DriveTopBar(this.play, {required this.onLeave});

  final DrivePlaying play;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final xp = formatNumber(play.xp);
    return Row(
      spacing: PindoroSpace.s3,
      children: [
        PindoroIconButton(
          glyph: PindoroGlyph.close,
          semanticLabel: l10n.a11yLeaveDrive,
          onPressed: onLeave,
        ),
        Expanded(
          child: QuestionBar(
            tiers: [
              for (var i = 0; i < play.passed; i++) Tier.great,
              // A Miss keeps its segment current: that trip is driven again.
              if (play.passes) Tier.great,
            ],
            total: CourseRules.finalDriveTrips,
            semanticLabel: l10n.a11yDriveStep(driveStep(play)),
          ),
        ),
        Pill(
          label: xp,
          icon: PindoroGlyph.xp,
          iconColor: PindoroTheme.of(context).colors.xpFill,
          floating: true,
          semanticLabel: l10n.a11yLessonXp(xp),
        ),
      ],
    );
  }
}
