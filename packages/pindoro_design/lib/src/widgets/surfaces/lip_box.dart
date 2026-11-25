import 'package:flutter/material.dart';

import '../../generated/pindoro_tokens.dart';
import '../../theme.dart';

/// A flat face sitting on a solid bottom lip: the system's only depth.
/// Cards, list groups, chips, pills and buttons are all built from it.
class LipBox extends StatelessWidget {
  const LipBox({
    super.key,
    required this.child,
    this.face,
    this.lip,
    this.border,
    this.lipHeight = PindoroElevation.e1,
    this.radius = PindoroRadius.xl,
    this.padding = EdgeInsets.zero,
    this.shadow = false,
  });

  final Widget child;

  /// Defaults to `color.surface.raised` with a `color.line.base` lip.
  final Color? face;
  final Color? lip;

  /// A [PindoroStroke.base] outline in this colour.
  final Color? border;
  final double lipHeight;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// `shadow.float`, for things floating over the map.
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final theme = PindoroTheme.of(context);
    final c = theme.colors;
    final shape = BorderRadius.circular(radius);
    return Container(
      padding: EdgeInsets.only(bottom: lipHeight),
      decoration: BoxDecoration(
        color: lip ?? c.lineBase,
        borderRadius: shape,
        boxShadow: shadow ? [theme.floatShadow] : null,
      ),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: face ?? c.surfaceRaised,
          borderRadius: shape,
          border: border == null
              ? null
              : Border.all(color: border!, width: PindoroStroke.base),
        ),
        child: child,
      ),
    );
  }
}
