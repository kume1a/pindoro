import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../generated/pindoro_tokens.dart';
import 'render_png.dart';

/// The brand pin: a round head on a short point, on a lip. [halo] adds the
/// player pin's white outline; a [letter] replaces the dot (in the dot's
/// colour) and [outline] rims the face. The tip, at the bottom centre, is
/// the point.
class PinMark extends StatelessWidget {
  const PinMark({
    super.key,
    required this.face,
    required this.lip,
    required this.dot,
    this.halo,
    this.letter,
    this.outline,
    this.width = PindoroSize.pinPlayer,
  });

  /// A road trip's A or B (`.pd-pin--endpoint`): route paint on its casing,
  /// the letter in route-arrow ink.
  factory PinMark.endpoint(String letter, PindoroColors c) => PinMark(
    face: c.mapRouteLine,
    lip: c.mapRouteCasing,
    outline: c.mapRouteCasing,
    dot: c.mapRouteArrow,
    letter: letter,
  );

  final Color face;
  final Color lip;
  final Color dot;
  final Color? halo;
  final String? letter;
  final Color? outline;
  final double width;

  /// The pin's 40 × 46 shape (head r16, tip 26 below the centre, 4 dp
  /// lip) plus 2 units on each side for the halo.
  static const double gridWidth = 44;
  static const double gridHeight = 50;

  /// The tip sits this far above the bottom edge (the halo below it).
  static const double tipInset = 2;

  Size get size => Size(width, width * gridHeight / gridWidth);

  @override
  Widget build(BuildContext context) => Semantics(
    label: letter,
    child: CustomPaint(size: size, painter: _painter),
  );

  _PinPainter get _painter => _PinPainter(
    face: face,
    lip: lip,
    dot: dot,
    halo: halo,
    letter: letter,
    outline: outline,
  );

  /// PNG of this pin at [pixelRatio], with room for the halo; the tip sits
  /// at the bottom centre (for map symbol layers anchored at the bottom).
  Future<Uint8List> toPng(double pixelRatio) =>
      renderPng(size, pixelRatio, (canvas) => _painter.paint(canvas, size));
}

class _PinPainter extends CustomPainter {
  _PinPainter({
    required this.face,
    required this.lip,
    required this.dot,
    this.halo,
    this.letter,
    this.outline,
  });

  final Color face;
  final Color lip;
  final Color dot;
  final Color? halo;
  final String? letter;
  final Color? outline;

  /// `.pd-pin-text`: 900 weight, 15 units on the 40-unit pin.
  static const double _letterSize = 15;

  /// Head radius 16 centred at (22, 18 + [dy]), tip 26 below the centre.
  static Path _shape(double dy) {
    const cx = 22.0, r = 16.0, tipDrop = 26.0;
    final cy = 18.0 + dy;
    final tip = Offset(cx, cy + tipDrop);
    final angle = math.acos(r / tipDrop);
    final left = Offset(cx - r * math.sin(angle), cy + r * math.cos(angle));
    return Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..arcTo(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        math.pi / 2 + angle,
        2 * math.pi - 2 * angle,
        false,
      )
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / PinMark.gridWidth);
    final facePath = _shape(0);
    final lipPath = _shape(PindoroElevation.e2);
    if (halo != null) {
      final stroke = Paint()
        ..color = halo!
        ..style = PaintingStyle.stroke
        ..strokeWidth = PindoroStroke.base * 2
        ..strokeJoin = StrokeJoin.round;
      canvas
        ..drawPath(facePath, stroke)
        ..drawPath(lipPath, stroke);
    }
    canvas
      ..drawPath(lipPath, Paint()..color = lip)
      ..drawPath(facePath, Paint()..color = face);
    if (outline != null) {
      canvas.drawPath(
        facePath,
        Paint()
          ..color = outline!
          ..style = PaintingStyle.stroke
          ..strokeWidth = PindoroStroke.base,
      );
    }
    final letter = this.letter;
    if (letter == null) {
      canvas.drawCircle(const Offset(22, 18), 6, Paint()..color = dot);
      return;
    }
    final text = TextPainter(
      text: TextSpan(
        text: letter,
        style: PindoroType.labelLg.copyWith(
          color: dot,
          fontSize: _letterSize,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, Offset(22 - text.width / 2, 18 - text.height / 2));
    text.dispose();
  }

  @override
  bool shouldRepaint(_PinPainter old) =>
      old.face != face ||
      old.lip != lip ||
      old.dot != dot ||
      old.halo != halo ||
      old.letter != letter ||
      old.outline != outline;
}
