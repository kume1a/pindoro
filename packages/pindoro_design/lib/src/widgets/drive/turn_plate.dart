import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../generated/pindoro_tokens.dart';
import '../../theme.dart';
import '../drive_glyph.dart';
import 'drive_parts.dart';

/// One lane of the road ahead (TurnPlate's [TurnPlate.lanes], left to right): its painted
/// arrows as turn angles in degrees (0 straight on, -90 left, 90 right, ±180 turning around)
/// and [use], the arrow to take in it; null when the lane doesn't go the way.
typedef DriveLane = ({List<double> arrowsDeg, double? use});

/// Guided's turn card, top left over the map (TurnPlate, the compact card of SPEC §16.23 item
/// 130): the [glyph] beside the [headline] (the distance to the turn), the [street] under them,
/// a small [note] with its [noteKind] badge (the landmark at the turn, the heading), the
/// [lanes] at the bottom; small [lead] lines above ("New route"), and the [then] chip under the
/// card. Announced once per change as [semanticsLabel]; takes no input.
class TurnPlate extends StatelessWidget {
  const TurnPlate({
    super.key,
    required this.semanticsLabel,
    this.lead = const [],
    this.glyph,
    this.headline,
    this.street,
    this.note,
    this.noteKind,
    this.lanes = const [],
    this.then,
    this.thenLabel,
  });

  final String semanticsLabel;
  final List<String> lead;
  final DriveGlyphName? glyph;
  final String? headline;
  final String? street;
  final String? note;
  final DriveGlyphName? noteKind;
  final List<DriveLane> lanes;
  final DriveGlyphName? then;
  final String? thenLabel;

  static const double glyphSize = 44;
  static const double _badge = 24;
  static const double _badgeGlyph = 16;
  static const double _thenGlyph = 24;

