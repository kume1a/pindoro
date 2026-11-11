import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'district_map.dart';
import 'graphics.dart';
import 'surfaces.dart';

/// A badge's shield (component Badge): a `color.badge.rim` rim, the coloured
/// [field] inset in it and one [glyph] in white. [locked] draws the locked
/// stop's colours and a lock instead. [size] is its width; it is 100 / 88 as
/// tall.
class BadgeShield extends StatelessWidget {
  const BadgeShield({
    super.key,
    required this.glyph,
    required this.field,
    this.locked = false,
    this.size = 76,
  });

  final PindoroGlyph glyph;
  final Color field;
  final bool locked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final face = locked ? c.pathNodeLockedFill : field;
    // The design draws the shield in an 88 × 100 box.
    final k = size / 88;
    return SizedBox(
      width: size,
      height: 100 * k,
      child: CustomPaint(
        painter: _ShieldPainter(
          rim: locked ? c.pathNodeLockedLip : c.badgeRim,
          field: face,
        ),
        child: Stack(
          children: [
            // The design's glyph: 24 dp at 1.5 ×, from (26, 28).
            Positioned(
              left: 26 * k,
              top: 28 * k,
              child: PindoroIcon(
                locked ? PindoroGlyph.lock : glyph,
                size: 36 * k,
                color: locked ? c.pathNodeLockedIcon : c.textOnColor,
                cut: face,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  _ShieldPainter({required this.rim, required this.field});

  final Color rim;
  final Color field;

  // The design's two shield paths (viewBox 88 × 100), scaled by k.
  static Path _outer(double k) => Path()
    ..moveTo(44 * k, 2 * k)
    ..lineTo(84 * k, 18 * k)
    ..lineTo(84 * k, 48 * k)
    ..cubicTo(84 * k, 74 * k, 66 * k, 90 * k, 44 * k, 98 * k)
    ..cubicTo(22 * k, 90 * k, 4 * k, 74 * k, 4 * k, 48 * k)
    ..lineTo(4 * k, 18 * k)
    ..close();

  static Path _inner(double k) => Path()
    ..moveTo(44 * k, 10 * k)
    ..lineTo(76 * k, 23 * k)
    ..lineTo(76 * k, 48 * k)
    ..cubicTo(76 * k, 69 * k, 62 * k, 82 * k, 44 * k, 89 * k)
    ..cubicTo(26 * k, 82 * k, 12 * k, 69 * k, 12 * k, 48 * k)
    ..lineTo(12 * k, 23 * k)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 88;
    canvas
      ..drawPath(_outer(k), Paint()..color = rim)
      ..drawPath(_inner(k), Paint()..color = field);
  }

  @override
  bool shouldRepaint(_ShieldPainter old) =>
      old.rim != rim || old.field != field;
}

/// A badge on the shelf (component Badge): its 56 dp shield, name and
/// condition on a raised card. A locked badge counting toward its target
/// shows [progress] (0–1) in a mini bar; [newLabel] shows the New pill.
/// Reads as one label, [semanticLabel].
class BadgeTile extends StatelessWidget {
  const BadgeTile({
    super.key,
    required this.glyph,
    required this.field,
    required this.name,
    required this.condition,
    required this.semanticLabel,
    this.locked = false,
    this.progress,
    this.newLabel,
  });

  final PindoroGlyph glyph;
  final Color field;
  final String name;
  final String condition;
  final String semanticLabel;
  final bool locked;
  final double? progress;
  final String? newLabel;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final progress = this.progress;
    final newLabel = this.newLabel;
    return Semantics(
      container: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Stack(
        children: [
          // The card fills its slot even when its text is narrower.
          SizedBox(
            width: double.infinity,
            child: LipBox(
              border: c.lineBase,
              radius: PindoroRadius.lg,
              padding: const EdgeInsets.symmetric(
                horizontal: PindoroSpace.s2,
                vertical: PindoroSpace.s3,
              ),
              child: Column(
                spacing: 2,
                children: [
                  BadgeShield(
                    glyph: glyph,
                    field: field,
                    locked: locked,
                    size: 56,
                  ),
                  const SizedBox(height: PindoroSpace.s1),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: PindoroType.titleSm.copyWith(
                      color: locked ? c.textSecondary : c.textPrimary,
                    ),
                  ),
                  Text(
                    condition,
                    textAlign: TextAlign.center,
                    style: PindoroType.bodySm.copyWith(color: c.textSecondary),
                  ),
                  if (progress != null)
                    Padding(
                      padding: const EdgeInsets.only(top: PindoroSpace.s1),
                      child: Minibar(value: progress),
                    ),
                ],
              ),
            ),
          ),
          if (newLabel != null)
            PositionedDirectional(
              top: PindoroSpace.s2,
              end: PindoroSpace.s2,
              child: Container(
                // The design's pill: 1 × 7 dp around label.sm.
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: c.accentBase,
                  borderRadius: BorderRadius.circular(PindoroRadius.full),
                ),
                child: Text(
                  newLabel,
                  style: PindoroType.labelSm.copyWith(color: c.accentOn),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
