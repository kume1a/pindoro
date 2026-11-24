import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../generated/pindoro_tokens.dart';
import '../../theme.dart';
import '../drive_glyph.dart';
import '../graphics.dart';
import '../tappable.dart';
import 'drive_parts.dart';

/// Guided's bar, floating over the bottom of the map (DriveBottomBar, SPEC §16.23 item 130):
/// the distance [left], the [arrival] time and the [minutes] left side by side over a line of
/// the drive's [progress] (0 to 1), or one [line] instead ("GPS lost 1:02"); the rescued mark
/// before them. The [trailing] button (End drive, while stopped) sits at its right end. One
/// polite live region, [semanticsLabel].
class DriveBottomBar extends StatelessWidget {
  const DriveBottomBar({
    super.key,
    required this.semanticsLabel,
    this.left,
    this.arrival,
    this.minutes,
    this.progress,
    this.line,
    this.rescued = false,
    this.trailing,
  });

  final String semanticsLabel;
  final String? left;
  final String? arrival;
  final String? minutes;
  final double? progress;
  final String? line;
  final bool rescued;
  final Widget? trailing;

  static const double _track = 4;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final read = PindoroType.headlineSm.copyWith(
      color: c.drivePlateText,
      height: 1.15,
    );
    final bottom = math.max(
      MediaQuery.paddingOf(context).bottom,
      PindoroSpace.s3,
    );
    final progress = this.progress;
    final values = [?left, ?arrival, ?minutes];
    final words = Column(
      mainAxisSize: MainAxisSize.min,
      spacing: PindoroSpace.s2,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: line != null
              ? Text(line!, style: read)
              : Row(
                  spacing: PindoroSpace.s6,
                  children: [
                    if (rescued)
                      DriveGlyph(
                        DriveGlyphName.rescue,
                        size: PindoroSize.iconMd,
                        color: c.drivePlateText2,
                        cut: c.drivePlate,
                      ),
                    for (final v in values) Text(v, style: read),
                  ],
                ),
        ),
        if (line == null && progress != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(_track / 2),
            child: Container(
              height: _track,
              color: c.drivePlateLine,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: progress.clamp(0, 1),
                heightFactor: 1,
                child: ColoredBox(color: c.drivePlateGlyph),
              ),
            ),
          ),
      ],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(PindoroSpace.s3, 0, PindoroSpace.s3, bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.drivePlate,
          borderRadius: BorderRadius.circular(PindoroRadius.xl),
          boxShadow: [plateShadow(c)],
        ),
        child: Padding(
          padding: const EdgeInsets.all(PindoroSpace.s3),
          child: Row(
            spacing: PindoroSpace.s3,
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label: semanticsLabel,
                  child: ExcludeSemantics(child: unscaled(context, words)),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// A square button at an end of Guided's bar (End drive): the [glyph] on the plate's line
/// colour, [label] for screen readers.
class DriveBarButton extends StatelessWidget {
  const DriveBarButton({
    super.key,
    required this.glyph,
    required this.label,
    required this.onTap,
  });

  final PindoroGlyph glyph;
  final String label;
  final VoidCallback onTap;

  static const double size = PindoroSize.buttonMd;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Tappable(
      label: label,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.drivePlateLine,
          borderRadius: BorderRadius.circular(PindoroRadius.md),
        ),
        child: PindoroIcon(
          glyph,
          size: PindoroSize.iconMd,
          color: c.drivePlateText,
          cut: c.drivePlateLine,
        ),
      ),
    );
  }
}
