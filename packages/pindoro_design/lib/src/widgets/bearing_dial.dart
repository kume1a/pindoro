import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';
import 'painters.dart';

/// The dial's reference size: every length in the painter spec is at 280 dp.
const double _reference = 280;

/// One tick, and one step of the keyboard or a screen reader's swipe.
const double _tickDeg = 30;

/// [b] in 0 … 360.
double _normal(double b) => b % 360;

/// The compass for bearing questions (Bearing dial): drag anywhere on it to
/// point your arrow (cobalt, dashed); with [trueBearing] set (after Check) the
/// truth shows in yellow with the ink angle between them, and dragging is off.
/// Bearings are degrees clockwise from north. [describeBearing] names a
/// bearing for screen readers ("west-north-west"); [semanticsLabel] names the
/// control ("Compass"); [caption] goes under the dial; [northLabel] marks north ("N").
class BearingDial extends StatefulWidget {
  const BearingDial({
    super.key,
    required this.playerBearing,
    required this.onChanged,
    required this.caption,
    required this.semanticsLabel,
    required this.describeBearing,
    required this.northLabel,
    this.trueBearing,
    this.enabled = true,
    this.animate = false,
    this.calibrating = false,
    this.degrees,
  });

  final double playerBearing;
  final ValueChanged<double> onChanged;
  final String caption;
  final String semanticsLabel;
  final String Function(double bearing) describeBearing;
  final String northLabel;

  /// Null before Check.
  final double? trueBearing;

  /// False after Check.
  final bool enabled;

  /// The truth and the angle fade in as Check lands; never under reduce
  /// motion.
  final bool animate;

  /// Pointing mode: the compass needs a moment, so your arrow greys out.
  final bool calibrating;

  /// Pointing mode: the angle between the two ("18°"), drawn on the arc
  /// once [trueBearing] is set.
  final String? degrees;

  @override
  State<BearingDial> createState() => _BearingDialState();
}

class _BearingDialState extends State<BearingDial> {
  bool _focused = false;

  bool get _live => widget.enabled && widget.trueBearing == null;

  void _turn(double by) {
    if (_live) widget.onChanged(_normal(widget.playerBearing + by));
  }

  void _point(Offset local, double side) {
    if (!_live) return;
    final d = local - Offset(side / 2, side / 2);
    if (d == Offset.zero) return;
    widget.onChanged(_normal(math.atan2(d.dx, -d.dy) * 180 / math.pi));
  }

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final player = widget.playerBearing;
    final truth = widget.trueBearing;
    final moving = widget.animate && !MediaQuery.disableAnimationsOf(context);
    Widget dial(double side, double reveal) => CustomPaint(
      size: Size.square(side),
      painter: _BearingDialPainter(
        player: player,
        truth: truth,
        reveal: reveal,
        focused: _focused,
        colors: c,
        calibrating: widget.calibrating,
        degrees: widget.degrees,
        northLabel: widget.northLabel,
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: PindoroSpace.s2,
      children: [
        Semantics(
          slider: true,
          enabled: _live,
          label: widget.semanticsLabel,
          value: widget.describeBearing(player),
          increasedValue: widget.describeBearing(_normal(player + _tickDeg)),
          decreasedValue: widget.describeBearing(_normal(player - _tickDeg)),
          onIncrease: _live ? () => _turn(_tickDeg) : null,
          onDecrease: _live ? () => _turn(-_tickDeg) : null,
          child: FocusableActionDetector(
            enabled: _live,
            onShowFocusHighlight: (on) => setState(() => _focused = on),
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.arrowUp): _TurnIntent(1),
              SingleActivator(LogicalKeyboardKey.arrowRight): _TurnIntent(1),
              SingleActivator(LogicalKeyboardKey.arrowDown): _TurnIntent(-1),
              SingleActivator(LogicalKeyboardKey.arrowLeft): _TurnIntent(-1),
            },
            actions: {
              _TurnIntent: CallbackAction<_TurnIntent>(
                onInvoke: (i) => _turn(i.direction * _tickDeg),
              ),
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final side = math.min(_reference, constraints.maxWidth);
                return GestureDetector(
                  // The slider's increase and decrease stand in for the drag.
                  excludeFromSemantics: true,
                  onPanDown: (d) => _point(d.localPosition, side),
                  onPanUpdate: (d) => _point(d.localPosition, side),
                  child: truth != null && moving
                      ? TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: PindoroMotion.durationBase,
                          curve: PindoroMotion.easeDecelerate,
                          builder: (_, t, _) => dial(side, t),
                        )
                      : dial(side, 1),
                );
              },
            ),
          ),
        ),
        Text(
          widget.caption,
          textAlign: TextAlign.center,
          style: PindoroType.labelMd.copyWith(color: c.textSecondary),
        ),
      ],
    );
  }
}

class _TurnIntent extends Intent {
  const _TurnIntent(this.direction);

  /// +1 clockwise, −1 anticlockwise.
  final int direction;
}

/// The signed shorter turn from [from] to [to], in −180 … 180 degrees.
double _shorterTurn(double from, double to) => (to - from + 540) % 360 - 180;

