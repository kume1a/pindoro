import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../generated/pindoro_tokens.dart';
import '../../theme.dart';
import '../graphics.dart';
import '../pindoro_button.dart';
import '../surfaces.dart';
import '../tappable.dart';
import 'drive_parts.dart';

/// The level chip in the [StoppedBar]: the level's [icon] and [label], a
/// chevron that points up while [open].
class _LevelChip extends StatelessWidget {
  const _LevelChip({
    required this.icon,
    required this.label,
    required this.semanticsLabel,
    required this.open,
    required this.onTap,
  });

  final PindoroGlyph icon;
  final String label;
  final String semanticsLabel;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    // A face with its edge on a lip of its own colour, as the buttons are.
    return Tappable(
      label: semanticsLabel,
      toggled: open,
      onTap: onTap,
      child: LipBox(
        face: c.surfaceRaised,
        lip: open ? c.primaryLip : c.lineStrong,
        border: open ? c.primaryBase : c.lineStrong,
        radius: PindoroRadius.lg,
        padding: const EdgeInsets.fromLTRB(
          PindoroSpace.s4,
          0,
          PindoroSpace.s3,
          0,
        ),
        child: SizedBox(
          height:
              PindoroSize.buttonLg -
              PindoroElevation.e1 -
              2 * PindoroStroke.base,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: PindoroSpace.s1,
            children: [
              PindoroIcon(icon, size: PindoroSize.iconSm, color: c.textPrimary),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PindoroType.bodyLg.copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              RotatedBox(
                quarterTurns: open ? 2 : 0,
                child: PindoroIcon(
                  PindoroGlyph.chevronDown,
                  size: PindoroSize.iconSm,
                  color: c.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// End drive's least width on the [StoppedBar], in square buttons.
const int _endMinSquares = 2;

/// The level shown on the [StoppedBar]'s chip.
typedef StoppedLevel = ({
  PindoroGlyph icon,
  String label,
  String semanticsLabel,
});

/// The only controls on a driving screen, while the car is stopped
/// (StoppedBar): the distance [left] and the [arrival] time, Mute, the
/// [level] chip that opens the [picker] (under its [pickerTitle] and
/// [pickerReason]), Route (the preview and the destination, [routeLabel]) and End drive.
class StoppedBar extends StatelessWidget {
  const StoppedBar({
    super.key,
    required this.semanticsLabel,
    required this.left,
    required this.arrival,
    required this.muted,
    required this.muteLabel,
    required this.onMute,
    required this.level,
    required this.levelOpen,
    required this.onLevel,
    required this.endLabel,
    required this.onEnd,
    this.picker,
    this.pickerTitle,
    this.pickerReason,
    this.routeLabel,
    this.onRoute,
  });

  final String semanticsLabel;
  final String? left;
  final String? arrival;
  final bool muted;
  final String muteLabel;
  final VoidCallback onMute;
  final StoppedLevel level;
  final bool levelOpen;
  final VoidCallback onLevel;
  final String endLabel;
  final VoidCallback onEnd;
  final Widget? picker;
  final String? pickerTitle;
  final String? pickerReason;
  final String? routeLabel;
  final VoidCallback? onRoute;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final bottom = math.max(
      MediaQuery.paddingOf(context).bottom,
      PindoroSpace.s3,
    );
    final info = PindoroType.bodyLg.copyWith(fontWeight: FontWeight.w800);
    final picker = this.picker;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticsLabel,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          PindoroSpace.s3,
          PindoroSpace.s3,
          PindoroSpace.s3,
          bottom,
        ),
        decoration: BoxDecoration(
          color: c.driveSurface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(PindoroRadius.r2xl),
          ),
          border: Border(
            top: BorderSide(
              color: c.driveSurfaceLine,
              width: PindoroStroke.base,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            if (levelOpen && picker != null)
              PickerPanel(
                title: pickerTitle,
                reason: pickerReason,
                picker: picker,
              ),
            Row(
              children: [
                if (left case final l?)
                  Expanded(
                    child: Text(l, style: info.copyWith(color: c.driveText)),
                  )
                else
                  const Spacer(),
                if (arrival case final a?)
                  Text(
                    a,
                    style: info.copyWith(
                      color: c.driveText2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            unscaled(
              context,
              LayoutBuilder(
                builder: (context, box) {
                  final route = switch ((routeLabel, onRoute)) {
                    (final label?, final tap?) => PindoroButton(
                      label: label,
                      icon: PindoroGlyph.route,
                      iconOnly: true,
                      large: true,
                      variant: PindoroButtonVariant.secondary,
                      onPressed: tap,
                    ),
                    _ => null,
                  };
                  // End drive keeps room for its words (two lines at worst); the level's
                  // name gives way to it.
                  final squares = route == null ? 1 : 2;
                  final chipMax =
                      box.maxWidth -
                      (squares + _endMinSquares) * PindoroSize.buttonLg -
                      (squares + 1) * PindoroSpace.s2;
                  return Row(
                    spacing: PindoroSpace.s2,
                    children: [
                      PindoroButton(
                        label: muteLabel,
                        icon: muted
                            ? PindoroGlyph.soundOff
                            : PindoroGlyph.soundOn,
                        iconOnly: true,
                        large: true,
                        variant: PindoroButtonVariant.secondary,
                        onPressed: onMute,
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: math.max(0, chipMax),
                        ),
                        child: _LevelChip(
                          icon: level.icon,
                          label: level.label,
                          semanticsLabel: level.semanticsLabel,
                          open: levelOpen,
                          onTap: onLevel,
                        ),
                      ),
                      ?route,
                      Expanded(
                        child: PindoroButton(
                          label: endLabel,
                          large: true,
                          variant: PindoroButtonVariant.secondary,
                          onPressed: onEnd,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
