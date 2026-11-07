import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';

bool _calm(BuildContext context) => MediaQuery.disableAnimationsOf(context);

/// What a rise or slide becomes with reduce motion on: a short cross-fade.
const Duration calmFade = Duration(milliseconds: 150);

/// Duration and curve for an implicit animation that waits [delay], then runs
/// [duration] with [curve]; instant with reduce motion on.
(Duration, Curve) delayedMotion(
  BuildContext context,
  Duration delay,
  Duration duration,
  Curve curve,
) {
  if (_calm(context)) return (Duration.zero, curve);
  final total = delay + duration;
  return (
    total,
    Interval(delay.inMicroseconds / total.inMicroseconds, 1, curve: curve),
  );
}

/// Push: slide 24 dp + fade in (`duration.base`, decelerate); pop: back out
/// (`duration.fast`, accelerate). Reduce motion: a plain fade.
class PindoroPageTransitions extends PageTransitionsBuilder {
  const PindoroPageTransitions();

  @override
  Duration get transitionDuration => PindoroMotion.durationBase;

  @override
  Duration get reverseTransitionDuration => PindoroMotion.durationFast;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: PindoroMotion.easeDecelerate,
      reverseCurve: PindoroMotion.easeAccelerate,
    );
    final fade = FadeTransition(opacity: curved, child: child);
    if (_calm(context)) return fade;
    return AnimatedBuilder(
      animation: curved,
      builder: (_, child) => Transform.translate(
        offset: Offset(PindoroSpace.s6 * (1 - curved.value), 0),
        child: child,
      ),
      child: fade,
    );
  }
}

/// A number that rolls up from [from] to [value] (`motion.count-up`) after
/// [delay], calling [onEnd] when it lands; shows the final value at once when
/// reduce motion is on.
class CountUp extends StatelessWidget {
  const CountUp({
    super.key,
    required this.value,
    required this.builder,
    this.from = 0,
    this.delay = Duration.zero,
    this.onEnd,
  });

  final int value;
  final int from;
  final Duration delay;
  final VoidCallback? onEnd;
  final Widget Function(BuildContext context, int value) builder;

  @override
  Widget build(BuildContext context) {
    final (duration, curve) = delayedMotion(
      context,
      delay,
      PindoroMotion.countUp,
      Curves.easeOutCubic,
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: from.toDouble(), end: value.toDouble()),
      duration: duration,
      curve: curve,
      onEnd: onEnd,
      builder: (context, v, _) => builder(context, v.round()),
    );
  }
}

/// Pops [child] in from 0.4 with a springy overshoot after [delay]; there at
/// once with reduce motion on.
class PopIn extends StatelessWidget {
  const PopIn({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (_calm(context)) return child;
    final (duration, curve) = delayedMotion(
      context,
      delay,
      PindoroMotion.durationBase,
      Curves.linear,
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: curve,
      builder: (_, t, child) => Transform.scale(
        scale: 0.4 + 0.6 * PindoroMotion.easeOvershoot.transform(t),
        child: Opacity(opacity: t, child: child),
      ),
      child: child,
    );
  }
}

/// Rises [distance] dp from below on first build, after [delay]
/// (`duration.base`, decelerate); fades in place when reduce motion is on.
class RiseIn extends StatelessWidget {
  const RiseIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.distance = 48,
  });

  final Widget child;
  final Duration delay;
  final double distance;

  @override
  Widget build(BuildContext context) {
    final calm = _calm(context);
    final total = (calm ? calmFade : PindoroMotion.durationBase) + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: PindoroMotion.easeDecelerate,
      ),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, calm ? 0 : distance * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Swaps its keyed [child]: the new one rises in (`duration.base`,
/// decelerate) as the old one leaves (`duration.fast`, accelerate); a
/// [calmFade] cross-fade when reduce motion is on.
class RiseSwitcher extends StatelessWidget {
  const RiseSwitcher({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final calm = _calm(context);
    return AnimatedSwitcher(
      duration: calm ? calmFade : PindoroMotion.durationBase,
      reverseDuration: calm ? calmFade : PindoroMotion.durationFast,
      switchInCurve: PindoroMotion.easeDecelerate,
      switchOutCurve: PindoroMotion.easeAccelerate,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: calm
            ? child
            : SlideTransition(
                position: animation.drive(
                  Tween(begin: const Offset(0, 0.15), end: Offset.zero),
                ),
                child: child,
              ),
      ),
      child: child,
    );
  }
}

/// Shows [child] through a circle growing from [center] (global
/// coordinates) as [progress] runs 0 → 1, until it covers the screen.
class CircleReveal extends StatelessWidget {
  const CircleReveal({
    super.key,
    required this.progress,
    required this.center,
    required this.child,
  });

  final Animation<double> progress;
  final Offset center;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: progress,
    builder: (context, child) =>
        ClipPath(clipper: _CircleClipper(center, progress.value), child: child),
    child: child,
  );
}

