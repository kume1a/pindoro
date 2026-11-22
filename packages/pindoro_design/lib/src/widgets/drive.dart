import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'drive_glyph.dart';
import 'graphics.dart';
import 'pindoro_button.dart';
import 'tappable.dart';

// The drive parts of the design system (v3.2 · Navigate and learn, V32-90). Their
// `color.drive.*` colours are day in the light theme and night in the dark one: the drive screen
// picks the theme by sun time at the car's position, not by the app's theme. Text read while
// moving ignores the system text scale: `type.drive.*` on Coached, Quiet and Off; Guided's
// turn card, bar and chip are compact (title and headline sizes, SPEC §16.23 items 118 and
// 130) so its map keeps its room.

/// Guided's bar and chip (26 dp).
TextStyle _barType(Color color) =>
    PindoroType.headlineMd.copyWith(color: color, height: 1.15);

/// Drive type is sized for a glance from the holder, so the system text
/// scale never changes it.
Widget _unscaled(BuildContext context, Widget child) =>
    MediaQuery.withNoTextScaling(child: child);

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
  static const double _widthShare = 0.62;

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
        boxShadow: [
          BoxShadow(
            color: c.drivePlate.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
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
                  Flexible(child: Text(n, style: small)),
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
        child: _unscaled(
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

/// One lane's arrows from a shared stem at the bottom centre: straight on up the middle, the
/// turns bending off it, a U-turn hooking back down on the left.
class _LanePainter extends CustomPainter {
  const _LanePainter(this.lane, {required this.on, required this.off});

  final DriveLane lane;
  final Color on;
  final Color off;

  static const double _stroke = 3.5;
  static const double _head = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final use = lane.use;
    // The arrow to take last, so it lies over the dim ones.
    final arrows = [
      for (final a in lane.arrowsDeg)
        if (a != use) a,
      ?use,
    ];
    for (final a in arrows) {
      _arrow(canvas, size, a, a == use ? on : off);
    }
  }

  void _arrow(Canvas canvas, Size size, double deg, Color color) {
    final w = size.width;
    final h = size.height;
    final base = Offset(w / 2, h - _stroke / 2);
    final knee = Offset(w / 2, h * 0.55);
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
      // Turning around: up, over to the left and back down.
      final r = w * 0.22;
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
      final rad = deg * math.pi / 180;
      final reach = deg == 0 ? h * 0.55 : w * 0.42;
      tip = Offset(
        knee.dx + reach * math.sin(rad),
        knee.dy - (deg == 0 ? reach : reach * math.cos(rad)),
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

/// The ink bar along the bottom of Guided (DriveBottomBar), one line: the
/// flag, the [arrival] time and the distance [left], or one [line] instead
/// ("GPS lost 1:02"); then the rescued mark, the camera badge and the [sign].
/// One polite live region, [semanticsLabel].
class DriveBottomBar extends StatelessWidget {
  const DriveBottomBar({
    super.key,
    required this.semanticsLabel,
    this.arrival,
    this.left,
    this.line,
    this.rescued = false,
    this.camera = false,
    this.sign,
  });

  final String semanticsLabel;
  final String? arrival;
  final String? left;
  final String? line;
  final bool rescued;
  final bool camera;
  final Widget? sign;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final read = _barType(c.drivePlateText);
    final bottom = math.max(
      MediaQuery.paddingOf(context).bottom,
      PindoroSpace.s3,
    );
    final trip = [?arrival, ?left].join(' · ');
    return Semantics(
      liveRegion: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: _unscaled(
          context,
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.drivePlate,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(PindoroRadius.r2xl),
              ),
              boxShadow: [
                BoxShadow(
                  color: c.drivePlate.withValues(alpha: 0.22),
                  blurRadius: 18,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                PindoroSpace.s4,
                PindoroSpace.s3,
                PindoroSpace.s3,
                bottom,
              ),
              child: Row(
                spacing: PindoroSpace.s3,
                children: [
                  // ponytail: on a narrow phone with the rescued mark and a
                  // camera at once, the trip line shrinks rather than wrap;
                  // the canvas never draws all three together.
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: line != null
                          ? Text(line!, style: read)
                          : Row(
                              spacing: PindoroSpace.s2,
                              children: [
                                if (arrival != null)
                                  DriveGlyph(
                                    DriveGlyphName.flag,
                                    size: 26,
                                    color: c.drivePlateGlyph,
                                    cut: c.drivePlate,
                                  ),
                                Text(trip, style: read),
                              ],
                            ),
                    ),
                  ),
                  if (rescued)
                    DriveGlyph(
                      DriveGlyphName.rescue,
                      size: 32,
                      color: c.drivePlateText2,
                      cut: c.drivePlate,
                    ),
                  if (camera) const CameraBadge(),
                  ?sign,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A round speed-limit sign (SpeedLimitSign): the [limit] in a red ring.
/// [over] (over the limit plus the tolerance) pulses it two and a half times
/// and leaves it grown with its halos; a new [beat] while over pulses again.
class SpeedLimitSign extends StatefulWidget {
  const SpeedLimitSign({
    super.key,
    required this.limit,
    required this.semanticsLabel,
    this.over = false,
    this.beat = 0,
  });

  final int limit;
  final String semanticsLabel;
  final bool over;
  final int beat;

  static const double size = 64;

  @override
  State<SpeedLimitSign> createState() => _SpeedLimitSignState();
}

class _SpeedLimitSignState extends State<SpeedLimitSign>
    with SingleTickerProviderStateMixin {
  /// Two and a half beats of `duration.base` + `duration.slow`, ending at a peak.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: (PindoroMotion.durationBase + PindoroMotion.durationSlow) * 2.5,
  );

  @override
  void initState() {
    super.initState();
    if (widget.over) _pulse.value = 1;
  }

  @override
  void didUpdateWidget(SpeedLimitSign old) {
    super.didUpdateWidget(old);
    if (!widget.over) {
      _pulse.value = 0;
    } else if (!old.over || widget.beat != old.beat) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _pulse.value = 1;
      } else {
        _pulse.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final three = widget.limit >= 100;
    final figures =
        (three ? PindoroType.headlineMd : PindoroType.headlineLg).fontSize!;
    return Semantics(
      image: true,
      label: widget.semanticsLabel,
      child: ExcludeSemantics(
        child: _unscaled(
          context,
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final beats = _pulse.value * 2.5;
              final i = (1 - math.cos(2 * math.pi * beats)) / 2;
              return Transform.scale(
                scale: 1 + 0.06 * i,
                child: Container(
                  width: SpeedLimitSign.size,
                  height: SpeedLimitSign.size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.driveSignBg,
                    border: Border.all(color: c.driveSignRing, width: 7),
                    boxShadow: [
                      if (i > 0) ...[
                        BoxShadow(
                          color: c.driveSignRing.withValues(alpha: 0.45),
                          spreadRadius: 6 * i,
                        ),
                        BoxShadow(
                          color: c.driveSignRing.withValues(alpha: 0.18),
                          spreadRadius: 12 * i,
                        ),
                      ],
                    ],
                  ),
                  child: Text(
                    '${widget.limit}',
                    style: PindoroType.driveRead.copyWith(
                      fontSize: figures,
                      height: 1,
                      letterSpacing: -0.02 * figures,
                      color: c.driveSignText,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The orange camera badge beside the speed sign while a camera is ahead
/// (CameraBadge). Its words join the bar's or the screen's announcement.
class CameraBadge extends StatelessWidget {
  const CameraBadge({super.key});

  static const double size = 64;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.driveCamera,
        borderRadius: BorderRadius.circular(PindoroRadius.lg),
      ),
      child: DriveGlyph(
        DriveGlyphName.camera,
        size: 44,
        color: c.driveCameraInk,
        cut: c.driveCamera,
      ),
    );
  }
}

/// The district as a chip on Guided's map (DistrictChip), left out when
/// [name] doesn't fit the width it is given.
class DistrictChip extends StatelessWidget {
  const DistrictChip(this.name, {super.key, required this.semanticsLabel});

  final String name;
  final String semanticsLabel;

  static const double height = 48;
  static const double _sides = PindoroSpace.s4;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final style = _barType(c.driveText);
    return LayoutBuilder(
      builder: (context, constraints) {
        final text = TextPainter(
          text: TextSpan(text: name, style: style),
          textDirection: Directionality.of(context),
          maxLines: 1,
        )..layout();
        final fits =
            text.width + 2 * (_sides + PindoroStroke.base) <=
            constraints.maxWidth;
        text.dispose();
        if (!fits) return const SizedBox.shrink();
        return Semantics(
          liveRegion: true,
          label: semanticsLabel,
          child: ExcludeSemantics(
            child: _unscaled(
              context,
              Container(
                height: height,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: _sides),
                decoration: BoxDecoration(
                  color: c.driveSurface,
                  borderRadius: BorderRadius.circular(PindoroRadius.lg),
                  border: Border.all(
                    color: c.driveSurfaceLine,
                    width: PindoroStroke.base,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: c.drivePlate.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(name, style: style, maxLines: 1),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The district under the Coached and Quiet dial (DistrictChip's line):
/// `type.drive.district`, stepping down 2 dp at a time to fit, never under
/// 54 dp; still too wide, it wraps.
class DistrictLine extends StatelessWidget {
  const DistrictLine(this.name, {super.key});

  final String name;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final base = PindoroType.driveDistrict.copyWith(color: c.driveQuietText);
    return LayoutBuilder(
      builder: (context, constraints) {
        var size = base.fontSize!;
        while (size > PindoroType.driveRead.fontSize!) {
          final text = TextPainter(
            text: TextSpan(
              text: name,
              style: base.copyWith(fontSize: size),
            ),
            textDirection: Directionality.of(context),
            maxLines: 1,
          )..layout();
          final fits = text.width <= constraints.maxWidth;
          text.dispose();
          if (fits) break;
          size -= 2;
        }
        return _unscaled(
          context,
          Text(
            name,
            textAlign: TextAlign.center,
            style: base.copyWith(fontSize: size),
          ),
        );
      },
    );
  }
}

/// Where the drive stands: on a good path, recovering from a wrong turn, or
/// finding the car (GPS lost).
enum DriveStatus { good, recovering, lost }

Color _statusColor(PindoroColors c, DriveStatus status) => switch (status) {
  DriveStatus.good => c.driveDotGood,
  DriveStatus.recovering => c.driveDotRecover,
  DriveStatus.lost => c.driveDotLost,
};

/// The Coached and Quiet dial (HeadingDial): a north-up ring in the
/// [status] colour, the car's [heading] on it and its cardinal [letter] in
/// the middle. Finding the car, the pointer and letter go and the dial dims.
class HeadingDial extends StatefulWidget {
  const HeadingDial({
    super.key,
    required this.heading,
    required this.letter,
    required this.status,
    required this.semanticsLabel,
    this.size = 280,
  });

  final double? heading;
  final String letter;
  final DriveStatus status;
  final String semanticsLabel;
  final double size;

  @override
  State<HeadingDial> createState() => _HeadingDialState();
}

class _HeadingDialState extends State<HeadingDial> {
  /// The pointer's turns, unwrapped so it always turns the shorter way.
  double _turns = 0;

  @override
  void initState() {
    super.initState();
    _turns = (widget.heading ?? 0) / 360;
  }

  @override
  void didUpdateWidget(HeadingDial old) {
    super.didUpdateWidget(old);
    final heading = widget.heading;
    if (heading == null) return;
    final from = (_turns * 360) % 360;
    _turns += (((heading - from) % 360 + 540) % 360 - 180) / 360;
  }

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final lost = widget.status == DriveStatus.lost;
    final s = widget.size / 280;
    final calm = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      image: true,
      label: widget.semanticsLabel,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: lost ? 0.5 : 1,
          child: SizedBox.square(
            dimension: widget.size,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DialPainter(
                      ring: _statusColor(c, widget.status),
                      dashed: lost,
                      north: c.driveQuietText,
                      ticks: c.driveQuietRing,
                    ),
                  ),
                ),
                if (!lost) ...[
                  Positioned.fill(
                    child: AnimatedRotation(
                      turns: _turns,
                      duration: calm
                          ? Duration.zero
                          : PindoroMotion.durationFast,
                      child: CustomPaint(
                        painter: _PointerPainter(
                          heading: c.driveHeading,
                          rim: c.driveQuietBg,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 100 * s,
                    child: _unscaled(
                      context,
                      Text(
                        widget.letter,
                        textAlign: TextAlign.center,
                        style: PindoroType.drivePrimary.copyWith(
                          color: c.driveQuietText,
                          fontSize: PindoroType.drivePrimary.fontSize! * s,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  const _DialPainter({
    required this.ring,
    required this.dashed,
    required this.north,
    required this.ticks,
  });

  final Color ring;
  final bool dashed;
  final Color north;
  final Color ticks;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 280;
    canvas.scale(s);
    const centre = Offset(140, 140);
    final stroke = Paint()
      ..color = ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    final circle = Path()
      ..addOval(Rect.fromCircle(center: centre, radius: 124));
    if (dashed) {
      for (final metric in circle.computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += 24) {
          canvas.drawPath(metric.extractPath(d, d + 10), stroke);
        }
      }
    } else {
      canvas.drawPath(circle, stroke);
    }
    canvas.drawPath(
      Path()
        ..moveTo(140, 2)
        ..lineTo(151, 18)
        ..lineTo(129, 18)
        ..close(),
      Paint()..color = north,
    );
    final tick = Paint()
      ..color = ticks
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (var t = 45; t < 360; t += 45) {
      final b = t * math.pi / 180;
      Offset at(double r) => centre + Offset(r * math.sin(b), -r * math.cos(b));
      canvas.drawLine(at(112), at(126), tick);
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.ring != ring ||
      old.dashed != dashed ||
      old.north != north ||
      old.ticks != ticks;
}

/// The heading pointer and its fan, drawn pointing north; rotated around the
/// centre to the heading.
class _PointerPainter extends CustomPainter {
  const _PointerPainter({required this.heading, required this.rim});

  final Color heading;
  final Color rim;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.shortestSide / 280);
    const centre = Offset(140, 140);
    const half = 18 * math.pi / 180;
    canvas.drawPath(
      Path()
        ..moveTo(centre.dx, centre.dy)
        ..arcTo(
          Rect.fromCircle(center: centre, radius: 116),
          -math.pi / 2 - half,
          2 * half,
          false,
        )
        ..close(),
      Paint()..color = heading.withValues(alpha: 0.16),
    );
    final pointer = Path()
      ..moveTo(140, 6)
      ..lineTo(164, 46)
      ..lineTo(140, 36)
      ..lineTo(116, 46)
      ..close();
    canvas
      ..drawPath(
        pointer,
        Paint()
          ..color = rim
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeJoin = StrokeJoin.round,
      )
      ..drawPath(pointer, Paint()..color = heading);
  }

  @override
  bool shouldRepaint(_PointerPainter old) =>
      old.heading != heading || old.rim != rim;
}

/// The status dot in the top corner of Coached and Quiet: filled on a good
/// path, with a halo while recovering, an outline while finding the car;
/// [ring] (0 to 1) fills the 10 s ring around it after a recovery.
class StatusDot extends StatelessWidget {
  const StatusDot({
    super.key,
    required this.status,
    required this.semanticsLabel,
    this.ring,
  });

  final DriveStatus status;
  final String semanticsLabel;
  final double? ring;

  static const double size = 24;
  static const double ringSize = 48;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final color = _statusColor(c, status);
    return Semantics(
      liveRegion: true,
      image: true,
      label: semanticsLabel,
      child: SizedBox.square(
        dimension: ringSize,
        child: CustomPaint(
          painter: ring == null
              ? null
              : _RingPainter(progress: ring!, color: c.driveDotGood),
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: status == DriveStatus.lost ? null : color,
                border: status == DriveStatus.lost
                    ? Border.all(color: color, width: 4)
                    : null,
                boxShadow: status == DriveStatus.recovering
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.3),
                          spreadRadius: 6,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const width = 3.0;
    canvas.drawArc(
      (Offset.zero & size).deflate(width / 2),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0, 1),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

/// Five bars beside the status dot that move while Coached's voice speaks;
/// still at mid height under reduce motion. Decorative.
class SpeakingBars extends StatefulWidget {
  const SpeakingBars({super.key});

  @override
  State<SpeakingBars> createState() => _SpeakingBarsState();
}

class _SpeakingBarsState extends State<SpeakingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: PindoroMotion.durationSlow * 2,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _wave.stop();
    } else if (!_wave.isAnimating) {
      _wave.repeat();
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = PindoroTheme.of(
      context,
    ).colors.driveQuietText.withValues(alpha: 0.7);
    final calm = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: SizedBox(
        height: 24,
        child: AnimatedBuilder(
          animation: _wave,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              for (var i = 0; i < 5; i++)
                Container(
                  width: 4,
                  height: calm
                      ? 12
                      : 6 +
                            18 *
                                (0.5 +
                                    0.5 *
                                        math.sin(
                                          2 * math.pi * (_wave.value + i / 5),
                                        )),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 10 dp orange band along the top edge while recovering (RecoveryBand).
class RecoveryBand extends StatelessWidget {
  const RecoveryBand({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 10,
    width: double.infinity,
    child: ColoredBox(color: PindoroTheme.of(context).colors.driveDotRecover),
  );
}

/// Off's only mark: a small steady red dot (RecordingDot).
class RecordingDot extends StatelessWidget {
  const RecordingDot({super.key, required this.semanticsLabel});

  final String semanticsLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: semanticsLabel,
    child: Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: PindoroTheme.of(context).colors.driveRec,
      ),
    ),
  );
}

/// One step of a [LevelPicker]: disabled with its [disabledReason].
typedef LevelStep<T> = ({
  T value,
  String label,
  PindoroGlyph icon,
  String? disabledReason,
});

/// Four steps of help for a drive (LevelPicker): the [suggested] step wears
/// a yellow [suggestedLabel] tag; a disabled step says why on long-press. A
/// tap applies at once. Parked only: it follows the app theme.
class LevelPicker<T> extends StatelessWidget {
  const LevelPicker({
    super.key,
    required this.steps,
    required this.selected,
    required this.suggestedLabel,
    required this.onChanged,
    required this.semanticsLabel,
    this.suggested,
  });

  final List<LevelStep<T>> steps;
  final T selected;
  final T? suggested;
  final String suggestedLabel;
  final ValueChanged<T> onChanged;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final large = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    Widget step(int i) {
      final s = steps[i];
      return Expanded(
        child: _LevelStepView(
          step: s,
          selected: s.value == selected,
          suggested: s.value == suggested,
          suggestedLabel: suggestedLabel,
          semanticsLabel: [
            s.label,
            if (s.value == suggested) suggestedLabel,
            ?s.disabledReason,
            '${i + 1} / ${steps.length}',
          ].join(', '),
          onTap: s.disabledReason != null || s.value == selected
              ? null
              : () => onChanged(s.value),
        ),
      );
    }

    Widget row(Iterable<int> indexes) => Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: PindoroSpace.s1,
      children: [for (final i in indexes) step(i)],
    );
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: Container(
        // Room above for the suggested tag.
        margin: const EdgeInsets.only(top: PindoroSpace.s3),
        padding: const EdgeInsets.all(PindoroSpace.s1),
        decoration: BoxDecoration(
          color: c.surfaceSunken,
          borderRadius: BorderRadius.circular(PindoroRadius.lg),
        ),
        child: IntrinsicHeight(
          child: large
              ? Column(
                  spacing: PindoroSpace.s4,
                  children: [
                    for (var i = 0; i < steps.length; i += 2)
                      IntrinsicHeight(
                        child: row([i, if (i + 1 < steps.length) i + 1]),
                      ),
                  ],
                )
              : row(List.generate(steps.length, (i) => i)),
        ),
      ),
    );
  }
}

class _LevelStepView<T> extends StatelessWidget {
  const _LevelStepView({
    required this.step,
    required this.selected,
    required this.suggested,
    required this.suggestedLabel,
    required this.semanticsLabel,
    required this.onTap,
  });

  final LevelStep<T> step;
  final bool selected;
  final bool suggested;
  final String suggestedLabel;
  final String semanticsLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final disabled = step.disabledReason != null;
    final ink = disabled
        ? c.textDisabled
        : selected
        ? c.primaryText
        : c.textSecondary;
    final large = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    final face = AnimatedContainer(
      duration: PindoroMotion.durationQuick,
      curve: PindoroMotion.easeStandard,
      constraints: BoxConstraints(minHeight: large ? 96 : 64),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      decoration: BoxDecoration(
        color: selected ? c.surfaceRaised : Colors.transparent,
        borderRadius: BorderRadius.circular(PindoroRadius.md),
        border: selected
            ? Border(
                bottom: BorderSide(
                  color: c.lineBase,
                  width: PindoroElevation.e1,
                ),
              )
            : null,
      ),
      foregroundDecoration: selected
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(PindoroRadius.md),
              border: Border.all(
                color: c.primaryBase,
                width: PindoroStroke.thick,
              ),
            )
          : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 2,
        children: [
          PindoroIcon(
            step.icon,
            size: large ? 32 : 22,
            color: ink,
            cut: selected ? c.surfaceRaised : c.surfaceSunken,
          ),
          Text(
            step.label,
            textAlign: TextAlign.center,
            style: PindoroType.labelLg.copyWith(
              color: ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
    final tapped = Tappable(
      label: semanticsLabel,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      onTap: onTap,
      child: disabled
          ? Tooltip(
              message: step.disabledReason,
              triggerMode: TooltipTriggerMode.longPress,
              child: face,
            )
          : face,
    );
    if (!suggested) return tapped;
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        tapped,
        Positioned(
          top: -PindoroSpace.s4,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              height: 18,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: c.accentBase,
                borderRadius: BorderRadius.circular(PindoroRadius.full),
              ),
              alignment: Alignment.center,
              child: Text(
                suggestedLabel,
                maxLines: 1,
                style: PindoroType.labelSm.copyWith(
                  color: c.accentOn,
                  fontWeight: FontWeight.w800,
                  height: 18 / 11,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The line above the level picker (LevelSuggestion): "[lead] [level]" and
/// its [reason], with a pip per turn on the route, filled for the [yours]
/// ones; [pipsLabel] reads the pips as one image.
class LevelSuggestion extends StatelessWidget {
  const LevelSuggestion({
    super.key,
    required this.lead,
    required this.level,
    required this.reason,
    this.yours,
    this.pipsLabel,
  });

  final String lead;
  final String level;
  final String reason;
  final List<bool>? yours;
  final String? pipsLabel;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final style = PindoroType.labelLg.copyWith(color: c.textPrimary);
    final large = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    final what = Text.rich(
      TextSpan(
        text: '$lead ',
        children: [
          TextSpan(
            text: level,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
      style: style,
    );
    final why = Text(reason, style: style.copyWith(color: c.textSecondary));
    final icon = PindoroIcon(
      PindoroGlyph.hint,
      size: large ? 32 : 22,
      color: c.primaryText,
      cut: c.surfaceBase,
    );
    final pips = yours;
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s2,
        children: [
          MergeSemantics(
            child: Row(
              crossAxisAlignment: large
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              spacing: PindoroSpace.s2,
              children: [
                icon,
                if (large)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [what, why],
                    ),
                  )
                else ...[
                  Expanded(child: what),
                  Flexible(child: why),
                ],
              ],
            ),
          ),
          if (pips != null && pips.isNotEmpty)
            Semantics(
              image: true,
              label: pipsLabel,
              child: ExcludeSemantics(
                child: Row(
                  spacing: 3,
                  children: [
                    for (final mine in pips)
                      Expanded(
                        child: Container(
                          height: large ? 20 : 14,
                          decoration: BoxDecoration(
                            color: mine ? c.primaryBase : null,
                            borderRadius: BorderRadius.circular(4),
                            border: mine
                                ? null
                                : Border.all(
                                    color: c.accentLip,
                                    width: PindoroStroke.thick,
                                  ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The level chip in the [StoppedBar]: the level's [icon] and [label], a
/// chevron that points up while [open].
class _LevelChip extends StatelessWidget {
  const _LevelChip({
    required this.icon,
    required this.label,
    required this.semanticsLabel,
    required this.open,
    required this.onTap,
  });

  final PindoroGlyph icon;
  final String label;
  final String semanticsLabel;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final radius = BorderRadius.circular(PindoroRadius.lg);
    // A face with its edge on a lip of its own colour, as the buttons are.
    return Tappable(
      label: semanticsLabel,
      toggled: open,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(bottom: PindoroElevation.e1),
        decoration: BoxDecoration(
          color: open ? c.primaryLip : c.lineStrong,
          borderRadius: radius,
        ),
        child: Container(
          height: PindoroSize.buttonLg - PindoroElevation.e1,
          padding: const EdgeInsets.fromLTRB(
            PindoroSpace.s4,
            0,
            PindoroSpace.s3,
            0,
          ),
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            borderRadius: radius,
            border: Border.all(
              color: open ? c.primaryBase : c.lineStrong,
              width: PindoroStroke.base,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: PindoroSpace.s1,
            children: [
              PindoroIcon(icon, size: 20, color: c.textPrimary),
              Text(
                label,
                style: PindoroType.bodyLg.copyWith(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              RotatedBox(
                quarterTurns: open ? 2 : 0,
                child: PindoroIcon(
                  PindoroGlyph.chevronDown,
                  size: 20,
                  color: c.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The level shown on the [StoppedBar]'s chip.
typedef StoppedLevel = ({
  PindoroGlyph icon,
  String label,
  String semanticsLabel,
});

/// The only controls on a driving screen, while the car is stopped
/// (StoppedBar): the distance [left] and the [arrival] time, Mute, the
/// [level] chip that opens the [picker] (under its [pickerTitle] and
/// [pickerReason]), Route (the preview and the destination, [routeLabel]) and End drive.
class StoppedBar extends StatelessWidget {
  const StoppedBar({
    super.key,
    required this.semanticsLabel,
    required this.left,
    required this.arrival,
    required this.muted,
    required this.muteLabel,
    required this.onMute,
    required this.level,
    required this.levelOpen,
    required this.onLevel,
    required this.endLabel,
    required this.onEnd,
    this.picker,
    this.pickerTitle,
    this.pickerReason,
    this.routeLabel,
    this.onRoute,
  });

  final String semanticsLabel;
  final String? left;
  final String? arrival;
  final bool muted;
  final String muteLabel;
  final VoidCallback onMute;
  final StoppedLevel level;
  final bool levelOpen;
  final VoidCallback onLevel;
  final String endLabel;
  final VoidCallback onEnd;
  final Widget? picker;
  final String? pickerTitle;
  final String? pickerReason;
  final String? routeLabel;
  final VoidCallback? onRoute;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final bottom = math.max(
      MediaQuery.paddingOf(context).bottom,
      PindoroSpace.s3,
    );
    final info = PindoroType.bodyLg.copyWith(fontWeight: FontWeight.w800);
    final picker = this.picker;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticsLabel,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          PindoroSpace.s3,
          PindoroSpace.s3,
          PindoroSpace.s3,
          bottom,
        ),
        decoration: BoxDecoration(
          color: c.driveSurface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(PindoroRadius.r2xl),
          ),
          border: Border(
            top: BorderSide(
              color: c.driveSurfaceLine,
              width: PindoroStroke.base,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            if (levelOpen && picker != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 6,
                children: [
                  Row(
                    spacing: PindoroSpace.s2,
                    children: [
                      Expanded(
                        child: Text(
                          pickerTitle ?? '',
                          style: PindoroType.labelLg.copyWith(
                            color: c.driveText,
                          ),
                        ),
                      ),
                      if (pickerReason case final r?)
                        Text(
                          r,
                          style: PindoroType.labelLg.copyWith(
                            color: c.driveText2,
                          ),
                        ),
                    ],
                  ),
                  picker,
                ],
              ),
            Row(
              children: [
                if (left case final l?)
                  Expanded(
                    child: Text(l, style: info.copyWith(color: c.driveText)),
                  )
                else
                  const Spacer(),
                if (arrival case final a?)
                  Text(
                    a,
                    style: info.copyWith(
                      color: c.driveText2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            Row(
              spacing: PindoroSpace.s2,
              children: [
                PindoroButton(
                  label: muteLabel,
                  icon: muted ? PindoroGlyph.soundOff : PindoroGlyph.soundOn,
                  iconOnly: true,
                  large: true,
                  variant: PindoroButtonVariant.secondary,
                  onPressed: onMute,
                ),
                _LevelChip(
                  icon: level.icon,
                  label: level.label,
                  semanticsLabel: level.semanticsLabel,
                  open: levelOpen,
                  onTap: onLevel,
                ),
                if ((routeLabel, onRoute) case (final label?, final tap?))
                  PindoroButton(
                    label: label,
                    icon: PindoroGlyph.route,
                    iconOnly: true,
                    large: true,
                    variant: PindoroButtonVariant.secondary,
                    onPressed: tap,
                  ),
                Expanded(
                  child: PindoroButton(
                    label: endLabel,
                    large: true,
                    variant: PindoroButtonVariant.secondary,
                    onPressed: onEnd,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
