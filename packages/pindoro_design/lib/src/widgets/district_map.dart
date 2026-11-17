import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'motion.dart';

/// How much of a district is in memory (District fills): outline only, a
/// yellow wash under [progressShare], the progress fill from it, cobalt once
/// Mastered.
enum DistrictProgress {
  notStarted,
  started,
  inProgress,
  complete;

  /// The share of a district's streets in memory from which it takes the
  /// progress fill.
  static const double progressShare = 0.25;

  /// The step for [share] of a district's streets in memory.
  static DistrictProgress of(double share, {required bool mastered}) => mastered
      ? complete
      : share <= 0
      ? notStarted
      : share < progressShare
      ? started
      : inProgress;

  /// Fill (none before any street is in memory) and outline in [c].
  (Color? fill, Color stroke) colorsIn(PindoroColors c) => switch (this) {
    notStarted => (null, c.mapRegionOutline),
    started => (c.mapDistrictStartedFill, c.mapDistrictProgressStroke),
    inProgress => (c.mapDistrictProgressFill, c.mapDistrictProgressStroke),
    complete => (c.mapDistrictMasteredFill, c.mapDistrictMasteredStroke),
  };
}

/// A district on [DistrictMap]: its outline, fill step and name.
typedef MapDistrict = ({
  List<List<Polyline>> boundary,
  DistrictProgress progress,
  String name,
  LatLng labelAt,
});

/// Equirectangular with the latitude's cosine, fitting [points] centred in
/// [size] at [fill] of the room.
Offset Function(LatLng) _fit(List<LatLng> points, Size size, double fill) {
  final box = Bbox.of(points);
  final kx = math.cos(box.center.lat * math.pi / 180);
  final w = math.max((box.maxLon - box.minLon) * kx, 1e-9);
  final h = math.max(box.maxLat - box.minLat, 1e-9);
  final scale = fill * math.min(size.width / w, size.height / h);
  final dx = (size.width - w * scale) / 2, dy = (size.height - h * scale) / 2;
  return (p) => Offset(
    dx + (p.lon - box.minLon) * kx * scale,
    dy + (box.maxLat - p.lat) * scale,
  );
}

Path _polygonPath(List<Polyline> polygon, Offset Function(LatLng) at) {
  final path = Path()..fillType = PathFillType.evenOdd;
  for (final ring in polygon) {
    path.addPolygon([for (final p in ring) at(p)], true);
  }
  return path;
}

