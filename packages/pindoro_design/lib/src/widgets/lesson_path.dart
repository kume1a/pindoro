import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';
import 'tappable.dart';

/// How a stop on the lesson path looks (`.pd-stop` and its modifiers).
enum PathStopLook { done, perfect, current, review, locked }

/// The progress ring's stroke and the gap around a 72 dp stop (`.pd-stop-ring`).
const double _ringStroke = 7;
const double _ringSize = PindoroSize.nodeCurrent + PindoroSpace.s6;

/// The tip's arrow and its gap above a big stop's centre (`.pd-tip`).
const double _tipArrow = 7;
const double _tipAbove = 56;

/// A round 3D stop on the lesson path: 56 dp ([big]: 72 dp) on its lip, the
/// [glyph] in the middle, an optional progress [ring] (0–1) around it and a
/// [tip] above it ("Start", "Tune up"). The current look floats ±4 dp over
/// 1.6 s; a tap presses it. The ring and tip paint outside its box, so place
/// it by its centre.
class PathStop extends StatefulWidget {
  const PathStop({
    super.key,
    required this.look,
    required this.glyph,
    required this.semanticLabel,
    this.big = false,
    this.ring,
    this.tip,
    this.scale = 1,
    this.onTap,
  });

  final PathStopLook look;
  final PindoroGlyph glyph;
  final String semanticLabel;
  final bool big;
  final double? ring;
  final String? tip;

  /// The unlock's pop and growth.
  final double scale;
  final VoidCallback? onTap;

  static double sizeOf({required bool big}) =>
      big ? PindoroSize.nodeCurrent : PindoroSize.nodeStop;

  @override
  State<PathStop> createState() => _PathStopState();
}