/// The Bearing dial painter spec, layer by layer, at 280 dp scaled to the
/// canvas.
class _BearingDialPainter extends CustomPainter {
  _BearingDialPainter({
    required this.player,
    required this.truth,
    required this.reveal,
    required this.focused,
    required this.colors,
    required this.northLabel,
    this.calibrating = false,
    this.degrees,
  });

  final double player;
  final double? truth;

  /// How far the truth and the angle have faded in, 0 … 1.
  final double reveal;
  final bool focused;
  final PindoroColors colors;
  final bool calibrating;
  final String? degrees;
  final String northLabel;

  static double _rad(double deg) => deg * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / _reference;
    final c = size.center(Offset.zero);
    Offset pt(double bearing, double r) => c.translate(
      r * s * math.sin(_rad(bearing)),
      -r * s * math.cos(_rad(bearing)),
    );
    Paint stroke(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * s
      ..strokeCap = StrokeCap.round;

    canvas
      ..drawCircle(c, 128 * s, Paint()..color = colors.surfaceRaised)
      ..drawCircle(c, 128 * s, stroke(colors.lineBase, PindoroStroke.base));
    if (focused) {
      canvas.drawCircle(
        c,
        (_reference / 2 + PindoroStroke.base + PindoroStroke.thick / 2) * s,
        stroke(colors.focusRing, PindoroStroke.thick),
      );
    }
    for (var t = 0.0; t < 360; t += _tickDeg) {
      final major = t % 90 == 0;
      canvas.drawLine(
        pt(t, 106),
        pt(t, major ? 124 : 118),
        stroke(colors.textSecondary, major ? 3 : 2),
      );
    }
    final north = TextPainter(
      text: TextSpan(
        text: northLabel,
        style: PindoroType.titleSm.copyWith(
          color: colors.textPrimary,
          fontSize: PindoroType.titleSm.fontSize! * s,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    north.paint(
      canvas,
      Offset(
        c.dx - north.width / 2,
        c.dy -
            88 * s -
            north.computeDistanceToActualBaseline(TextBaseline.alphabetic),
      ),
    );
    north.dispose();
    final truth = this.truth;
    Color shown(Color color) => color.withValues(alpha: color.a * reveal);
    if (truth != null) {
      canvas
        ..drawLine(c, pt(truth, 108), stroke(shown(colors.mapAnswerCasing), 12))
        ..drawLine(c, pt(truth, 108), stroke(shown(colors.mapAnswerLine), 8));
    }
    final arrow = Path()
      ..moveTo(c.dx, c.dy)
      ..lineTo(pt(player, 100).dx, pt(player, 100).dy);
    final dashes = dashedPath(arrow, dash: 10 * s, period: 18 * s);
    canvas.drawPath(
      dashes,
      stroke(calibrating ? colors.textDisabled : colors.mapPlayerRoute, 6),
    );
    if (truth != null) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: 76 * s),
        _rad(player - 90),
        _rad(_shorterTurn(player, truth)),
        false,
        stroke(shown(colors.mapMeasureLine), PindoroStroke.thick),
      );
    }
    canvas.drawCircle(c, 10 * s, Paint()..color = colors.mapPlayerPin);
    final degrees = this.degrees;
    if (truth != null && degrees != null) {
      // On the arc's bisector, over a halo of the face so it reads across
      // the lines.
      final at = pt(player + _shorterTurn(player, truth) / 2, 52);
      for (final paint in [
        stroke(shown(colors.surfaceRaised), 5)..strokeJoin = StrokeJoin.round,
        Paint()..color = shown(colors.mapMeasureLine),
      ]) {
        final text = TextPainter(
          text: TextSpan(
            text: degrees,
            style: PindoroType.labelMd.copyWith(
              fontSize: 15 * s,
              height: 1,
              fontWeight: FontWeight.w900,
              foreground: paint,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text
          ..paint(canvas, at - Offset(text.width / 2, text.height / 2))
          ..dispose();
      }
    }
  }

  @override
  bool shouldRepaint(_BearingDialPainter old) =>
      old.player != player ||
      old.truth != truth ||
      old.reveal != reveal ||
      old.focused != focused ||
      old.colors != colors ||
      old.calibrating != calibrating ||
      old.degrees != degrees ||
      old.northLabel != northLabel;
}

/// The pointing result under the dial (Bearing dial, pointing mode): a 40 dp
/// pill in the [tier]'s background with a 2 dp edge in its fill, the tier's
/// icon and [label] ("Great · 18° off") in its ink.
class DialResultChip extends StatelessWidget {
  const DialResultChip({super.key, required this.tier, required this.label});

  final Tier tier;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = PindoroTheme.of(context).tier(tier);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: PindoroSpace.s10),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: t.bg,
          shape: StadiumBorder(
            side: BorderSide(color: t.fill, width: PindoroStroke.base),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PindoroSpace.s4,
            vertical: PindoroSpace.s1,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: PindoroSpace.s2,
            children: [
              PindoroIcon(t.icon, size: 22, color: t.ink, cut: t.bg),
              Flexible(
                child: Text(
                  label,
                  style: PindoroType.labelLg.copyWith(
                    fontSize: 17,
                    height: 22 / 17,
                    fontWeight: FontWeight.w900,
                    color: t.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
