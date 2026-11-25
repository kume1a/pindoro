import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'painters.dart';
import 'surfaces.dart';

/// A hint bubble over the map on the inverse surface; passes taps through.
class CoachBubble extends StatelessWidget {
  const CoachBubble({
    super.key,
    required this.title,
    this.body,
    this.pointsUp = false,
  });

  final String title;
  final String? body;

  /// A tail on top pointing at what the bubble explains, which sits above.
  final bool pointsUp;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: pointsUp
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomPaint(
                      size: const Size(18, 9),
                      painter: TailPainter(c.coachBg, down: false),
                    ),
                    _bubble(c),
                  ],
                )
              : _bubble(c),
        ),
      ),
    );
  }

  Widget _bubble(PindoroColors c) => LipBox(
    face: c.coachBg,
    lip: c.coachLip,
    lipHeight: PindoroElevation.e2,
    radius: PindoroRadius.lg,
    shadow: true,
    padding: const EdgeInsets.symmetric(
      horizontal: PindoroSpace.s4,
      vertical: PindoroSpace.s3,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: PindoroType.titleSm.copyWith(color: c.coachText)),
        if (body != null)
          Text(body!, style: PindoroType.bodySm.copyWith(color: c.coachText)),
      ],
    ),
  );
}
