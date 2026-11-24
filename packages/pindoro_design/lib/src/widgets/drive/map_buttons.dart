import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../generated/pindoro_tokens.dart';
import '../../theme.dart';
import '../drive_glyph.dart';
import '../graphics.dart';
import '../tappable.dart';
import 'drive_parts.dart';

/// A round button over Guided's map (DriveMapButton, its right-hand column): [child] on
/// `drive.surface` in a `drive.surface-line` rim; [label] for screen readers, [toggled] for
/// one that switches.
class DriveMapButton extends StatelessWidget {
  const DriveMapButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.toggled,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;
  final bool? toggled;

  static const double size = PindoroSize.buttonMd;

  /// A [PindoroGlyph] in the button's ink.
  static Widget glyph(BuildContext context, PindoroGlyph glyph) {
    final c = PindoroTheme.of(context).colors;
    return PindoroIcon(
      glyph,
      size: PindoroSize.iconMd,
      color: c.driveText,
      cut: c.driveSurface,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Tappable(
      label: label,
      toggled: toggled,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.driveSurface,
          border: Border.all(
            color: c.driveSurfaceLine,
            width: PindoroStroke.base,
          ),
          boxShadow: [buttonShadow(c)],
        ),
        child: child,
      ),
    );
  }
}

/// Recentre (DriveMapButton): back onto the car once the map was moved; the arrow leans 45°
/// right, as the car's own arrow never does.
class DriveRecentre extends StatelessWidget {
  const DriveRecentre({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return DriveMapButton(
      label: label,
      onTap: onTap,
      child: Transform.rotate(
        angle: math.pi / 4,
        child: DriveGlyph(
          DriveGlyphName.recentre,
          size: 26,
          color: c.driveText,
          cut: c.driveSurface,
        ),
      ),
    );
  }
}

/// The compass (DriveCompass, a DriveMapButton): a needle with a small hole at its pivot, its
/// north half red, turned by the map's [bearingDeg] so it points north. A tap switches north
/// up and heading up ([label] says which).
class DriveCompass extends StatelessWidget {
  const DriveCompass({
    super.key,
    required this.bearingDeg,
    required this.label,
    required this.onTap,
  });

  final double bearingDeg;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return DriveMapButton(
      label: label,
      onTap: onTap,
      child: Transform.rotate(
        angle: -bearingDeg * math.pi / 180,
        child: CustomPaint(
          size: const Size(12, 32),
          painter: _NeedlePainter(north: c.driveSignRing, south: c.driveText),
        ),
      ),
    );
  }
}

/// A compass needle filling its box, a small hole cut at its pivot: the [north] half up, the
/// [south] half down.
class _NeedlePainter extends CustomPainter {
  const _NeedlePainter({required this.north, required this.south});

  final Color north;
  final Color south;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final hole = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(size.width / 2, mid),
          radius: size.width * 0.18,
        ),
      );
    Path half(double tip) => Path.combine(
      PathOperation.difference,
      Path()
        ..moveTo(size.width / 2, tip)
        ..lineTo(size.width, mid)
        ..lineTo(0, mid)
        ..close(),
      hole,
    );
    canvas
      ..drawPath(half(0), Paint()..color = north)
      ..drawPath(half(size.height), Paint()..color = south);
  }

  @override
  bool shouldRepaint(_NeedlePainter old) =>
      old.north != north || old.south != south;
}

/// The street the car is on, a pill over Guided's map above its bar (StreetChip): one line,
/// cut short with an ellipsis when [name] is wider than the room it has.
class StreetChip extends StatelessWidget {
  const StreetChip(this.name, {super.key, required this.semanticsLabel});

  final String name;
  final String semanticsLabel;

  static const double height = 36;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Semantics(
      liveRegion: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: unscaled(
          context,
          Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: PindoroSpace.s3),
            decoration: BoxDecoration(
              color: c.driveSurface,
              borderRadius: BorderRadius.circular(height / 2),
              border: Border.all(
                color: c.driveSurfaceLine,
                width: PindoroStroke.base,
              ),
              boxShadow: [buttonShadow(c)],
            ),
            child: Center(
              widthFactor: 1,
              child: Text(
                name,
                style: PindoroType.titleSm.copyWith(color: c.driveText),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
