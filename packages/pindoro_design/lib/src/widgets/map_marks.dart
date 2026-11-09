import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';
import 'graphics.dart';

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
      _png(size, pixelRatio, (canvas) => _painter.paint(canvas, size));
}

/// [glyph] at [size] dp as a PNG for map symbol layers (the route chevrons).
Future<Uint8List> glyphPng(
  PindoroGlyph glyph, {
  required Color ink,
  required Color cut,
  required double size,
  required double pixelRatio,
}) async {
  final icon = await glyphPicture(glyph, ink: ink, cut: cut);
  try {
    return await _png(Size.square(size), pixelRatio, (canvas) {
      canvas
        ..scale(size / icon.size.width)
        ..drawPicture(icon.picture);
    });
  } finally {
    icon.picture.dispose();
  }
}

/// The road-trip replay's car (`.pd-map-car`): a route-arrow disc with the
/// car in route paint, on a white halo, as a PNG centred on its point.
class CarMark {
  const CarMark(this.colors);

  final PindoroColors colors;

  static const double size = PindoroSize.iconLg + 2 * PindoroStroke.base;

  Future<Uint8List> toPng(double pixelRatio) async {
    final car = await glyphPicture(
      PindoroGlyph.car,
      ink: colors.mapRouteLine,
      cut: colors.mapRouteArrow,
    );
    try {
      return await _png(const Size.square(size), pixelRatio, (canvas) {
        const centre = Offset(size / 2, size / 2);
        const inset = (size - PindoroSize.iconSm) / 2;
        canvas
          ..drawCircle(centre, size / 2, Paint()..color = colors.mapPlayerHalo)
          ..drawCircle(
            centre,
            PindoroSize.iconLg / 2,
            Paint()..color = colors.mapRouteArrow,
          )
          ..translate(inset, inset)
          ..scale(PindoroSize.iconSm / car.size.width)
          ..drawPicture(car.picture);
      });
    } finally {
      car.picture.dispose();
    }
  }
}

/// A map label (an area's name, the reveal's distance) as a PNG for map
/// symbol layers: the label on a pill face over a lip, with an optional
/// check in front. Map styles carry no fonts, so labels are drawn here.
class MapChip {
  const MapChip({
    required this.label,
    required this.style,
    required this.face,
    required this.lip,
    required this.text,
    this.check = false,
  });

  /// An unpicked area's name chip on the area picker.
  factory MapChip.region(String label, PindoroColors c) => MapChip(
    label: label,
    style: PindoroType.labelMd,
    face: c.mapRegionLabelBg,
    lip: c.lineBase,
    text: c.mapRegionLabelText,
  );

  /// A picked area's name chip: cobalt, with a check.
  factory MapChip.picked(String label, PindoroColors c) => MapChip(
    label: label,
    style: PindoroType.labelMd,
    face: c.mapAreaLabelBg,
    lip: c.mapAreaLabelLip,
    text: c.mapAreaLabelText,
    check: true,
  );

  /// The reveal's distance chip on the measure line ("764 m").
  factory MapChip.distance(String label, PindoroColors c) => MapChip(
    label: label,
    style: PindoroType.numericSm,
    face: c.mapMeasureLabel,
    lip: c.mapMeasureLine,
    text: c.mapMeasureLabelText,
  );

  final String label;
  final TextStyle style;
  final Color face;
  final Color lip;
  final Color text;
  final bool check;

  Future<Uint8List> toPng(double pixelRatio) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: style.copyWith(color: text),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final checkSize = check ? style.fontSize! : 0.0;
    final gap = check ? PindoroSpace.s1 : 0.0;
    final faceHeight = painter.height + 2 * PindoroSpace.s1;
    final size = Size(
      painter.width + checkSize + gap + 2 * PindoroSpace.s3,
      faceHeight + PindoroElevation.e1,
    );
    final radius = Radius.circular(faceHeight / 2);
    return _png(size, pixelRatio, (canvas) {
      canvas
        ..drawRRect(
          RRect.fromLTRBR(
            0,
            PindoroElevation.e1,
            size.width,
            size.height,
            radius,
          ),
          Paint()..color = lip,
        )
        ..drawRRect(
          RRect.fromLTRBR(0, 0, size.width, faceHeight, radius),
          Paint()..color = face,
        );
      if (check) {
        final x = PindoroSpace.s3;
        final y = faceHeight / 2;
        canvas.drawPath(
          Path()
            ..moveTo(x + checkSize * 0.1, y)
            ..lineTo(x + checkSize * 0.4, y + checkSize * 0.3)
            ..lineTo(x + checkSize * 0.95, y - checkSize * 0.3),
          Paint()
            ..color = text
            ..style = PaintingStyle.stroke
            ..strokeWidth = PindoroStroke.base
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
      painter.paint(
        canvas,
        Offset(PindoroSpace.s3 + checkSize + gap, PindoroSpace.s1),
      );
    });
  }
}

/// A district's name as small grey map text with a land-coloured halo, as a
/// PNG for a symbol layer placed along the district's outline.
Future<Uint8List> outlineLabelPng(
  String label,
  PindoroColors c,
  double pixelRatio,
) {
  TextPainter painter(Paint paint) => TextPainter(
    text: TextSpan(
      text: label,
      style: PindoroType.labelSm.copyWith(foreground: paint),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  const halo = PindoroStroke.thick;
  final outline = painter(
    Paint()
      ..color = c.mapBasemapLand
      ..style = PaintingStyle.stroke
      ..strokeWidth = halo
      ..strokeJoin = StrokeJoin.round,
  );
  final fill = painter(Paint()..color = c.textSecondary);
  return _png(Size(fill.width + 2 * halo, fill.height + 2 * halo), pixelRatio, (
    canvas,
  ) {
    outline.paint(canvas, const Offset(halo, halo));
    fill.paint(canvas, const Offset(halo, halo));
  });
}

Future<Uint8List> _png(
  Size size,
  double pixelRatio,
  void Function(Canvas canvas) paint,
) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder)..scale(pixelRatio));
  final image = await recorder.endRecording().toImage(
    (size.width * pixelRatio).ceil(),
    (size.height * pixelRatio).ceil(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
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