class _CircleClipper extends CustomClipper<Path> {
  _CircleClipper(this.center, this.t);

  final Offset center;
  final double t;

  @override
  Path getClip(Size size) {
    final reach = [
      Offset.zero,
      size.topRight(Offset.zero),
      size.bottomLeft(Offset.zero),
      size.bottomRight(Offset.zero),
    ].map((corner) => (corner - center).distance).reduce(math.max);
    return Path()..addOval(Rect.fromCircle(center: center, radius: reach * t));
  }

  @override
  bool shouldReclip(_CircleClipper old) => old.t != t || old.center != center;
}

enum CelebrationSize { small, medium, big }

/// The celebration for a tier: big for a Perfect, medium for a Great, small
/// for a Close, none for a Miss. Repeats calm down: a round's second Perfect
/// gets the medium one, and from the fifth Great-or-better in a row a Great
/// only pops its badge.
CelebrationSize? celebrationFor(
  Tier tier, {
  int perfectsThisRound = 1,
  int inARow = 1,
}) => switch (tier) {
  Tier.perfect when perfectsThisRound > 1 => CelebrationSize.medium,
  Tier.perfect => CelebrationSize.big,
  Tier.great when inARow >= 5 => null,
  Tier.great => CelebrationSize.medium,
  Tier.close => CelebrationSize.small,
  Tier.miss => null,
};

/// Lane-dash and star confetti (big), a 12-dash burst around [burstCenter]
/// (medium and big) and a lane-yellow edge glow (big). Never blocks input;
/// nothing at all with reduce motion on.
class Celebration extends StatefulWidget {
  const Celebration({super.key, required this.size, this.burstCenter});

  final CelebrationSize size;

  /// Where the burst radiates from, as an alignment in the overlay.
  final Alignment? burstCenter;

  @override
  State<Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<Celebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: switch (widget.size) {
      CelebrationSize.small => PindoroMotion.celebrateSmall,
      CelebrationSize.medium => PindoroMotion.celebrateMedium,
      CelebrationSize.big => PindoroMotion.celebrateBig,
    },
  )..forward();

  final _pieces = [
    for (var i = 0; i < 28; i++)
      (
        x: math.Random(i).nextDouble(),
        delay: math.Random(i + 99).nextDouble() * 0.3,
        spin: math.Random(i + 7).nextDouble() * 6 - 3,
        star: i % 4 == 0,
        cobalt: i % 7 == 3,
      ),
  ];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_calm(context) || widget.size == CelebrationSize.small) {
      return const SizedBox.shrink();
    }
    final colors = PindoroTheme.of(context).colors;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(
          size: Size.infinite,
          painter: _CelebrationPainter(
            t: _c.value,
            big: widget.size == CelebrationSize.big,
            burstCenter: widget.burstCenter ?? Alignment.center,
            pieces: _pieces,
            colors: colors,
          ),
        ),
      ),
    );
  }
}

