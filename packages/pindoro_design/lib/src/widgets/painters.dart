import 'package:flutter/rendering.dart';

/// [path] cut into pieces [dash] long, one every [period] along it.
Path dashedPath(Path path, {required double dash, required double period}) {
  final out = Path();
  for (final metric in path.computeMetrics()) {
    for (var d = 0.0; d < metric.length; d += period) {
      out.addPath(metric.extractPath(d, d + dash), Offset.zero);
    }
  }
  return out;
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
