import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// A widget pinned to a map point: [foot], where in its box the point is, on [at].
class MapMark {
  const MapMark(this.at, this.child, {this.foot = Alignment.center});

  final LatLng at;
  final Widget child;
  final Alignment foot;
}

/// Paints [child] and hands [onPng] its picture at [pixelRatio] after each repaint (an icon
/// loaded, the theme changed), its [foot] at the picture's centre, with room around it for a
/// halo or a shadow. The map draws the picture as its own symbol, so it keeps to the ground as
/// the map moves, where a widget laid over the map trails its camera.
class MapSprite extends SingleChildRenderObjectWidget {
  const MapSprite({
    super.key,
    required this.foot,
    required this.pixelRatio,
    required this.onPng,
    required Widget super.child,
  });

  final Alignment foot;
  final double pixelRatio;
  final ValueChanged<Uint8List> onPng;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMapSprite(foot, pixelRatio, onPng);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderMapSprite)
        ..foot = foot
        ..pixelRatio = pixelRatio
        ..onPng = onPng;
}

class _RenderMapSprite extends RenderRepaintBoundary {
  _RenderMapSprite(this._foot, this._pixelRatio, this.onPng);

  /// Room around the child for its halo or float shadow.
  static const double _bleed = 24;

  Alignment _foot;
  set foot(Alignment value) {
    if (value == _foot) return;
    _foot = value;
    markNeedsLayout();
  }

  double _pixelRatio;
  set pixelRatio(double value) {
    if (value == _pixelRatio) return;
    _pixelRatio = value;
    markNeedsPaint();
  }

  ValueChanged<Uint8List> onPng;
  Offset _shift = Offset.zero;
  bool _capturing = false;
  bool _stale = false;

  @override
  void performLayout() {
    final child = this.child!
      ..layout(const BoxConstraints(), parentUsesSize: true);
    final box = child.size;
    final foot = _foot.alongSize(box);
    size = constraints.constrain(
      Size(
        2 * (math.max(foot.dx, box.width - foot.dx) + _bleed),
        2 * (math.max(foot.dy, box.height - foot.dy) + _bleed),
      ),
    );
    _shift = size.center(Offset.zero) - foot;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.paintChild(child!, offset + _shift);
    _capture();
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.translateByDouble(_shift.dx, _shift.dy, 0, 1);

  /// Pictures the sprite once the frame it painted in is done; a repaint meanwhile pictures it
  /// again after.
  void _capture() {
    _stale = true;
    if (_capturing) return;
    _capturing = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => unawaited(_send()))
      ..ensureVisualUpdate();
  }

  Future<void> _send() async {
    _stale = false;
    try {
      if (!attached) return;
      final image = await toImage(pixelRatio: _pixelRatio);
      try {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        if (png != null && attached) onPng(png.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    } finally {
      _capturing = false;
      if (_stale && attached) _capture();
    }
  }
}