class _PathStopState extends State<PathStop>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncFloat();
  }

  @override
  void didUpdateWidget(PathStop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFloat();
  }

  void _syncFloat() {
    final floats =
        widget.look == PathStopLook.current &&
        !MediaQuery.disableAnimationsOf(context);
    if (floats && !_float.isAnimating) {
      _float.repeat(reverse: true);
    } else if (!floats && _float.isAnimating) {
      _float
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  void _press(bool down) {
    if (widget.onTap != null) setState(() => _pressed = down);
  }

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final (face, lip, ink, rim) = switch (widget.look) {
      PathStopLook.done ||
      PathStopLook.current => (c.primaryBase, c.primaryLip, c.primaryOn, null),
      PathStopLook.perfect => (c.rewardBase, c.rewardLip, c.rewardOn, null),
      PathStopLook.review => (
        c.pathNodeReviewFill,
        c.pathNodeReviewLip,
        c.pathNodeReviewIcon,
        c.pathNodeReviewLip,
      ),
      PathStopLook.locked => (
        c.pathNodeLockedFill,
        c.pathNodeLockedLip,
        c.pathNodeLockedIcon,
        null,
      ),
    };
    final size = PathStop.sizeOf(big: widget.big);
    final lipHeight = widget.look == PathStopLook.current
        ? PindoroElevation.e3
        : PindoroElevation.e2;
    final drop = _pressed ? lipHeight : 0.0;
    final ring = widget.ring;
    final tip = widget.tip;

    final button = AnimatedContainer(
      duration: PindoroMotion.durationInstant,
      curve: PindoroMotion.easePress,
      width: size,
      height: size,
      transform: Matrix4.translationValues(0, drop, 0),
      decoration: BoxDecoration(
        color: face,
        shape: BoxShape.circle,
        border: rim == null
            ? null
            : Border.all(color: rim, width: PindoroStroke.base),
        boxShadow: [
          if (!_pressed) BoxShadow(color: lip, offset: Offset(0, lipHeight)),
        ],
      ),
      child: Center(
        child: PindoroIcon(
          widget.glyph,
          size: widget.big ? 36 : PindoroSize.iconLg,
          color: ink,
          cut: face,
        ),
      ),
    );

    return AnimatedBuilder(
      animation: _float,
      builder: (context, child) => Transform.translate(
        offset: Offset(
          0,
          -4 * PindoroMotion.easeStandard.transform(_float.value),
        ),
        child: child,
      ),
      child: Transform.scale(
        scale: widget.scale,
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (ring != null)
                Positioned(
                  left: (size - _ringSize) / 2,
                  top: (size - _ringSize) / 2,
                  child: CustomPaint(
                    size: const Size.square(_ringSize),
                    painter: _RingPainter(
                      value: ring,
                      track: c.xpTrack,
                      fill: c.xpFill,
                    ),
                  ),
                ),
              Tappable(
                label: widget.semanticLabel,
                onTap: widget.onTap,
                onTapDown: (_) => _press(true),
                onTapUp: (_) => _press(false),
                onTapCancel: () => _press(false),
                child: button,
              ),
              if (tip != null)
                Positioned(
                  bottom: size / 2 + _tipAbove,
                  child: ExcludeSemantics(child: _Tip(tip)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.track,
    required this.fill,
  });

  final double value;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final circle = rect.deflate(_ringStroke / 2 + 1);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ringStroke;
    canvas.drawOval(circle, paint..color = track);
    if (value > 0) {
      canvas.drawArc(
        circle,
        -math.pi / 2,
        2 * math.pi * value.clamp(0, 1),
        false,
        paint
          ..color = fill
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.track != track || old.fill != fill;
}

/// "Start" above the current stop: a raised bubble with an arrow down.
class _Tip extends StatelessWidget {
  const _Tip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: PindoroSpace.s2,
          ),
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            borderRadius: BorderRadius.circular(PindoroRadius.md),
            boxShadow: [
              BoxShadow(color: c.lineBase, offset: const Offset(0, 2)),
            ],
          ),
          child: Text(
            label,
            maxLines: 1,
            style: PindoroType.labelLg.copyWith(
              color: c.primaryText,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        CustomPaint(
          size: const Size(2 * _tipArrow, _tipArrow),
          painter: _ArrowPainter(c.surfaceRaised),
        ),
      ],
    );
  }
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    Path()
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close(),
    Paint()..color = color,
  );

  @override
  bool shouldRepaint(_ArrowPainter old) => old.color != color;
}

/// A unit's compact signpost (`.pd-sign--compact`): the unit [number] in a
/// tile, a small [line] ("2 of 6 lessons") over the [title] (the district).
/// Locked units use the locked stop colours. Read as one heading.
class Signpost extends StatelessWidget {
  const Signpost({
    super.key,
    required this.number,
    required this.line,
    required this.title,
    required this.semanticLabel,
    this.locked = false,
    this.onTap,
  });

  final int number;
  final String line;
  final String title;
  final String semanticLabel;
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final (face, lip, rule, ink, sub) = locked
        ? (
            c.pathNodeLockedFill,
            c.pathNodeLockedLip,
            c.pathNodeLockedLip,
            c.textSecondary,
            c.textSecondary,
          )
        : (
            c.streetCardBg,
            c.streetCardLip,
            c.streetCardRule,
            c.streetCardText,
            c.streetCardSubtext,
          );
    final sign = Container(
      padding: const EdgeInsets.only(bottom: PindoroElevation.e2),
      decoration: BoxDecoration(
        color: lip,
        borderRadius: BorderRadius.circular(PindoroRadius.lg),
      ),
      child: Container(
        padding: const EdgeInsets.all(PindoroSpace.s1),
        decoration: BoxDecoration(
          color: face,
          borderRadius: BorderRadius.circular(PindoroRadius.lg),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 6, PindoroSpace.s3, 6),
          decoration: BoxDecoration(
            border: Border.all(color: rule, width: PindoroStroke.base),
            borderRadius: BorderRadius.circular(PindoroRadius.md),
          ),
          child: Row(
            spacing: PindoroSpace.s2,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: rule,
                  borderRadius: BorderRadius.circular(PindoroRadius.md),
                ),
                child: Text(
                  '$number',
                  style: PindoroType.titleMd.copyWith(
                    color: locked ? c.textSecondary : face,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line, style: PindoroType.labelMd.copyWith(color: sub)),
                    Text(
                      title,
                      style: PindoroType.titleMd.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      header: true,
      child: onTap == null
          ? Semantics(label: semanticLabel, excludeSemantics: true, child: sign)
          : Tappable(label: semanticLabel, onTap: onTap, child: sign),
    );
  }
}

/// The road from stop to stop (`.pd-road*`): cubic curves with vertical
/// tangents at each of [points]. Up to [driven] (in segments: 2.0 reaches
/// `points[2]`) it is asphalt with kerbs and white lane dashes; after it the
/// soft road ahead. While [driven] is between two stops (the unlock paving),
/// the newly paved stretch has accent-yellow dashes.
class LessonRoad extends StatelessWidget {
  const LessonRoad({
    super.key,
    required this.points,
    required this.driven,
    this.opacity = 1,
  });

  final List<Offset> points;
  final double driven;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Opacity(
      opacity: opacity,
      child: CustomPaint(
        painter: _RoadPainter(
          points: points,
          driven: driven,
          colors: (
            road: c.pathRoad,
            edge: c.pathEdge,
            lane: c.pathLane,
            ahead: c.pathRoadAhead,
            laneAhead: c.pathLaneAhead,
            paving: c.accentBase,
          ),
        ),
      ),
    );
  }
}

typedef _RoadColors = ({
  Color road,
  Color edge,
  Color lane,
  Color ahead,
  Color laneAhead,
  Color paving,
});

class _RoadPainter extends CustomPainter {
  const _RoadPainter({
    required this.points,
    required this.driven,
    required this.colors,
  });

  final List<Offset> points;
  final double driven;
  final _RoadColors colors;

  static Path _through(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], b = pts[i];
      final h = (b.dy - a.dy) / 2;
      path.cubicTo(a.dx, a.dy + h, b.dx, b.dy - h, b.dx, b.dy);
    }
    return path;
  }

  static Path _dashed(Path path, double dash, double gap) {
    final out = Path();
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        out.addPath(metric.extractPath(d, d + dash), Offset.zero);
      }
    }
    return out;
  }

  Paint _stroke(Color color, double width, {bool round = true}) => Paint()
    ..style = PaintingStyle.stroke
    ..color = color
    ..strokeWidth = width
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = round ? StrokeCap.round : StrokeCap.butt;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final whole = _through(points);
    canvas
      ..drawPath(whole, _stroke(colors.ahead, PindoroSize.road))
      ..drawPath(
        _dashed(whole, 6, 10),
        _stroke(colors.laneAhead, PindoroStroke.thick),
      );

    final reach = driven.clamp(0, points.length - 1.0);
    if (reach <= 0) return;
    final full = reach.floor();
    final part = reach - full;
    final paved = _through(points.sublist(0, full + 1));
    Path? paving;
    if (part > 0) {
      final next = _through([points[full], points[full + 1]]);
      final metric = next.computeMetrics().first;
      paving = metric.extractPath(0, metric.length * part);
      paved.addPath(paving, Offset.zero);
    }
    canvas
      ..drawPath(
        paved,
        _stroke(colors.edge, PindoroSize.road + 2 * PindoroStroke.base),
      )
      ..drawPath(paved, _stroke(colors.road, PindoroSize.road))
      ..drawPath(
        _dashed(_through(points.sublist(0, full + 1)), 10, 12),
        _stroke(colors.lane, PindoroStroke.thick, round: false),
      );
    if (paving != null) {
      canvas.drawPath(
        _dashed(paving, 10, 12),
        _stroke(colors.paving, 4, round: false),
      );
    }
  }

  @override
  bool shouldRepaint(_RoadPainter old) =>
      old.driven != driven || old.points != points || old.colors != colors;
}
