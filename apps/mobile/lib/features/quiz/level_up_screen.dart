import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pindoro_design/pindoro_design.dart';

import '../../app/format.dart';
import '../../app/page_scaffold.dart';

/// The full-screen level-up moment over cobalt: rays, the shield with the new
/// number, Pindo, the total and what comes next. Several levels crossed in one
/// round play once, with the final level.
class LevelUpScreen extends StatelessWidget {
  const LevelUpScreen({super.key, required this.level, required this.totalXp});

  final int level;
  final int totalXp;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    return Scaffold(
      backgroundColor: c.levelBg,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _Rays(c.levelText.withValues(alpha: 0.08)),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const Spacer(),
                LevelBadge(level, size: 120),
                const SizedBox(height: PindoroSpace.s4),
                const Pindo(PindoExpression.cheering, height: 104),
                const SizedBox(height: PindoroSpace.s4),
                Semantics(
                  header: true,
                  liveRegion: true,
                  child: Text(
                    l10n.levelUpTitle(level),
                    style: PindoroType.displayMd.copyWith(color: c.levelText),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PindoroSpace.s6,
                    vertical: PindoroSpace.s2,
                  ),
                  child: Text(
                    l10n.levelUpBody(formatNumber(totalXp)),
                    textAlign: TextAlign.center,
                    style: PindoroType.bodyLg.copyWith(color: c.levelText),
                  ),
                ),
                const SizedBox(height: PindoroSpace.s4),
                LipBox(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PindoroSpace.s4,
                    vertical: PindoroSpace.s3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: PindoroSpace.s3,
                    children: [
                      LevelBadge(level + 1, size: 32),
                      Text(
                        l10n.levelUpNext(level + 1),
                        style: PindoroType.titleSm.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    PindoroSpace.s4,
                    0,
                    PindoroSpace.s4,
                    bottomActionGap(context) -
                        MediaQuery.paddingOf(context).bottom,
                  ),
                  child: PindoroButton(
                    label: l10n.commonContinue,
                    variant: PindoroButtonVariant.reward,
                    hero: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sixteen rays from the shield.
class _Rays extends CustomPainter {
  _Rays(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.32);
    final reach = size.longestSide;
    final paint = Paint()..color = color;
    const rays = 16;
    for (var i = 0; i < rays; i += 2) {
      final a = 2 * math.pi * i / rays;
      final b = 2 * math.pi * (i + 1) / rays;
      canvas.drawPath(
        Path()
          ..moveTo(center.dx, center.dy)
          ..lineTo(
            center.dx + reach * math.cos(a),
            center.dy + reach * math.sin(a),
          )
          ..lineTo(
            center.dx + reach * math.cos(b),
            center.dy + reach * math.sin(b),
          )
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Rays old) => old.color != color;
}