Paint _line(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeJoin = StrokeJoin.round
  ..strokeCap = StrokeCap.round;

/// The city's districts in their fill steps on the land colour, each named
/// at its label point (District map, Progress). A tap on a district calls
/// [onTap] with its index. One screen-reader node, [semanticsLabel]; rows
/// beside it carry the same data. [overlay] sits over the map (attribution).
class DistrictMap extends StatelessWidget {
  const DistrictMap({
    super.key,
    required this.districts,
    required this.semanticsLabel,
    this.height = 220,
    this.onTap,
    this.overlay,
  });

  final List<MapDistrict> districts;
  final String semanticsLabel;
  final double height;
  final ValueChanged<int>? onTap;
  final Widget? overlay;

  static const double _fill = 0.92;

  List<(int, Path)> _paths(Size size) {
    final at = _fit(
      [
        for (final d in districts)
          for (final polygon in d.boundary)
            for (final ring in polygon) ...ring,
      ],
      size,
      _fill,
    );
    return [
      for (final (i, d) in districts.indexed)
        for (final polygon in d.boundary) (i, _polygonPath(polygon, at)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final overlay = this.overlay;
    return Semantics(
      image: true,
      label: semanticsLabel,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PindoroRadius.lg),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, box) {
              final size = box.biggest;
              final empty = districts.every((d) => d.boundary.isEmpty);
              return Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: onTap == null || empty
                          ? null
                          : (details) {
                              for (final (i, path) in _paths(size)) {
                                if (path.contains(details.localPosition)) {
                                  onTap!(i);
                                  return;
                                }
                              }
                            },
                      child: CustomPaint(
                        painter: _DistrictPainter(
                          colors: c,
                          districts: districts,
                          paths: empty ? const [] : _paths(size),
                          label: PindoroType.labelSm,
                        ),
                      ),
                    ),
                  ),
                  ?overlay,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DistrictPainter extends CustomPainter {
  _DistrictPainter({
    required this.colors,
    required this.districts,
    required this.paths,
    required this.label,
  });

  final PindoroColors colors;
  final List<MapDistrict> districts;
  final List<(int, Path)> paths;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.mapVectorLand);
    if (paths.isEmpty) return;
    // Each district is a tile: its fill, a coloured edge kept inside it, then
    // a land-coloured gap along every border, so no neighbour draws over it.
    for (final (i, path) in paths) {
      final (fill, stroke) = districts[i].progress.colorsIn(colors);
      canvas.drawPath(
        path,
        Paint()..color = fill ?? colors.mapDistrictLockedFill,
      );
      if (districts[i].progress != DistrictProgress.notStarted) {
        canvas
          ..save()
          ..clipPath(path)
          ..drawPath(path, _line(stroke, 5))
          ..restore();
      }
    }
    for (final (_, path) in paths) {
      canvas.drawPath(path, _line(colors.mapVectorLand, 1.5));
    }
    final at = _fit(
      [
        for (final d in districts)
          for (final polygon in d.boundary)
            for (final ring in polygon) ...ring,
      ],
      size,
      DistrictMap._fill,
    );
    for (final (i, d) in districts.indexed) {
      final room = paths
          .where((p) => p.$1 == i)
          .map((p) => p.$2.getBounds())
          .fold(Rect.zero, (a, b) => a.isEmpty ? b : a.expandToInclude(b));
      final halo = TextPainter(
        text: TextSpan(
          text: d.name,
          style: label.copyWith(foreground: _line(colors.mapVectorLand, 3)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final text = TextPainter(
        text: TextSpan(
          text: d.name,
          style: label.copyWith(color: colors.textPrimary),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // A name wider than its district would sit on its neighbours.
      if (text.width > room.width) continue;
      final centre = at(d.labelAt) - Offset(text.width / 2, text.height / 2);
      halo.paint(canvas, centre);
      text.paint(canvas, centre);
    }
  }

  @override
  bool shouldRepaint(_DistrictPainter old) =>
      old.colors != colors || old.districts != districts;
}

/// A neighbourhood at card size (Neighbourhood card's mini map): the land
/// colour, the [streets] the player knows traced in `color.map.region.outline`
/// at `opacity.street-trace`, and the [area] as the dashed cobalt play-area
/// outline over its fill. No names. Decorative.
class AreaMiniMap extends StatelessWidget {
  const AreaMiniMap({
    super.key,
    required this.area,
    this.streets = const [],
    this.size = 104,
  });

  final List<List<Polyline>> area;
  final List<Polyline> streets;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(PindoroRadius.md),
      child: CustomPaint(
        size: Size.square(size),
        painter: _AreaPainter(
          colors: PindoroTheme.of(context).colors,
          area: area,
          streets: streets,
        ),
      ),
    ),
  );
}

class _AreaPainter extends CustomPainter {
  _AreaPainter({
    required this.colors,
    required this.area,
    required this.streets,
  });

  final PindoroColors colors;
  final List<List<Polyline>> area;
  final List<Polyline> streets;

  static const double _fill = 0.8;
  static const double _street = 4;
  static const double _dash = 8;
  static const double _gap = 6;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.mapVectorLand);
    final outline = [
      for (final polygon in area)
        for (final ring in polygon) ...ring,
    ];
    if (outline.isEmpty) return;
    final at = _fit(outline, size, _fill);
    final trace = _line(
      colors.mapRegionOutline.withValues(alpha: PindoroOpacity.streetTrace),
      _street,
    );
    for (final street in streets) {
      if (street.length < 2) continue;
      canvas.drawPath(
        Path()..addPolygon([for (final p in street) at(p)], false),
        trace,
      );
    }
    final stroke = _line(colors.mapAreaStroke, PindoroStroke.thick);
    for (final polygon in area) {
      final path = _polygonPath(polygon, at);
      canvas.drawPath(path, Paint()..color = colors.mapAreaFill);
      for (final metric in path.computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += _dash + _gap) {
          canvas.drawPath(metric.extractPath(d, d + _dash), stroke);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_AreaPainter old) =>
      old.colors != colors || old.area != area || old.streets != streets;
}

/// A 6 dp bar of a district's known streets.
class Minibar extends StatelessWidget {
  const Minibar({
    super.key,
    required this.value,
    this.from,
    this.delay = Duration.zero,
  });

  final double value;

  /// Grows from here to [value] after [delay] (`duration.slow`) on first
  /// build; null draws [value] as is.
  final double? from;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final (duration, curve) = delayedMotion(
      context,
      delay,
      PindoroMotion.durationSlow,
      PindoroMotion.easeStandard,
    );
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: c.progressTrack,
        borderRadius: BorderRadius.circular(3),
      ),
      alignment: Alignment.centerLeft,
      child: TweenAnimationBuilder<double>(
        tween: Tween(
          begin: (from ?? value).clamp(0, 1),
          end: value.clamp(0, 1),
        ),
        duration: from == null ? Duration.zero : duration,
        curve: curve,
        builder: (_, v, _) => FractionallySizedBox(
          widthFactor: v,
          child: Container(
            decoration: BoxDecoration(
              color: c.progressDone,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }
}

/// A [DistrictMap] colour square: with [label] in the legend, alone (and
/// larger) before a district's row. A [dense] legend sets its label in
/// `label.sm`, for a key over a map.
class Swatch extends StatelessWidget {
  const Swatch({
    super.key,
    required this.progress,
    this.label,
    this.size = 12,
    this.dense = false,
  });

  final DistrictProgress progress;
  final String? label;
  final double size;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final (fill, stroke) = progress.colorsIn(c);
    final label = this.label;
    final square = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill ?? c.surfaceRaised,
        border: Border.all(
          color: stroke,
          width: label == null ? PindoroStroke.thick : PindoroStroke.base,
        ),
        borderRadius: BorderRadius.circular(
          label == null ? PindoroRadius.xs : 3,
        ),
      ),
    );
    if (label == null) return square;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: PindoroSpace.s1,
      children: [
        square,
        Flexible(
          child: Text(
            label,
            style: (dense ? PindoroType.labelSm : PindoroType.labelMd).copyWith(
              color: c.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
