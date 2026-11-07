import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The play circle in the middle of the map: dashed cobalt outline, centre
/// dot, radius pill and a resize handle on the right edge.
class CircleOverlay extends StatelessWidget {
  const CircleOverlay({
    super.key,
    required this.radiusPx,
    required this.label,
    required this.onResize,
  });

  final double radiusPx;
  final String label;

  /// The new radius in logical pixels.
  final ValueChanged<double> onResize;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final center = box.biggest.center(Offset.zero);
      final colors = PindoroTheme.of(context).colors;
      return Stack(
        children: [
          IgnorePointer(
            child: CustomPaint(
              size: box.biggest,
              painter: _ShapePainter(
                colors: colors,
                rect: Rect.fromCircle(center: center, radius: radiusPx),
                circle: true,
              ),
            ),
          ),
          Positioned(
            left: center.dx - 60,
            width: 120,
            top: center.dy - radiusPx - 18,
            child: IgnorePointer(
              child: Center(child: Pill(label: label)),
            ),
          ),
          _Handle(
            at: center + Offset(radiusPx, 0),
            onDrag: (p) => onResize((p - center).distance),
          ),
        ],
      );
    },
  );
}

/// The play rectangle with a size pill and four corner handles.
class RectOverlay extends StatelessWidget {
  const RectOverlay({
    super.key,
    required this.size,
    required this.label,
    required this.onResize,
  });

  final Size size;
  final String label;

  /// The new size in logical pixels (symmetric about the centre).
  final ValueChanged<Size> onResize;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final center = box.biggest.center(Offset.zero);
      final rect = Rect.fromCenter(
        center: center,
        width: size.width,
        height: size.height,
      );
      final colors = PindoroTheme.of(context).colors;
      void drag(Offset p) => onResize(
        Size(2 * (p.dx - center.dx).abs(), 2 * (p.dy - center.dy).abs()),
      );
      return Stack(
        children: [
          IgnorePointer(
            child: CustomPaint(
              size: box.biggest,
              painter: _ShapePainter(colors: colors, rect: rect, circle: false),
            ),
          ),
          Positioned(
            left: center.dx - 80,
            width: 160,
            top: rect.top - 18,
            child: IgnorePointer(
              child: Center(child: Pill(label: label)),
            ),
          ),
          for (final corner in [
            rect.topLeft,
            rect.topRight,
            rect.bottomLeft,
            rect.bottomRight,
          ])
            _Handle(at: corner, onDrag: drag),
        ],
      );
    },
  );
}

/// A 48 dp target with a 20 dp white dot in a 3 dp cobalt ring. A drag adds
/// up its movement from where it started: [at] snaps to the shape's steps, so
/// following it would drop every move too small for one step.
class _Handle extends StatefulWidget {
  const _Handle({required this.at, required this.onDrag});

  final Offset at;
  final ValueChanged<Offset> onDrag;

  @override
  State<_Handle> createState() => _HandleState();
}

class _HandleState extends State<_Handle> {
  Offset _dragged = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final colors = PindoroTheme.of(context).colors;
    return Positioned(
      left: widget.at.dx - PindoroSize.tapMin / 2,
      top: widget.at.dy - PindoroSize.tapMin / 2,
      child: GestureDetector(
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (_) => _dragged = widget.at,
        onPanUpdate: (d) => widget.onDrag(_dragged += d.delta),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpLeftDownRight,
          child: SizedBox.square(
            dimension: PindoroSize.tapMin,
            child: Center(
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: colors.mapPlayerHalo,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.mapAreaStroke,
                    width: PindoroStroke.thick,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShapePainter extends CustomPainter {
  _ShapePainter({
    required this.colors,
    required this.rect,
    required this.circle,
  });

  final PindoroColors colors;
  final Rect rect;
  final bool circle;

  @override
  void paint(Canvas canvas, Size size) {
    final path = circle ? (Path()..addOval(rect)) : (Path()..addRect(rect));
    canvas.drawPath(path, Paint()..color = colors.mapAreaFill);
    final stroke = Paint()
      ..color = colors.mapAreaStroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = PindoroStroke.base;
    // Dashed 6/5 outline.
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 11) {
        canvas.drawPath(metric.extractPath(d, d + 6), stroke);
      }
    }
    if (circle) {
      canvas
        ..drawCircle(rect.center, 7, Paint()..color = colors.mapPlayerHalo)
        ..drawCircle(rect.center, 5, Paint()..color = colors.mapAreaCenter);
    }
  }

  @override
  bool shouldRepaint(_ShapePainter old) =>
      old.rect != rect || old.colors != colors || old.circle != circle;
}
