import 'package:flutter/material.dart';

import '../theme.dart';
import 'graphics.dart';
import 'round_hud.dart';

/// A pill with the wrench in `color.path.node.review.icon`: "Added to your
/// Pit stop" on a reveal, "3 to your Pit stop" on results.
class PitStopChip extends StatelessWidget {
  const PitStopChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Pill(
    label: label,
    icon: PindoroGlyph.wrench,
    iconColor: PindoroTheme.of(context).colors.pathNodeReviewIcon,
  );
}

/// A street's Pit stop step on [steps] bars (`.pd-gauge`): 6 × 14 dp, 2 dp
/// apart, `color.primary.text` up to [step] and `color.line.base` after.
class ReviewGauge extends StatelessWidget {
  const ReviewGauge(
    this.step, {
    super.key,
    required this.semanticLabel,
    this.steps = 4,
  });

  final int step;
  final int steps;

  /// "Review step 2 of 4".
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Semantics(
      container: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          for (var i = 0; i < steps; i++)
            Container(
              width: 6,
              height: 14,
              decoration: BoxDecoration(
                color: i < step ? c.primaryText : c.lineBase,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}
