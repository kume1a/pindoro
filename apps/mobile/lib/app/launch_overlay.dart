import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro_design/pindoro_design.dart';

import 'settings.dart';

/// The native splash's pin, measured from `res/drawable*/splash.png`: dp per
/// pin unit, and how far its yellow dot sits above the screen centre.
const double _unit = 2.35;
const double _dotAboveCentre = 17.75;

/// Cold start (canvas M-10) over the first page: the native splash's pin
/// hops, a road draws out under it, it lands with a squash and a ring, then
/// the page opens out of the yellow dot. With reduce motion the splash
/// cross-fades away instead.
class LaunchOverlay extends ConsumerStatefulWidget {
  const LaunchOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LaunchOverlay> createState() => _LaunchOverlayState();
}

/// Milliseconds into the launch where each phase starts.
abstract final class _At {
  static const double hop = 700;
  static const double fall = 1000;
  static const double land = 1220;
  static const double settle = 1280;
  static const double reveal = 1500;
  static const double end = 1860;
}

class _LaunchOverlayState extends ConsumerState<LaunchOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _At.end.toInt()),
  );
  bool _calm = false;
  bool _done = false;
  bool _landed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_t.status != AnimationStatus.dismissed) return;
    _calm = MediaQuery.disableAnimationsOf(context);
    if (_calm) _t.duration = const Duration(milliseconds: 150);
    _t
      ..addListener(_onTick)
      ..forward().whenCompleteOrCancel(() {
        if (mounted) setState(() => _done = true);
      });
  }

  void _onTick() {
    if (!_calm && !_landed && _t.value * _At.end >= _At.land) {
      _landed = true;
      ref.read(feedbackProvider).pinDrop();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: AbsorbPointer(
            child: AnimatedBuilder(
              animation: _t,
              builder: (context, _) => _calm
                  ? Opacity(opacity: 1 - _t.value, child: _frame(dark, 0))
                  : _frame(dark, _t.value * _At.end),
            ),
          ),
        ),
      ],
    );
  }

  /// The launch [ms] milliseconds in.
  Widget _frame(bool dark, double ms) => LayoutBuilder(
    builder: (context, box) {
      final dot =
          box.biggest.center(Offset.zero) - const Offset(0, _dotAboveCentre);
      final pin = _pinPose(ms);
      return ClipPath(
        clipper: _Hole(
          dot,
          _phase(ms, _At.reveal, _At.end, PindoroMotion.easeStandard),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _Ground(
                  dark: dark,
                  dot: dot,
                  road: _phase(
                    ms,
                    _At.hop,
                    _At.hop + 280,
                    PindoroMotion.easeDecelerate,
                  ),
                  lanes: _phase(ms, _At.fall, _At.fall + 200, Curves.linear),
                  ring: ms < _At.land
                      ? null
                      : _phase(
                          ms,
                          _At.land,
                          _At.land + 420,
                          PindoroMotion.easeDecelerate,
                        ),
                ),
              ),
            ),
            Positioned(
              left: dot.dx - 22 * _unit,
              top: dot.dy - 20 * _unit,
              child: Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.translationValues(0, pin.dy, 0)
                  ..scaleByDouble(pin.sx, pin.sy, 1, 1),
                child: PinMark(
                  face: dark
                      ? PindoroPalette.cobalt400
                      : PindoroPalette.asphalt0,
                  lip: dark
                      ? PindoroPalette.cobalt600
                      : PindoroPalette.cobalt200,
                  dot: PindoroPalette.yellow400,
                  width: PinMark.gridWidth * _unit,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// 0 → 1 between [from] and [to] milliseconds, eased by [curve].
double _phase(double ms, double from, double to, Curve curve) =>
    curve.transform(((ms - from) / (to - from)).clamp(0.0, 1.0));

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// The pin's offset and stretch: up 28 dp stretched, down, a squash on
/// landing, then back to rest with an overshoot.
({double dy, double sx, double sy}) _pinPose(double ms) {
  if (ms < _At.hop) return (dy: 0, sx: 1, sy: 1);
  if (ms < _At.fall) {
    final t = _phase(ms, _At.hop, _At.fall, PindoroMotion.easeDecelerate);
    return (dy: -28 * t, sx: _lerp(1, 0.96, t), sy: _lerp(1, 1.05, t));
  }
  if (ms < _At.land) {
    final t = _phase(ms, _At.fall, _At.land, PindoroMotion.easeAccelerate);
    return (dy: -28 * (1 - t), sx: _lerp(0.96, 1, t), sy: _lerp(1.05, 1, t));
  }
  if (ms < _At.settle) {
    final t = _phase(ms, _At.land, _At.settle, PindoroMotion.easePress);
    return (dy: 0, sx: _lerp(1, 1.12, t), sy: _lerp(1, 0.86, t));
  }
  final t = _phase(ms, _At.settle, _At.reveal, PindoroMotion.easeOvershoot);
  return (dy: 0, sx: _lerp(1.12, 1, t), sy: _lerp(0.86, 1, t));
}

/// The splash colour, the road drawing out under the pin with its lane
/// dashes, and the yellow ring where the pin lands.
class _Ground extends CustomPainter {
  _Ground({
    required this.dark,
    required this.dot,
    required this.road,
    required this.lanes,
    required this.ring,
  });

  final bool dark;
  final Offset dot;
  final double road;
  final double lanes;
  final double? ring;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = dark ? PindoroPalette.asphalt950 : PindoroPalette.cobalt500,
    );
    // Road, lanes and ring sit just under the pin's tip (pin unit 46).
    final ground = dot + const Offset(0, 30.5 * _unit);
    if (road > 0) {
      final half = 75.7 * _unit * road;
      canvas.drawLine(
        ground - Offset(half, 0),
        ground + Offset(half, 0),
        Paint()
          ..color = PindoroPalette.cobalt600
          ..strokeWidth = 13.3 * _unit
          ..strokeCap = StrokeCap.round,
      );
    }
    if (lanes > 0) {
      final dash = Paint()
        ..color = PindoroPalette.yellow400.withValues(alpha: lanes)
        ..strokeWidth = 1.9 * _unit;
      const length = 7.2 * _unit, gap = 5.5 * _unit, half = 68.5 * _unit;
      for (var x = -half; x < half; x += length + gap) {
        canvas.drawLine(
          ground + Offset(x, 0),
          ground + Offset(math.min(x + length, half), 0),
          dash,
        );
      }
    }
    final ring = this.ring;
    if (ring != null && ring < 1) {
      canvas.drawOval(
        Rect.fromCenter(
          center: ground,
          width: 77 * _unit * _lerp(0.6, 1.25, ring),
          height: 22 * _unit * _lerp(0.6, 1.25, ring),
        ),
        Paint()
          ..color = PindoroPalette.yellow400.withValues(alpha: 0.7 * (1 - ring))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2 * _unit,
      );
    }
  }

  @override
  bool shouldRepaint(_Ground old) =>
      old.road != road ||
      old.lanes != lanes ||
      old.ring != ring ||
      old.dark != dark ||
      old.dot != dot;
}

/// Everything but a circle around [center] that grows to cover the screen
/// as [t] runs 0 → 1.
class _Hole extends CustomClipper<Path> {
  _Hole(this.center, this.t);

  final Offset center;
  final double t;

  @override
  Path getClip(Size size) {
    final path = Path()..addRect(Offset.zero & size);
    if (t == 0) return path;
    final reach = size.longestSide;
    return path
      ..addOval(Rect.fromCircle(center: center, radius: reach * t))
      ..fillType = PathFillType.evenOdd;
  }

  @override
  bool shouldReclip(_Hole old) => old.t != t || old.center != center;
}
