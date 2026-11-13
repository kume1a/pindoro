import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The design box the scene is laid out in; it scales to fit its slot.
const Size _box = Size(320, 240);

/// The road across the middle of the box.
const double _roadTop = 108;
const double _roadHeight = 36;
const double _dash = 12;

/// The city's blocks in the order they're built; the top row leaves the
/// middle free for Pindo.
const List<({Rect rect, _Fill fill})> _blocks = [
  (rect: Rect.fromLTWH(12, 28, 60, 60), fill: _Fill.raised),
  (rect: Rect.fromLTWH(16, 160, 92, 60), fill: _Fill.alt),
  (rect: Rect.fromLTWH(80, 20, 40, 68), fill: _Fill.alt),
  (rect: Rect.fromLTWH(120, 160, 56, 68), fill: _Fill.raised),
  (rect: Rect.fromLTWH(200, 20, 44, 68), fill: _Fill.raised),
  (rect: Rect.fromLTWH(188, 160, 52, 56), fill: _Fill.park),
  (rect: Rect.fromLTWH(252, 32, 56, 56), fill: _Fill.park),
  (rect: Rect.fromLTWH(252, 160, 52, 64), fill: _Fill.alt),
];

enum _Fill { raised, alt, park }

/// A flat little city (the design system's Illustration style) that builds
/// as a pack downloads: a block pops in for each eighth of [progress]
/// (null: not started), and a star lands when it's all in. Pindo stands on
/// the road; while [moving], the lane dashes drive and Pindo floats.
/// Decorative: the panel under it speaks. Still with reduce motion on.
class CityScene extends StatefulWidget {
  const CityScene({
    super.key,
    required this.progress,
    required this.pindo,
    required this.moving,
  });

  final double? progress;
  final PindoExpression pindo;
  final bool moving;

  @override
  State<CityScene> createState() => _CitySceneState();
}

class _CitySceneState extends State<CityScene>
    with SingleTickerProviderStateMixin {
  /// One loop of Pindo's float; the lanes drive two dashes per loop.
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _drive();
  }

  @override
  void didUpdateWidget(CityScene old) {
    super.didUpdateWidget(old);
    _drive();
  }

  void _drive() {
    final run = widget.moving && !MediaQuery.disableAnimationsOf(context);
    if (run && !_loop.isAnimating) _loop.repeat();
    if (!run && _loop.value != 0) _loop.reset();
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final progress = widget.progress;
    final done = progress != null && progress >= 1;
    final park = _blocks[6].rect;
    return ExcludeSemantics(
      child: FittedBox(
        child: SizedBox.fromSize(
          size: _box,
          child: AnimatedBuilder(
            animation: _loop,
            builder: (context, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _Streets(
                      road: c.pathRoad,
                      lane: c.pathLane,
                      ghost: c.lineBase,
                      drive: _loop.value,
                    ),
                  ),
                ),
                for (final (i, b) in _blocks.indexed)
                  Positioned.fromRect(
                    rect: b.rect,
                    child: _Block(
                      built: progress != null && progress >= i / _blocks.length,
                      rank: i,
                      color: switch (b.fill) {
                        _Fill.raised => c.surfaceRaised,
                        _Fill.alt => c.illustrationBlockAlt,
                        _Fill.park => c.illustrationPark,
                      },
                    ),
                  ),
                if (done)
                  Positioned(
                    left: park.center.dx - 16,
                    top: park.top - 20,
                    child: PopIn(
                      child: PindoroIcon(
                        PindoroGlyph.star,
                        size: 32,
                        color: c.xpFill,
                        cut: c.primarySoft,
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: _box.height - _roadTop - _roadHeight / 2,
                  child: Transform.translate(
                    offset: Offset(
                      0,
                      math.sin(_loop.value * 2 * math.pi) * PindoroSpace.s1,
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(widget.pindo),
                      child: _pindo(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pindo() {
    final pindo = Center(child: Pindo(widget.pindo, height: 88));
    return widget.pindo == PindoExpression.cheering
        ? PopIn(child: pindo)
        : pindo;
  }
}

/// A city block: pops in (overshoot, staggered by [rank]) when [built],
/// shrinks away when not; a fade with reduce motion on.
class _Block extends StatelessWidget {
  const _Block({required this.built, required this.rank, required this.color});

  final bool built;
  final int rank;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final block = DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(PindoroRadius.lg),
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      return AnimatedOpacity(
        opacity: built ? 1 : 0,
        duration: calmFade,
        child: block,
      );
    }
    final (duration, curve) = delayedMotion(
      context,
      PindoroMotion.stagger * rank,
      PindoroMotion.durationBase,
      built ? PindoroMotion.easeOvershoot : PindoroMotion.easeAccelerate,
    );
    return AnimatedScale(
      scale: built ? 1 : 0,
      duration: duration,
      curve: curve,
      child: block,
    );
  }
}

/// The road with its lane dashes, shifted [drive] of a loop, and every
/// block's outline, where it will stand.
class _Streets extends CustomPainter {
  _Streets({
    required this.road,
    required this.lane,
    required this.ghost,
    required this.drive,
  });

  final Color road;
  final Color lane;
  final Color ghost;
  final double drive;

  @override
  void paint(Canvas canvas, Size size) {
    final street = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, _roadTop, size.width, _roadHeight),
      const Radius.circular(_roadHeight / 2),
    );
    canvas
      ..drawRRect(street, Paint()..color = road)
      ..save()
      ..clipRect(
        Rect.fromLTWH(
          _roadHeight / 2,
          _roadTop,
          size.width - _roadHeight,
          _roadHeight,
        ),
      );
    final dash = Paint()
      ..color = lane
      ..strokeWidth = PindoroSpace.s1;
    final y = _roadTop + _roadHeight / 2;
    for (
      var x = -4 * _dash + drive * 4 * _dash;
      x < size.width;
      x += 2 * _dash
    ) {
      canvas.drawLine(Offset(x, y), Offset(x + _dash, y), dash);
    }
    canvas.restore();
    final outline = Paint()
      ..color = ghost
      ..style = PaintingStyle.stroke
      ..strokeWidth = PindoroStroke.base;
    for (final b in _blocks) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          b.rect.deflate(PindoroStroke.base / 2),
          const Radius.circular(PindoroRadius.lg),
        ),
        outline,
      );
    }
  }

  @override
  bool shouldRepaint(_Streets old) =>
      old.drive != drive ||
      old.road != road ||
      old.lane != lane ||
      old.ghost != ghost;
}
