import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pindoro/features/map/ui/route_layers.dart';
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
/// drawing it paints the finger, the street being followed up to the finger
/// with a ring on its next junction and, off the road, a rubber band from the
/// route's end. [onTouch] hears every touch (the first-trip ghost hides);
/// [onDrawing] hears a draw start and end; [onOffRoad] says when the finger
/// leaves or rejoins the streets.
class RouteDrawLayer extends StatefulWidget {
  const RouteDrawLayer({
    super.key,
    required this.projection,
    required this.draft,
    required this.onDraft,
    required this.onTouch,
    required this.onDrawing,
    required this.onOffRoad,
  });

  final MapProjection? projection;
  final RouteDraft draft;
  final ValueChanged<RouteDraft> onDraft;
  final VoidCallback onTouch;
  final ValueChanged<bool> onDrawing;
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
    widget.onDrawing(false);
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
    final street = projection == null
        ? null
        : _heading?.lineFrom(_draft.end).map(projection.toScreen).toList();
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
                    widget.onDrawing(true);
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
                  junction: street?.last,
                  along: street == null ? null : lineUpTo(street, finger),
                ),
        ),
      ),
    );
  }
}

/// [line] from its start up to the point on it nearest [point].
List<Offset> lineUpTo(List<Offset> line, Offset point) {
  var best = (distance: double.infinity, index: 0, at: line.first);
  for (var i = 0; i + 1 < line.length; i++) {
    final a = line[i], ab = line[i + 1] - a;
    final toPoint = point - a;
    final length2 = ab.distanceSquared;
    final t = length2 == 0
        ? 0.0
        : ((toPoint.dx * ab.dx + toPoint.dy * ab.dy) / length2).clamp(0.0, 1.0);
    final at = a + ab * t;
    final distance = (point - at).distance;
    if (distance < best.distance) {
      best = (distance: distance, index: i, at: at);
    }
  }
  return [...line.take(best.index + 1), best.at];
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
    required this.along,
  });

  final PindoroColors colors;
  final Offset finger;
  final Offset end;

  /// The next junction on the edge being followed; null off the road.
  final Offset? junction;

  /// That edge from the route's end up to the finger, in the drawn route's
  /// look, so the route keeps up with the finger between junctions.
  final List<Offset>? along;

  @override
  void paint(Canvas canvas, Size size) {
    final route = Paint()
      ..color = colors.mapPlayerRoute
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    if (along case final along?) _paintAlong(canvas, along);
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

  void _paintAlong(Canvas canvas, List<Offset> along) {
    final path = Path()..addPolygon(along, false);
    canvas.drawPath(
      path,
      Paint()
        ..color = colors.mapPlayerHalo
        ..style = PaintingStyle.stroke
        ..strokeWidth = drawnHalo
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final dash = Paint()
      ..color = colors.mapPlayerRoute
      ..style = PaintingStyle.stroke
      ..strokeWidth = drawnWidth
      ..strokeJoin = StrokeJoin.round;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += drawnDash + drawnGap) {
        canvas.drawPath(metric.extractPath(d, d + drawnDash), dash);
      }
    }
  }

  // The map below keeps every touch the drag doesn't take.
  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_FingerPainter old) =>
      old.finger != finger || old.end != end || old.junction != junction;
}
