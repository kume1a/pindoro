import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// How much of the map its overlays cover at the top and the bottom, in dp.
typedef MapInsets = ({double top, double bottom});

/// A full-screen map under its overlays. [top] (in the top safe area, 16 dp
/// in) and [bottom] (on the bottom edge) are measured and [map] is built with
/// their heights, so its framing, controls and attribution clear them however
/// tall their text makes them. [behind] sits between the map and them (draw
/// layers, the coach reticle), [front] over everything (celebrations); both
/// are Stack children.
class MapLayout extends StatefulWidget {
  const MapLayout({
    super.key,
    required this.map,
    this.top,
    this.bottom,
    this.behind = const [],
    this.front = const [],
  });

  final Widget Function(MapInsets insets) map;
  final Widget? top;
  final Widget? bottom;
  final List<Widget> behind;
  final List<Widget> front;

  @override
  State<MapLayout> createState() => _MapLayoutState();
}

class _MapLayoutState extends State<MapLayout> {
  double _top = 0;
  double _bottom = 0;

  void _measured({double? top, double? bottom}) {
    if (!mounted) return;
    setState(() {
      _top = top ?? _top;
      _bottom = bottom ?? _bottom;
    });
  }

  @override
  Widget build(BuildContext context) {
    final top = widget.top;
    final bottom = widget.bottom;
    return Stack(
      children: [
        widget.map((
          top: top == null ? MediaQuery.paddingOf(context).top : _top,
          bottom: bottom == null ? 0 : _bottom,
        )),
        ...widget.behind,
        if (top != null)
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MeasureHeight(
                onHeight: (h) => _measured(top: h),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.all(PindoroSpace.s4),
                    child: top,
                  ),
                ),
              ),
            ],
          ),
        if (bottom != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: _MeasureHeight(
              onHeight: (h) => _measured(bottom: h),
              child: bottom,
            ),
          ),
        ...widget.front,
      ],
    );
  }
}

/// Hands [onHeight] its child's height after each layout that changed it.
class _MeasureHeight extends SingleChildRenderObjectWidget {
  const _MeasureHeight({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureHeight(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasureHeight renderObject,
  ) => renderObject.onHeight = onHeight;
}

class _RenderMeasureHeight extends RenderProxyBox {
  _RenderMeasureHeight(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    // Layout can't rebuild the map; it takes the height in the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}
