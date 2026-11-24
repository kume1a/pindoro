import 'package:flutter/material.dart';

import '../../generated/pindoro_tokens.dart';
import '../../theme.dart';

/// Drive type is sized for a glance from the holder, so the system text
/// scale never changes it.
Widget unscaled(BuildContext context, Widget child) =>
    MediaQuery.withNoTextScaling(child: child);

/// The shadow under Guided's turn card and bar, lifting them off the map.
BoxShadow plateShadow(PindoroColors c) => BoxShadow(
  color: c.drivePlate.withValues(alpha: 0.28),
  blurRadius: 18,
  offset: const Offset(0, 6),
);

/// The shadow under Guided's round map buttons and street chip.
BoxShadow buttonShadow(PindoroColors c) => BoxShadow(
  color: c.drivePlate.withValues(alpha: 0.18),
  blurRadius: 12,
  offset: const Offset(0, 4),
);

/// A card over Guided's map, in its surface and rim.
class DriveCard extends StatelessWidget {
  const DriveCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: PindoroSpace.s3),
      padding: const EdgeInsets.all(PindoroSpace.s3),
      decoration: BoxDecoration(
        color: c.driveSurface,
        borderRadius: BorderRadius.circular(PindoroRadius.xl),
        border: Border.all(
          color: c.driveSurfaceLine,
          width: PindoroStroke.base,
        ),
      ),
      child: child,
    );
  }
}

/// The level picker under its [title] and the [reason] for the level suggested (StoppedBar,
/// LevelPickerCard).
class PickerPanel extends StatelessWidget {
  const PickerPanel({super.key, required this.picker, this.title, this.reason});

  final Widget picker;
  final String? title;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Row(
          spacing: PindoroSpace.s2,
          children: [
            Expanded(
              child: Text(
                title ?? '',
                style: PindoroType.labelLg.copyWith(color: c.driveText),
              ),
            ),
            if (reason case final r?)
              Text(r, style: PindoroType.labelLg.copyWith(color: c.driveText2)),
          ],
        ),
        picker,
      ],
    );
  }
}
