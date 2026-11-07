import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Streets due in the Pit stop, on top of Home (canvas R3-01).
class PitStopCard extends StatelessWidget {
  const PitStopCard({super.key, required this.due, required this.onReview});

  final int due;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    return LipBox(
      border: c.lineBase,
      padding: const EdgeInsetsDirectional.fromSTEB(
        PindoroSpace.s4,
        PindoroSpace.s3,
        PindoroSpace.s3,
        PindoroSpace.s3,
      ),
      child: Row(
        spacing: PindoroSpace.s3,
        children: [
          RowTile(
            PindoroGlyph.wrench,
            face: c.pathNodeReviewFill,
            ink: c.pathNodeReviewIcon,
            lip: c.pathNodeReviewLip,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.pitStopTitle,
                  style: PindoroType.titleMd.copyWith(color: c.textPrimary),
                ),
                Text(
                  l10n.homePitStopDue(due),
                  style: PindoroType.bodySm.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
          PindoroButton(
            label: l10n.homePitStopReview,
            variant: PindoroButtonVariant.secondary,
            onPressed: onReview,
          ),
        ],
      ),
    );
  }
}
