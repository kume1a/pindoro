import 'dart:math' as math;

import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// A turn card on the real map, driving up the screen: the [approach] into
/// the junction and each exit's road out of it (ends at the junction), where
/// each exit's button and the car sit, and what the camera frames.
typedef TurnScene = ({
  double bearing,
  List<LatLng> approach,
  Map<Turn, List<LatLng>> exits,
  Map<Turn, LatLng> buttons,
  LatLng car,
  List<LatLng> frame,
});

/// Metres of road drawn from the junction; buttons and the car sit
/// [_markM] out along each road's first stretch (a short edge still puts
/// its button clear of the junction).
const double _roadM = 90;
const double _markM = 50;

/// How far along a road its heading is read.
const double _headingM = 20;

TurnScene turnScene(RoadGraph graph, TurnQuestion q) {
  final at = graph.at(q.junction);
  final local = LocalProjection(at);
  List<LatLng> road(RoadEdge e, double metres) =>
      clipToCircle([e.lineFrom(q.junction)], at, metres).first;
  LatLng out(RoadEdge e) {
    final (x, y) = local.project(road(e, _headingM).last);
    final length = math.max(math.sqrt(x * x + y * y), 1);
    return local.unproject((x / length * _markM, y / length * _markM));
  }

  final car = out(q.approach);
  final buttons = {for (final e in q.exits.entries) e.key: out(e.value)};
  return (
    // The way the driver faces: from the approach towards the junction.
    bearing: bearingDegrees(road(q.approach, _headingM).last, at),
    approach: road(q.approach, _roadM).reversed.toList(),
    exits: {for (final e in q.exits.entries) e.key: road(e.value, _roadM)},
    buttons: buttons,
    car: car,
    frame: [at, car, ...buttons.values],
  );
}
