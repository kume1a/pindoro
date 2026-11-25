import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../generated/pindoro_tokens.dart';
import 'motion_parts.dart';

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
  if (isCalm(context)) return (Duration.zero, curve);
  final total = delay + duration;
  return (
    total,
    Interval(delay.inMicroseconds / total.inMicroseconds, 1, curve: curve),
  );
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
    if (isCalm(context)) return child;
    final (duration, curve) = delayedMotion(
      context,
      delay,
      PindoroMotion.durationBase,
      PindoroMotion.easeLinear,
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
    final calm = isCalm(context);
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

/// A small celebration: the child wiggles ±6° once (`celebrate.small`).
class Wiggle extends StatelessWidget {
  const Wiggle({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => isCalm(context)
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

/// The error shake: the child jolts sideways 3 × 6 dp over 300 ms, once when
/// built (give it a new key to shake again). Still with reduce motion on.
class Shake extends StatelessWidget {
  const Shake({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => isCalm(context)
      ? child
      : TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 300),
          builder: (_, t, child) => Transform.translate(
            offset: Offset(math.sin(t * 3 * 2 * math.pi) * 6, 0),
            child: child,
          ),
          child: child,
        );
}

/// [builder] at 0 → 1 over [duration] on [curve], once, while [animate] and motion is on;
/// at 1 otherwise.
class GrowOnce extends StatelessWidget {
  const GrowOnce({
    super.key,
    required this.duration,
    required this.builder,
    this.curve = Curves.linear,
    this.animate = true,
  });

  final Duration duration;
  final Curve curve;
  final bool animate;
  final Widget Function(double t) builder;

  @override
  Widget build(BuildContext context) => animate && !isCalm(context)
      ? TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: duration,
          curve: curve,
          builder: (_, t, _) => builder(t),
        )
      : builder(1);
}