class _CelebrationPainter extends CustomPainter {
  _CelebrationPainter({
    required this.t,
    required this.big,
    required this.burstCenter,
    required this.pieces,
    required this.colors,
  });

  final double t;
  final bool big;
  final Alignment burstCenter;
  final List<({double x, double delay, double spin, bool star, bool cobalt})>
  pieces;
  final PindoroColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final dash = Paint()
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    // 12 lane dashes flying out from the badge.
    final burst = (t * 2.5).clamp(0.0, 1.0);
    if (burst < 1) {
      final center = burstCenter.alongSize(size);
      dash.color = colors.accentBase.withValues(alpha: 1 - burst);
      for (var i = 0; i < 12; i++) {
        final a = 2 * math.pi * i / 12;
        final dir = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(
          center + dir * (28 + 40 * burst),
          center + dir * (38 + 52 * burst),
          dash,
        );
      }
    }
    if (!big) return;
    // Confetti showering from the top.
    for (final p in pieces) {
      final life = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (life <= 0 || life >= 1) continue;
      final at = Offset(p.x * size.width, -20 + life * (size.height * 0.9));
      final color = p.cobalt ? colors.primaryBase : colors.accentBase;
      canvas
        ..save()
        ..translate(at.dx, at.dy)
        ..rotate(p.spin * life * math.pi);
      if (p.star) {
        canvas.drawPath(_star(6), Paint()..color = color);
      } else {
        canvas.drawLine(
          const Offset(-6, 0),
          const Offset(6, 0),
          dash..color = color.withValues(alpha: 1 - life * 0.3),
        );
      }
      canvas.restore();
    }
    // A 10 dp lane-yellow glow around the screen edge, pulsing once.
    final glow = math.sin(t * math.pi);
    canvas.drawRect(
      (Offset.zero & size).deflate(5),
      Paint()
        ..color = colors.accentBase.withValues(alpha: 0.6 * glow)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  static Path _star(double r) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? r : r / 2.4;
      final a = -math.pi / 2 + i * math.pi / 5;
      final point = Offset(radius * math.cos(a), radius * math.sin(a));
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_CelebrationPainter old) => old.t != t;
}

/// A small celebration: the child wiggles ±6° once (`celebrate.small`).
class Wiggle extends StatelessWidget {
  const Wiggle({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => _calm(context)
      ? child
      : TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: PindoroMotion.celebrateSmall,
          builder: (_, t, child) => Transform.rotate(
            angle: math.sin(t * 3 * math.pi) * (1 - t) * 6 * math.pi / 180,
            child: child,
          ),
          child: child,
        );
}

/// An [IndexedStack] that cross-fades to [index] (`duration.fast`); every
/// child keeps its state, the hidden ones offstage with tickers off.
/// Instant with reduce motion on.
class FadeIndexedStack extends StatefulWidget {
  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: PindoroMotion.durationFast,
    value: 1,
  )..addStatusListener(_settled);

  /// The child fading out, until the fade ends.
  int? _leaving;

  void _settled(AnimationStatus status) {
    if (status.isCompleted) setState(() => _leaving = null);
  }

  @override
  void didUpdateWidget(FadeIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;
    if (_calm(context)) {
      _leaving = null;
      _fade.value = 1;
      return;
    }
    _leaving = old.index;
    unawaited(_fade.forward(from: 0));
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  Animation<double> _opacity(int i) => i == widget.index
      ? _fade
      : i == _leaving
      ? ReverseAnimation(_fade)
      : kAlwaysCompleteAnimation;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      for (final (i, child) in widget.children.indexed)
        Offstage(
          offstage: i != widget.index && i != _leaving,
          child: TickerMode(
            enabled: i == widget.index,
            child: IgnorePointer(
              ignoring: i != widget.index,
              child: FadeTransition(opacity: _opacity(i), child: child),
            ),
          ),
        ),
    ],
  );
}
