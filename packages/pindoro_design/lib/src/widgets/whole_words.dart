import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// [text] broken only between its words: when its widest word is wider than the room, the
/// whole text shrinks, as a FittedBox would, until that word fits, and still wraps between
/// words. A long Georgian word would otherwise be split in two.
class WholeWords extends StatelessWidget {
  const WholeWords(this.text, {super.key});

  /// A plain [Text] (not `Text.rich`).
  final Text text;

  @override
  Widget build(BuildContext context) => _WordFit(
    words: text.data!.split(_space),
    style: textStyleAsShown(
      context,
      DefaultTextStyle.of(context).style.merge(text.style),
    ),
    scaler: text.textScaler ?? MediaQuery.textScalerOf(context),
    direction: text.textDirection ?? Directionality.of(context),
    child: text,
  );
}

final RegExp _space = RegExp(r'\s+');

/// [text]'s width on one line in [style] at [scaler].
double textWidth(
  String text,
  TextStyle style, {
  TextScaler scaler = TextScaler.noScaling,
  TextDirection direction = TextDirection.ltr,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: direction,
    textScaler: scaler,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// The widest of [words] on one line, as [textWidth] measures each.
double widestWordWidth(
  Iterable<String> words,
  TextStyle style, {
  TextScaler scaler = TextScaler.noScaling,
  TextDirection direction = TextDirection.ltr,
}) => words.fold(
  0,
  (widest, word) => math.max(
    widest,
    textWidth(word, style, scaler: scaler, direction: direction),
  ),
);

/// [style] as a [Text] lays it out: bold when the platform asks for bold text.
TextStyle textStyleAsShown(BuildContext context, TextStyle style) =>
    MediaQuery.boldTextOf(context)
    ? style.merge(const TextStyle(fontWeight: FontWeight.bold))
    : style;

class _WordFit extends SingleChildRenderObjectWidget {
  const _WordFit({
    required this.words,
    required this.style,
    required this.scaler,
    required this.direction,
    required Widget super.child,
  });

  final List<String> words;
  final TextStyle style;
  final TextScaler scaler;
  final TextDirection direction;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderWordFit(words, style, scaler, direction);

  @override
  void updateRenderObject(BuildContext context, _RenderWordFit renderObject) =>
      renderObject.measure(words, style, scaler, direction);
}

class _RenderWordFit extends RenderProxyBox {
  _RenderWordFit(this._words, this._style, this._scaler, this._direction);

  List<String> _words;
  TextStyle _style;
  TextScaler _scaler;
  TextDirection _direction;

  /// The widest word's width, measured once per text and style.
  double? _widest;

  /// The child's paint scale from the last layout.
  double _scale = 1;

  void measure(
    List<String> words,
    TextStyle style,
    TextScaler scaler,
    TextDirection direction,
  ) {
    if (listEquals(words, _words) &&
        style == _style &&
        scaler == _scaler &&
        direction == _direction) {
      return;
    }
    _words = words;
    _style = style;
    _scaler = scaler;
    _direction = direction;
    _widest = null;
    markNeedsLayout();
  }

  double get _widestWord => _widest ??= widestWordWidth(
    _words,
    _style,
    scaler: _scaler,
    direction: _direction,
  );

  double _scaleFor(double maxWidth) =>
      maxWidth.isFinite && _widestWord > maxWidth && maxWidth > 0
      ? maxWidth / _widestWord
      : 1;

  static BoxConstraints _unscaled(BoxConstraints c, double s) => s == 1
      ? c
      : BoxConstraints(
          minWidth: c.minWidth / s,
          maxWidth: c.maxWidth / s,
          minHeight: c.minHeight / s,
          maxHeight: c.maxHeight / s,
        );

  Matrix4 get _transform => Matrix4.diagonal3Values(_scale, _scale, 1);

  @override
  void performLayout() {
    final child = this.child!;
    _scale = _scaleFor(constraints.maxWidth);
    child.layout(_unscaled(constraints, _scale), parentUsesSize: true);
    size = constraints.constrain(child.size * _scale);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final s = _scaleFor(constraints.maxWidth);
    return constraints.constrain(
      child!.getDryLayout(_unscaled(constraints, s)) * s,
    );
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    final s = _scaleFor(width);
    return child!.getMinIntrinsicHeight(width / s) * s;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final s = _scaleFor(width);
    return child!.getMaxIntrinsicHeight(width / s) * s;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      switch (child!.getDistanceToActualBaseline(baseline)) {
        final d? => d * _scale,
        null => null,
      };

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_scale == 1) {
      layer = null;
      return super.paint(context, offset);
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      super.paint,
      oldLayer: layer is TransformLayer ? layer! as TransformLayer : null,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintTransform(
        transform: _scale == 1 ? null : _transform,
        position: position,
        hitTest: (result, position) =>
            child!.hitTest(result, position: position),
      );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (_scale != 1) transform.multiply(_transform);
  }
}
