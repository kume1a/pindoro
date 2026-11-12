import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pindoro/features/course/ui/path_stops.dart';
import 'package:pindoro/features/course/ui/widgets/path_unit.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Where the unlock plays: the finished stop and the new current one, each
/// as (unit index, stop index); [unitOpens] when a Final drive opened the
/// next unit (canvas R4-61).
typedef UnlockStops = ({
  int unit,
  int done,
  ({int unit, int stop}) next,
  bool unitOpens,
});

/// The unlock storyboard (canvas R4-60), as fractions of its 900 ms: the
/// finished stop pops to 200 ms, the road paves to 620 ms, then the next
/// stop grows in with an overshoot.
abstract final class _UnlockAt {
  static const Duration length = Duration(milliseconds: 900);
  static const double settle = 200 / 900;
  static const double paved = 620 / 900;
  static const double burst = 420 / 900;
  static const double overshoot = 1.12;

  static double _part(double t, double from, double to) =>
      ((t - from) / (to - from)).clamp(0, 1);

  /// The next unit opening (canvas R4-61): its signpost flips from 280 ms
  /// over `duration.base`, its road fades up over `duration.slow`.
  static const double flipFrom = 280 / 900;
  static const double flipTo = (280 + 280) / 900;
  static const double fadeTo = (280 + 420) / 900;

  static double flip(double t) => _part(t, flipFrom, flipTo);

  static double fade(double t) => _part(t, flipFrom, fadeTo);

  /// The finished stop's pop.
  static double pop(double t) =>
      1 + 0.2 * math.sin(math.pi * _part(t, 0, settle));

  static double pave(double t) => _part(t, settle, paved);

  /// The next stop, from a small stop's size up through the overshoot.
  static double grow(double t) {
    final g = _part(t, paved, 1);
    const small = PindoroSize.nodeStop / PindoroSize.nodeCurrent;
    return g < 0.6
        ? small + (overshoot - small) * (g / 0.6)
        : overshoot + (1 - overshoot) * ((g - 0.6) / 0.4);
  }
}

/// The unlock on the Path (canvas R4-60, R4-61), frame by frame: how it
/// changes each unit's stops, road and signpost while it plays.
/// [onUnitFlip] fires as an opening unit's signpost flips, [onPaved] once the
/// road reaches the new stop, and [onFrame] on every frame.
class UnlockPlayer {
  UnlockPlayer({
    required TickerProvider vsync,
    required this.onUnitFlip,
    required this.onPaved,
    required VoidCallback onFrame,
  }) : _clock = AnimationController(vsync: vsync, duration: _UnlockAt.length) {
    _clock.addListener(() {
      _tick();
      onFrame();
    });
  }

  final AnimationController _clock;
  final VoidCallback onUnitFlip;

  /// Gets whether the unlock opened a unit (its flip already spoke).
  final void Function({required bool unitOpens}) onPaved;

  UnlockStops? _stops;
  bool _paved = false;
  bool _flipped = false;

  double get _t => _clock.value;

  void play(UnlockStops stops) {
    _stops = stops;
    _paved = false;
    _flipped = false;
    unawaited(_clock.forward(from: 0));
  }

  void dispose() => _clock.dispose();

  void _tick() {
    final unitOpens = _stops?.unitOpens ?? false;
    if (unitOpens && !_flipped && _t >= _UnlockAt.flipFrom) {
      _flipped = true;
      onUnitFlip();
    }
    if (!_paved && _t >= _UnlockAt.paved) {
      _paved = true;
      onPaved(unitOpens: unitOpens);
    }
    if (_clock.isCompleted) _stops = null;
  }

  /// [views] of unit [u] as the unlock shows them now: the finished stop
  /// plain and big until it settles, the next one locked until the road
  /// reaches it.
  List<StopView> stops(int u, List<StopView> views) {
    final stops = _stops;
    if (stops == null) return views;
    return [
      for (final (i, v) in views.indexed)
        if (u == stops.unit && i == stops.done && _t < _UnlockAt.settle)
          v.copyWith(big: true, ring: () => null, tip: () => null)
        else if (u == stops.next.unit &&
            i == stops.next.stop &&
            _t < _UnlockAt.paved)
          v.copyWith(
            look: PathStopLook.locked,
            glyph: v.glyph == PindoroGlyph.wrench
                ? PindoroGlyph.wrench
                : PindoroGlyph.lock,
            big: true,
            ring: () => null,
            tip: () => null,
          )
        else
          v,
    ];
  }

  double? scale(int u, int i) {
    final stops = _stops;
    if (stops == null) return null;
    if (u == stops.unit && i == stops.done) return _UnlockAt.pop(_t);
    if (u == stops.next.unit && i == stops.next.stop) {
      return _t < _UnlockAt.paved
          ? PindoroSize.nodeStop / PindoroSize.nodeCurrent
          : _UnlockAt.grow(_t);
    }
    return null;
  }

  ({int stop, double t})? burst(int u) {
    final stops = _stops;
    if (stops == null || stops.unit != u) return null;
    return (stop: stops.done, t: (_t / _UnlockAt.burst).clamp(0.0, 1.0));
  }

  /// A locked unit's road is faint; the unit opening fades it up.
  double roadOpacity(int u, UnitProgress progress) {
    final stops = _stops;
    if (stops != null && stops.unitOpens && stops.next.unit == u) {
      const from = PathUnit.lockedRoadOpacity;
      return from + (1 - from) * _UnlockAt.fade(_t);
    }
    return progress.open ? 1 : PathUnit.lockedRoadOpacity;
  }

  /// The opening unit's signpost flips on X: the locked face turns away,
  /// the open face turns in.
  Widget signpost(int u, bool open, Widget Function(bool locked) sign) {
    final stops = _stops;
    if (stops == null || !stops.unitOpens || stops.next.unit != u) {
      return sign(!open);
    }
    final f = _UnlockAt.flip(_t);
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.002)
        ..rotateX((f < 0.5 ? f : 1 - f) * math.pi),
      child: sign(f < 0.5),
    );
  }

  /// How far unit [u]'s road reaches: paving towards the new stop until it
  /// gets there, else [driven].
  double driven(int u, double driven) {
    final stops = _stops;
    if (stops == null ||
        u != stops.unit ||
        stops.next.unit != u ||
        _t >= _UnlockAt.paved) {
      return driven;
    }
    return pavedTo(
      done: stops.done,
      next: stops.next.stop,
      driven: driven,
      t: _UnlockAt.pave(_t),
    );
  }
}
