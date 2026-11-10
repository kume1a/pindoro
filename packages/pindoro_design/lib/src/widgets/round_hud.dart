import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';
import 'progress.dart';
import 'surfaces.dart';
import 'tappable.dart';

/// The quiz top bar's progress: one segment per question. Answered segments
/// are lane yellow (a Miss is red), the current one cobalt, the rest outlined.
class QuestionBar extends StatelessWidget {
  const QuestionBar({
    super.key,
    required this.tiers,
    required this.total,
    required this.semanticLabel,
  });

  /// Answers so far, in order.
  final List<Tier> tiers;
  final int total;

  /// "Question 5 of 10".
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Row(
        spacing: PindoroSpace.s1,
        children: [
          for (var i = 0; i < total; i++)
            Expanded(
              child: AnimatedContainer(
                duration: PindoroMotion.durationFast,
                curve: PindoroMotion.easeStandard,
                height: 12,
                decoration: BoxDecoration(
                  color: i < tiers.length
                      ? (tiers[i] == Tier.miss
                            ? c.feedbackMissFill
                            : c.progressDone)
                      : i == tiers.length
                      ? c.progressCurrent
                      : c.progressTodo,
                  borderRadius: BorderRadius.circular(PindoroRadius.xs),
                  border: i > tiers.length
                      ? Border.all(
                          color: c.progressTodoBorder,
                          width: PindoroStroke.base,
                        )
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A raised pill (XP, city, area size); floats over the map with a shadow.
/// [face], [lip] and [foreground] recolour it (the streak pill's states).
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.icon,
    this.iconColor,
    this.iconAccent,
    this.face,
    this.lip,
    this.foreground,
    this.floating = false,
    this.ring = false,
    this.semanticLabel,
    this.onTap,
  });

  final String label;
  final PindoroGlyph? icon;
  final Color? iconColor;

  /// [PindoroIcon.accent], e.g. the flame's core.
  final Color? iconAccent;
  final Color? face;
  final Color? lip;

  /// The label's colour; defaults to `color.text.primary`.
  final Color? foreground;
  final bool floating;

  /// The accent ring, while the value changes (Home after a round).
  final bool ring;
  final String? semanticLabel;

  /// Makes the pill a button (Results' league chip opens the league).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pill = _pill(context);
    if (onTap == null) return pill;
    // Its own node: next to other pills it would merge into their parent.
    return Semantics(
      container: true,
      child: Tappable(label: semanticLabel ?? label, onTap: onTap, child: pill),
    );
  }

  Widget _pill(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Semantics(
      container: semanticLabel != null,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: AccentRing(
        on: ring,
        radius: PindoroRadius.full,
        child: LipBox(
          radius: PindoroRadius.full,
          face: face,
          lip: lip,
          shadow: floating,
          padding: const EdgeInsets.symmetric(
            horizontal: PindoroSpace.s3,
            vertical: PindoroSpace.s2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: PindoroSpace.s1,
            children: [
              if (icon != null)
                PindoroIcon(
                  icon!,
                  size: PindoroSize.iconSm,
                  color: iconColor ?? c.textPrimary,
                  accent: iconAccent,
                  cut: face,
                ),
              // Wraps rather than overflows: long labels at large text sizes.
              Flexible(
                child: Text(
                  label,
                  style: PindoroType.numericSm.copyWith(
                    color: foreground ?? c.textPrimary,
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

/// A 48 dp map control (raised, 2 dp lip, `shadow.float`).
class MapControl extends StatelessWidget {
  const MapControl({
    super.key,
    required this.glyph,
    required this.semanticLabel,
    required this.onPressed,
  });

  final PindoroGlyph glyph;
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tappable(
    label: semanticLabel,
    onTap: onPressed,
    child: LipBox(
      radius: PindoroRadius.md,
      shadow: true,
      child: SizedBox.square(
        dimension: PindoroSize.tapMin - PindoroElevation.e1,
        child: Center(child: PindoroIcon(glyph)),
      ),
    ),
  );
}
