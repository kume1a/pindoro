import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pindoro/features/map/ui/route_projection.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// A drag that starts this close to the route's end draws (canvas R4-30).
const double drawStartRadius = 40;

/// The finger snaps to an edge (and passes a junction) within this.
const double snapDp = 28;

/// The finger dot (`.pd-map-finger`) and the next-junction ring
/// (`.pd-map-junction`).
const double _fingerRadius = 10;
const double _ringRadius = 14;

/// Draws a road trip by dragging over the map: a one-finger drag that starts
/// within [drawStartRadius] of the route's end walks the route along the
/// streets ([RouteDraft.follow]); any other drag goes to the map below. While
/// drawing it paints the finger, a ring on the next junction and, off the
/// road, a rubber band from the route's end. [onTouch] hears every touch
/// (the first-trip ghost hides); [onOffRoad] says when the finger leaves or
/// rejoins the streets.
class RouteDrawLayer extends StatefulWidget {
  const RouteDrawLayer({
    super.key,
    required this.projection,
    required this.draft,
    required this.onDraft,
    required this.onTouch,
    required this.onOffRoad,
  });

  final MapProjection? projection;
  final RouteDraft draft;
  final ValueChanged<RouteDraft> onDraft;
  final VoidCallback onTouch;
  final ValueChanged<bool> onOffRoad;

  @override
  State<RouteDrawLayer> createState() => _RouteDrawLayerState();
}

class _RouteDrawLayerState extends State<RouteDrawLayer> {
  late RouteDraft _draft = widget.draft;
  Offset? _finger;
  LatLng? _last;
  RoadEdge? _heading;
  bool _offRoad = false;

  @override
  void didUpdateWidget(RouteDrawLayer old) {
    super.didUpdateWidget(old);
    if (!identical(widget.draft, old.draft)) _draft = widget.draft;
  }

  bool _startsNearEnd(Offset global) {
    final projection = widget.projection;
    final box = context.findRenderObject() as RenderBox?;
    if (projection == null || box == null || _draft.reached) return false;
    final end = projection.toScreen(_draft.graph.at(_draft.end));
    return (box.globalToLocal(global) - end).distance <= drawStartRadius;
  }

  void _move(Offset local) {
    final projection = widget.projection;
    if (projection == null) return;
    final finger = projection.toLatLng(local);
    final snapM = snapDp * projection.metresPerDp(finger);
    final next = _draft.follow(finger, snapM, from: _last);
    _last = finger;
    final heading = next.heading(finger, snapM);
    _setOffRoad(heading == null && !next.reached);
    setState(() {
      _finger = local;
      _heading = heading;
    });
    if (!identical(next, _draft)) {
      _draft = next;
      widget.onDraft(next);
    }
  }

  void _setOffRoad(bool off) {
    if (off == _offRoad) return;
    _offRoad = off;
    widget.onOffRoad(off);
  }

  void _lift() {
    _setOffRoad(false);
    setState(() {
      _finger = null;
      _last = null;
      _heading = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final projection = widget.projection;
    final finger = _finger;
    final heading = _heading;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.onTouch(),
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: {
          _NearEndRecognizer:
              GestureRecognizerFactoryWithHandlers<_NearEndRecognizer>(
                () => _NearEndRecognizer(_startsNearEnd),
                (r) => r
                  ..dragStartBehavior = DragStartBehavior.down
                  ..onStart = (d) {
                    _last = projection?.toLatLng(d.localPosition);
                    _move(d.localPosition);
                  }
                  ..onUpdate = (d) {
                    _move(d.localPosition);
                  }
                  ..onEnd = (_) {
                    _lift();
                  }
                  ..onCancel = _lift,
              ),
        },
        child: CustomPaint(
          size: Size.infinite,
          painter: finger == null || projection == null
              ? null
              : _FingerPainter(
                  colors: PindoroTheme.of(context).colors,
                  finger: finger,
                  end: projection.toScreen(_draft.graph.at(_draft.end)),
                  junction: heading == null
                      ? null
                      : projection.toScreen(
                          _draft.graph.at(heading.other(_draft.end)),
                        ),
                ),
        ),
      ),
    );
  }
}

/// A pan that only joins the gesture arena when it starts near the route's
/// end; otherwise the map's own gestures get the pointer.
class _NearEndRecognizer extends PanGestureRecognizer {
  _NearEndRecognizer(this._accepts);

  final bool Function(Offset global) _accepts;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      _accepts(event.position) && super.isPointerAllowed(event);
}

class _FingerPainter extends CustomPainter {
  _FingerPainter({
    required this.colors,
    required this.finger,
    required this.end,
    required this.junction,
  });

  final PindoroColors colors;
  final Offset finger;
  final Offset end;

  /// The next junction on the edge being followed; null off the road.
  final Offset? junction;

  @override
  void paint(Canvas canvas, Size size) {
    final route = Paint()
      ..color = colors.mapPlayerRoute
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final junction = this.junction;
    if (junction == null) {
      // The rubber band: the route stops, a thin line follows the finger.
      canvas.drawLine(end, finger, route..strokeWidth = PindoroStroke.base);
    } else {
      canvas.drawCircle(
        junction,
        _ringRadius,
        route..strokeWidth = PindoroStroke.thick,
      );
    }
    canvas
      ..drawCircle(
        finger,
        _fingerRadius + PindoroStroke.base,
        Paint()..color = colors.mapPlayerHalo,
      )
      ..drawCircle(
        finger,
        _fingerRadius,
        Paint()..color = colors.mapPlayerRoute,
      );
  }

  // The map below keeps every touch the drag doesn't take.
  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_FingerPainter old) =>
      old.finger != finger || old.end != end || old.junction != junction;
}
