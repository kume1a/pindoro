import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// An Explore round's top bar: ✕ to leave and the question bar.
class PlayBar extends StatelessWidget {
  const PlayBar({
    super.key,
    required this.leaveLabel,
    required this.onLeave,
    required this.tiers,
    required this.total,
    required this.barLabel,
  });

  final String leaveLabel;
  final VoidCallback onLeave;

  /// The filled segments, of [total].
  final List<Tier> tiers;
  final int total;
  final String barLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: PindoroSpace.s3,
      children: [
        PindoroIconButton(
          glyph: PindoroGlyph.close,
          semanticLabel: leaveLabel,
          onPressed: onLeave,
        ),
        Expanded(
          child: QuestionBar(
            tiers: tiers,
            total: total,
            semanticLabel: barLabel,
          ),
        ),
      ],
    );
  }
}