  /// The card's widest, as a share of the screen: the map keeps the rest.
  static const double _widthShare = 0.55;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final top = MediaQuery.paddingOf(context).top;
    final width = MediaQuery.sizeOf(context).width * _widthShare;
    final line = PindoroType.titleLg.copyWith(
      color: c.drivePlateText,
      height: 1.2,
    );
    final small = PindoroType.labelLg.copyWith(color: c.drivePlateText2);
    final glyph = this.glyph;
    final headline = this.headline;
    final then = this.then;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: c.drivePlate,
        borderRadius: BorderRadius.circular(PindoroRadius.lg),
        boxShadow: [plateShadow(c)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(PindoroSpace.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: PindoroSpace.s1,
          children: [
            for (final l in lead) Text(l, style: line),
            if (glyph != null || headline != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: PindoroSpace.s2,
                children: [
                  if (glyph != null)
                    DriveGlyph(
                      glyph,
                      size: glyphSize,
                      color: c.drivePlateGlyph,
                      cut: c.drivePlate,
                    ),
                  if (headline != null)
                    Flexible(
                      child: Text(
                        headline,
                        style: PindoroType.headlineLg.copyWith(
                          color: c.drivePlateText,
                          height: 1.1,
                        ),
                      ),
                    ),
                ],
              ),
            if (street case final s?) Text(s, style: line),
            if (note case final n?)
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: PindoroSpace.s2,
                children: [
                  Flexible(
                    child: Text(
                      n,
                      style: small,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (noteKind case final kind?)
                    Container(
                      width: _badge,
                      height: _badge,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.driveBadge,
                        borderRadius: BorderRadius.circular(PindoroRadius.sm),
                      ),
                      child: DriveGlyph(
                        kind,
                        size: _badgeGlyph,
                        color: c.driveBadgeInk,
                        cut: c.driveBadge,
                      ),
                    ),
                ],
              ),
            if (lanes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: PindoroSpace.s1),
                child: LaneArrows(lanes),
              ),
          ],
        ),
      ),
    );
    return Semantics(
      liveRegion: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: unscaled(
          context,
          Padding(
            padding: EdgeInsets.fromLTRB(
              PindoroSpace.s3,
              top + PindoroSpace.s2,
              PindoroSpace.s3,
              0,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: PindoroSpace.s1,
                children: [
                  card,
                  if (then != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: PindoroSpace.s3,
                        vertical: PindoroSpace.s1,
                      ),
                      decoration: BoxDecoration(
                        color: c.drivePlate,
                        borderRadius: BorderRadius.circular(PindoroRadius.md),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: PindoroSpace.s2,
                        children: [
                          if (thenLabel case final l?) Text(l, style: small),
                          DriveGlyph(
                            then,
                            size: _thenGlyph,
                            color: c.drivePlateGlyph,
                            cut: c.drivePlate,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The lanes of the road ahead, left to right (TurnPlate's bottom row): each lane's arrows,
/// the arrow to take bright in the lanes that go the way, the rest dim.
class LaneArrows extends StatelessWidget {
  const LaneArrows(this.lanes, {super.key});

  final List<DriveLane> lanes;

  static const Size laneSize = Size(28, 36);

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Wrap(
      spacing: PindoroSpace.s1,
      runSpacing: PindoroSpace.s1,
      children: [
        for (final lane in lanes)
          CustomPaint(
            size: laneSize,
            painter: _LanePainter(
              lane,
              on: c.drivePlateGlyph,
              off: c.drivePlateText2.withValues(alpha: PindoroOpacity.hatch),
            ),
          ),
      ],
    );
  }
}

/// One lane's arrows from a shared stem at the bottom centre, all to one scale: straight on up
/// the middle to the top, the turns bending off it with their heads level with a straight
/// arrow's (half way up when the lane also goes straight on), a U-turn hooking back down on
/// the left.
class _LanePainter extends CustomPainter {
  const _LanePainter(this.lane, {required this.on, required this.off});

  final DriveLane lane;
  final Color on;
  final Color off;

  static const double _stroke = 3.5;
  static const double _head = 6;

  /// How near straight on an arrow counts as straight.
  static const double _straightDeg = 22.5;

  @override
  void paint(Canvas canvas, Size size) {
    final use = lane.use;
    final through = lane.arrowsDeg.any((a) => a.abs() < _straightDeg);
    // The arrow to take last, so it lies over the dim ones.
    final arrows = [
      for (final a in lane.arrowsDeg)
        if (a != use) a,
      ?use,
    ];
    for (final a in arrows) {
      _arrow(canvas, size, a, a == use ? on : off, through: through);
    }
  }

  void _arrow(
    Canvas canvas,
    Size size,
    double deg,
    Color color, {
    required bool through,
  }) {
    final w = size.width;
    final h = size.height;
    final base = Offset(w / 2, h - _stroke / 2);
    // Where the heads reach: a straight arrow's tip, and every turn's in a lane without one.
    const top = _head + 1;
    final reach = w * 0.4;
    final rad = deg * math.pi / 180;
    final knee = Offset(
      w / 2,
      deg.abs() < _straightDeg
          ? top + reach
          : through
          ? h * 0.55
          : top + reach * math.max(0, math.cos(rad)),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(base.dx, base.dy);
    final Offset tip;
    final Offset from;
    if (deg.abs() >= 150) {
      // Turning around: up, over to the left and back down, the head kept inside the lane.
      final r = (w / 2 - _head) / 2;
      path
        ..lineTo(knee.dx, h * 0.35)
        ..arcToPoint(
          Offset(knee.dx - 2 * r, h * 0.35),
          radius: Radius.circular(r),
          clockwise: false,
        )
        ..lineTo(knee.dx - 2 * r, h * 0.6);
      tip = Offset(knee.dx - 2 * r, h * 0.6);
      from = Offset(tip.dx, tip.dy - 1);
    } else {
      tip = Offset(
        knee.dx + reach * math.sin(rad),
        knee.dy - reach * math.cos(rad),
      );
      path
        ..lineTo(knee.dx, knee.dy)
        ..lineTo(tip.dx, tip.dy);
      from = knee;
    }
    canvas.drawPath(path, paint);
    final d = tip - from;
    final unit = d / d.distance;
    final side = Offset(-unit.dy, unit.dx);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx + unit.dx * 2, tip.dy + unit.dy * 2)
        ..lineTo(
          tip.dx - unit.dx * _head + side.dx * _head,
          tip.dy - unit.dy * _head + side.dy * _head,
        )
        ..lineTo(
          tip.dx - unit.dx * _head - side.dx * _head,
          tip.dy - unit.dy * _head - side.dy * _head,
        )
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_LanePainter old) =>
      old.lane != lane || old.on != on || old.off != off;
}
