import 'dart:async';

import 'package:flutter/material.dart';

import '../../generated/pindoro_tokens.dart';
import 'entrances.dart';
import 'motion_parts.dart';

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
  ) => _PindoroPageTransition(animation: animation, child: child);
}

/// Keeps one [CurvedAnimation] per route animation: it listens to its parent
/// until disposed, and [PindoroPageTransitions.buildTransitions] runs on every
/// transition frame.
class _PindoroPageTransition extends StatefulWidget {
  const _PindoroPageTransition({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  State<_PindoroPageTransition> createState() => _PindoroPageTransitionState();
}

class _PindoroPageTransitionState extends State<_PindoroPageTransition> {
  late CurvedAnimation _curved;

  CurvedAnimation _curve(Animation<double> parent) => CurvedAnimation(
    parent: parent,
    curve: PindoroMotion.easeDecelerate,
    reverseCurve: PindoroMotion.easeAccelerate,
  );

  @override
  void initState() {
    super.initState();
    _curved = _curve(widget.animation);
  }

  @override
  void didUpdateWidget(_PindoroPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      _curved.dispose();
      _curved = _curve(widget.animation);
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = FadeTransition(opacity: _curved, child: widget.child);
    if (isCalm(context)) return fade;
    return AnimatedBuilder(
      animation: _curved,
      builder: (_, child) => Transform.translate(
        offset: Offset(PindoroSpace.s6 * (1 - _curved.value), 0),
        child: child,
      ),
      child: fade,
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
    final calm = isCalm(context);
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
    if (isCalm(context)) {
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
