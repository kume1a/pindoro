import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'motion.dart';

enum DistrictProgress {
  notStarted,
  inProgress,
  complete;

  /// Fill (none before any street is known) and outline in [c].
  (Color? fill, Color stroke) colorsIn(PindoroColors c) => switch (this) {
    notStarted => (null, c.mapRegionOutline),
    inProgress => (c.mapDistrictProgressFill, c.mapDistrictProgressStroke),
    complete => (c.mapDistrictMasteredFill, c.mapDistrictMasteredStroke),
  };
}

typedef MiniMapDistrict = ({
  List<List<Polyline>> boundary,
  DistrictProgress progress,
});

/// The city's districts filling in as streets become known: outline when not
/// started, yellow in progress, cobalt complete. Decorative; rows beside it
/// carry the same data.
class DistrictMiniMap extends StatelessWidget {
  const DistrictMiniMap({super.key, required this.districts});

  final List<MiniMapDistrict> districts;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(PindoroRadius.lg),
      child: SizedBox(
        height: 120,
        width: double.infinity,
        child: CustomPaint(
          painter: _DistrictPainter(
            colors: PindoroTheme.of(context).colors,
            districts: districts,
          ),
        ),
      ),
    ),
  );
}

class _DistrictPainter extends CustomPainter {
  _DistrictPainter({required this.colors, required this.districts});

  final PindoroColors colors;
  final List<MiniMapDistrict> districts;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.mapBasemapLand);
    final points = [
      for (final d in districts)
        for (final polygon in d.boundary)
          for (final ring in polygon) ...ring,
    ];
    if (points.isEmpty) return;
    final box = Bbox.of(points);
    // Equirectangular with the latitude's cosine, fitted and centred.
    final kx = math.cos(box.center.lat * math.pi / 180);
    final w = (box.maxLon - box.minLon) * kx, h = box.maxLat - box.minLat;
    final scale =
        0.92 *
        (size.width / w < size.height / h ? size.width / w : size.height / h);
    final dx = (size.width - w * scale) / 2, dy = (size.height - h * scale) / 2;
    Offset at(LatLng p) => Offset(
      dx + (p.lon - box.minLon) * kx * scale,
      dy + (box.maxLat - p.lat) * scale,
    );
    for (final d in districts) {
      final (fill, stroke) = d.progress.colorsIn(colors);
      final width = d.progress == DistrictProgress.notStarted ? 1.5 : 2.0;
      for (final polygon in d.boundary) {
        final path = Path()..fillType = PathFillType.evenOdd;
        for (final ring in polygon) {
          path.addPolygon([for (final p in ring) at(p)], true);
        }
        if (fill != null) canvas.drawPath(path, Paint()..color = fill);
        canvas.drawPath(
          path,
          Paint()
            ..color = stroke
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DistrictPainter old) =>
      old.colors != colors || old.districts != districts;
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
        color: c.xpTrack,
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
              color: c.xpFill,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }
}

/// A [DistrictMiniMap] colour square: with [label] in the legend, alone
/// (and larger) before a district's row.
class Swatch extends StatelessWidget {
  const Swatch({super.key, required this.progress, this.label, this.size = 12});

  final DistrictProgress progress;
  final String? label;
  final double size;

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
            style: PindoroType.labelMd.copyWith(color: c.textSecondary),
          ),
        ),
      ],
    );
  }
}
