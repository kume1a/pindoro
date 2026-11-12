import 'dart:math' as math;

import 'package:flutter/rendering.dart';

/// A progress ring: a [track] circle under a round-capped [fill] arc from
/// 12 o'clock that goes [value] (clamped to 0–1) of the way round. The ring's
/// [stroke] sits [inset] inside the painted box.
class RingPainter extends CustomPainter {
  const RingPainter({
    required this.value,
    required this.stroke,
    required this.track,
    required this.fill,
    this.inset = 0,
  });

  final double value;
  final double stroke;
  final Color track;
  final Color fill;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final circle = (Offset.zero & size).deflate(stroke / 2 + inset);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawOval(circle, paint..color = track);
    final sweep = value.clamp(0.0, 1.0);
    if (sweep <= 0) return;
    canvas.drawArc(
      circle,
      -math.pi / 2,
      2 * math.pi * sweep,
      false,
      paint
        ..color = fill
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.value != value ||
      old.stroke != stroke ||
      old.track != track ||
      old.fill != fill ||
      old.inset != inset;
}

/// A triangle tail for bubbles, pointing down or up.
class TailPainter extends CustomPainter {
  const TailPainter(this.color, {required this.down});

  final Color color;
  final bool down;

  @override
  void paint(Canvas canvas, Size size) {
    final path = down
        ? (Path()
            ..moveTo(0, 0)
            ..lineTo(size.width, 0)
            ..lineTo(size.width / 2, size.height))
        : (Path()
            ..moveTo(0, size.height)
            ..lineTo(size.width, size.height)
            ..lineTo(size.width / 2, 0));
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(TailPainter old) => old.color != color || old.down != down;
}
