import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../generated/pindoro_tokens.dart';
import 'render_png.dart';

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
    return renderPng(size, pixelRatio, (canvas) {
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
      painter
        ..paint(
          canvas,
          Offset(PindoroSpace.s3 + checkSize + gap, PindoroSpace.s1),
        )
        ..dispose();
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
      ..color = c.mapVectorLand
      ..style = PaintingStyle.stroke
      ..strokeWidth = halo
      ..strokeJoin = StrokeJoin.round,
  );
  final fill = painter(Paint()..color = c.textSecondary);
  return renderPng(
    Size(fill.width + 2 * halo, fill.height + 2 * halo),
    pixelRatio,
    (canvas) {
      for (final painter in [outline, fill]) {
        painter
          ..paint(canvas, const Offset(halo, halo))
          ..dispose();
      }
    },
  );
}
