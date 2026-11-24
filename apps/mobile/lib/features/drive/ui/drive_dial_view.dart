import 'package:flutter/material.dart';
import 'package:pindoro/core/database/database.dart' show Settings;
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/features/drive/ui/drive_controller.dart';
import 'package:pindoro/features/drive/ui/drive_levels.dart';
import 'package:pindoro/features/drive/ui/drive_view_parts.dart';
import 'package:pindoro/features/learning/ui/drive_labels.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart' hide Navigator;

/// "Now Coached" stays this long after the guard steps in (board V32-31).
const Duration _guardNotice = Duration(seconds: 4);

/// Coached and Quiet while driving (boards V32-30, V32-31): the heading dial and the district,
/// Recovery over it after a wrong turn, the limit and camera, the status dot, "Now Coached"
/// after the guard; the [stoppedBar] rising while stopped, and Route at a touch ([revealed])
/// while moving (item 134).
class DialDrive extends StatelessWidget {
  const DialDrive({
    required this.recording,
    required this.now,
    required this.settings,
    required this.revealed,
    required this.stoppedBar,
    required this.onTouch,
    required this.onRoute,
    super.key,
  });

  final DriveRecording recording;
  final DateTime now;
  final Settings? settings;
  final bool revealed;
  final Widget? stoppedBar;
  final VoidCallback onTouch;
  final VoidCallback onRoute;

  @override
  Widget build(BuildContext context) {
    final r = recording;
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final view = r.view;
    final lost = view?.gpsLostS != null;
    final recovering = view?.recovering ?? false;
    final status = lost
        ? DriveStatus.lost
        : recovering
        ? DriveStatus.recovering
        : DriveStatus.good;
    final top = MediaQuery.paddingOf(context).top;
    final point = switch (view?.headingDeg) {
      final h? => compassPointOf(h),
      null => null,
    };
    final direction = point == null ? null : l10n.compassWord(point.name);
    final district = switch (r.district) {
      final d? => districtName(d, settings),
      null => null,
    };
    final goodS = view?.goodS;
    final limit = view?.limitKmh;
    final over = view?.over ?? false;
    final guardedAt = r.guardedAt;
    final guarded =
        guardedAt != null && now.difference(guardedAt) < _guardNotice;
    // A passenger's way in while moving (item 134): a touch shows Route for a while.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => onTouch(),
      child: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              child: Center(
                child: recovering
                    ? _RecoveryTurn(view: view!, settings: settings)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 28,
                        children: [
                          HeadingDial(
                            heading: lost ? null : view?.headingDeg,
                            letter: point == null
                                ? ''
                                : l10n.driveCardinal(point.name),
                            status: status,
                            semanticsLabel: lost || direction == null
                                ? l10n.a11yHeadingLost
                                : district == null
                                ? l10n.a11yHeading(direction)
                                : l10n.a11yHeadingIn(direction, district),
                          ),
                          if (district != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: PindoroSpace.s3,
                              ),
                              child: ExcludeSemantics(
                                child: DistrictLine(district),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
          if (recovering)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: goodS == null ? 1 : 0.45,
                child: const RecoveryBand(),
              ),
            ),
          if (!lost && !r.stopped && limit != null)
            Positioned(
              top: top + PindoroSpace.s2,
              left: PindoroSpace.s3,
              child: Row(
                spacing: PindoroSpace.s3,
                children: [
                  SpeedLimitSign(
                    limit: limit,
                    over: over,
                    beat: r.beat,
                    semanticsLabel: over
                        ? l10n.a11ySpeedOver(limit)
                        : l10n.a11ySpeedLimit(limit),
                  ),
                  if (view?.camera ?? false)
                    Semantics(
                      label: l10n.a11yCameraAhead,
                      child: const CameraBadge(),
                    ),
                ],
              ),
            ),
          Positioned(
            // The dot's centre sits 24 dp under the inset and 28 dp in.
            top: top,
            right: PindoroSpace.s1,
            child: Row(
              spacing: PindoroSpace.s3,
              children: [
                if (r.level == DriveLevel.coached && r.speaking)
                  const SpeakingBars(),
                StatusDot(
                  status: status,
                  ring: recovering && goodS != null
                      ? goodS / LearningConfig.recoveryHoldS
                      : null,
                  semanticsLabel: switch (status) {
                    DriveStatus.good => l10n.a11yOnGoodPath,
                    DriveStatus.recovering => l10n.a11yRecoveringDot,
                    DriveStatus.lost => l10n.a11yFindingPosition,
                  },
                ),
              ],
            ),
          ),
          if (guarded)
            Positioned(
              left: PindoroSpace.s3,
              right: PindoroSpace.s3,
              bottom: MediaQuery.paddingOf(context).bottom + PindoroSpace.s16,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: PindoroSpace.s3,
                  ),
                  decoration: BoxDecoration(
                    color: c.drivePlate,
                    borderRadius: BorderRadius.circular(PindoroRadius.lg),
                  ),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      l10n.driveNowLevel(levelLabel(l10n, r.level)),
                      style: PindoroType.driveRead.copyWith(
                        color: c.drivePlateText,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: StoppedRise(stopped: r.stopped, child: stoppedBar),
          ),
          if (!r.stopped)
            Positioned(
              right: PindoroSpace.s3,
              bottom: MediaQuery.paddingOf(context).bottom + PindoroSpace.s4,
              child: DrivePop(
                revealed: revealed,
                child: DriveMapButton(
                  label: l10n.a11yDriveRoute,
                  onTap: onRoute,
                  child: DriveGlyph(
                    DriveGlyphName.routes,
                    size: 28,
                    color: c.driveText,
                    cut: c.driveSurface,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The heading-up next-turn view while recovering (board V32-31): the way back and the street
/// to turn into, dimmed once back on a good path.
class _RecoveryTurn extends StatelessWidget {
  const _RecoveryTurn({required this.view, required this.settings});

  final NavView view;
  final Settings? settings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final next = view.next;
    final glyph = next == null ? DriveGlyphName.straight : decisionGlyph(next);
    final street = next?.street;
    return Semantics(
      liveRegion: true,
      label: l10n.a11yRecovering(
        [
          decisionAction(l10n, glyph, onto: street != null),
          if (street != null) streetName(street, settings),
        ].join(' '),
      ),
      child: ExcludeSemantics(
        child: AnimatedOpacity(
          opacity: view.goodS == null ? 1 : 0.45,
          duration: PindoroMotion.durationSlow,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: PindoroSpace.s4,
            children: [
              DriveGlyph(
                glyph,
                size: 220,
                color: c.drivePlateGlyph,
                cut: c.driveQuietBg,
              ),
              if (street != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PindoroSpace.s3,
                  ),
                  child: MediaQuery.withNoTextScaling(
                    child: Text(
                      shortKind(streetName(street, settings)),
                      textAlign: TextAlign.center,
                      style: PindoroType.driveRead.copyWith(
                        color: c.driveQuietText,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Off's black screen (board V32-40): the recording dot, the [stoppedBar] rising while stopped.
class OffDrive extends StatelessWidget {
  const OffDrive({required this.stoppedBar, super.key});

  final Widget? stoppedBar;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        top: MediaQuery.paddingOf(context).top + PindoroSpace.s4,
        right: PindoroSpace.s5,
        child: RecordingDot(semanticsLabel: context.l10n.driveRecording),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: StoppedRise(stopped: stoppedBar != null, child: stoppedBar),
      ),
    ],
  );
}
