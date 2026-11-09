import 'package:flutter/material.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Dashed cobalt ring at the map centre: where a first tap would land.
class Reticle extends StatelessWidget {
  const Reticle({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      size: const Size.square(48),
      painter: _ReticlePainter(PindoroTheme.of(context).colors),
    ),
  );
}

class _ReticlePainter extends CustomPainter {
  _ReticlePainter(this.colors);

  final PindoroColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final ring = Paint()
      ..color = colors.mapReticle
      ..style = PaintingStyle.stroke
      ..strokeWidth = PindoroStroke.thick
      ..strokeCap = StrokeCap.round;
    const dashes = 12;
    final rect = Rect.fromCircle(center: center, radius: size.width / 2 - 2);
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(
        rect,
        i * 2 * 3.14159 / dashes,
        3.14159 / dashes,
        false,
        ring,
      );
    }
    canvas
      ..drawCircle(center, 6, Paint()..color = colors.mapPlayerHalo)
      ..drawCircle(center, 4, Paint()..color = colors.mapReticle);
  }

  @override
  bool shouldRepaint(_ReticlePainter old) => old.colors != colors;
}
