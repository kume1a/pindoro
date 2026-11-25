import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../generated/pindoro_tokens.dart';
import '../drive_glyph.dart';
import '../graphics.dart';
import 'render_png.dart';

/// [glyph] at [size] dp as a PNG for map symbol layers (the route chevrons).
Future<Uint8List> glyphPng(
  PindoroGlyph glyph, {
  required Color ink,
  required Color cut,
  required double size,
  required double pixelRatio,
}) async {
  final icon = await glyphPicture(glyph, ink: ink, cut: cut);
  return _picturePng(icon, size, pixelRatio);
}

/// [glyph] at [size] dp as a PNG for map symbol layers (Guided's traffic lights).
Future<Uint8List> driveGlyphPng(
  DriveGlyphName glyph, {
  required Color color,
  required Color cut,
  required double size,
  required double pixelRatio,
}) async {
  final icon = await vg.loadPicture(
    SvgStringLoader(driveGlyphSvg(glyph, color: color, cut: cut)),
    null,
  );
  return _picturePng(icon, size, pixelRatio);
}

/// [icon] drawn in a [size] dp square as a PNG; the picture is freed after.
Future<Uint8List> _picturePng(
  PictureInfo icon,
  double size,
  double pixelRatio,
) async {
  try {
    return await renderPng(Size.square(size), pixelRatio, (canvas) {
      canvas
        ..scale(size / icon.size.width)
        ..drawPicture(icon.picture);
    });
  } finally {
    icon.picture.dispose();
  }
}

/// A one-way street's arrow (the basemap's `oneway-arrows`): a hairline shaft
/// with an open head pointing right, along the road, as a 12 × 6 dp PNG.
Future<Uint8List> onewayArrowPng(Color color, double pixelRatio) {
  const size = Size(12, 6);
  const inset = PindoroStroke.hairline / 2;
  final headStart = size.width - 3.5;
  final mid = size.height / 2;
  return renderPng(size, pixelRatio, (canvas) {
    canvas.drawPath(
      Path()
        ..moveTo(inset, mid)
        ..lineTo(size.width - inset, mid)
        ..moveTo(headStart, inset)
        ..lineTo(size.width - inset, mid)
        ..lineTo(headStart, size.height - inset),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = PindoroStroke.hairline
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  });
}

/// The head of Guided's turn arrow on the map: a [fill] triangle pointing up
/// in a [casing] rim, as a 28 × 22 dp PNG whose bottom centre sits on the
/// arrow's end.
Future<Uint8List> turnArrowHeadPng({
  required Color fill,
  required Color casing,
  required double pixelRatio,
}) {
  const size = Size(28, 22);
  const rim = PindoroStroke.thick;
  final head = Path()
    ..moveTo(size.width / 2, rim)
    ..lineTo(size.width - rim, size.height - rim)
    ..lineTo(rim, size.height - rim)
    ..close();
  return renderPng(size, pixelRatio, (canvas) {
    canvas
      ..drawPath(
        head,
        Paint()
          ..color = casing
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * rim
          ..strokeJoin = StrokeJoin.round,
      )
      ..drawPath(head, Paint()..color = fill);
  });
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
      return await renderPng(const Size.square(size), pixelRatio, (canvas) {
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

/// Guided's car as a navigation arrow (the default): a cobalt arrowhead pointing up, its
/// right half in the lip shade, in a halo rim, as a 36 × 40 dp PNG centred on its point.
/// Laid flat on the map, it points along the road.
class ArrowMark {
  const ArrowMark(this.colors);

  final PindoroColors colors;

  static const Size size = Size(36, 40);

  Future<Uint8List> toPng(double pixelRatio) {
    const rim = PindoroStroke.thick;
    final tip = Offset(size.width / 2, rim);
    final notch = Offset(size.width / 2, size.height * 0.7);
    final left = Offset(rim, size.height - rim);
    final right = Offset(size.width - rim, size.height - rim);
    Path shape(List<Offset> points) => Path()..addPolygon(points, true);
    return renderPng(size, pixelRatio, (canvas) {
      canvas
        ..drawPath(
          shape([tip, right, notch, left]),
          Paint()
            ..color = colors.mapPlayerHalo
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * rim
            ..strokeJoin = StrokeJoin.round,
        )
        ..drawPath(
          shape([tip, notch, left]),
          Paint()..color = colors.mapPlayerPin,
        )
        ..drawPath(
          shape([tip, right, notch]),
          Paint()..color = colors.mapPlayerPinLip,
        );
    });
  }
}

/// A basemap landmark (a café, a church, a metro station): a disc in its
/// category [color] with the Maki [icon] in `color.map.poi.glyph`, rimmed in
/// the land colour, as a PNG centred on its point. Landmarks never get names.
class PoiMark {
  const PoiMark({
    required this.icon,
    required this.color,
    required this.colors,
  });

  final String icon;
  final Color color;
  final PindoroColors colors;

  static const double size = PindoroSize.iconSm;

  Future<Uint8List> toPng(double pixelRatio) async {
    final glyph = await mapIconPicture(icon);
    try {
      return await renderPng(const Size.square(size), pixelRatio, (canvas) {
        const centre = Offset(size / 2, size / 2);
        const inset = PindoroSpace.s1;
        canvas
          ..drawCircle(centre, size / 2, Paint()..color = colors.mapVectorLand)
          ..drawCircle(
            centre,
            size / 2 - PindoroStroke.base,
            Paint()..color = color,
          )
          // Maki draws in implicit black: tint whatever it paints.
          ..saveLayer(
            Offset.zero & const Size.square(size),
            Paint()
              ..colorFilter = ColorFilter.mode(
                colors.mapPoiGlyph,
                BlendMode.srcIn,
              ),
          )
          ..translate(inset, inset)
          ..scale((size - 2 * inset) / glyph.size.width)
          ..drawPicture(glyph.picture)
          ..restore();
      });
    } finally {
      glyph.picture.dispose();
    }
  }
}
