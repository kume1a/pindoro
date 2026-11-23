import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Most points of a route weighed for its bubble: long routes are sampled.
const int _samples = 200;

/// A bubble already placed counts this many times nearer than it is: it covers much more of
/// the map than a route's line does.
const double _bubbleWeight = 3;

/// Where a route's bubble goes on the map (SPEC §16.23 item 134): the point of [route] farthest
/// from the [others] and from the bubbles [placed] already, so each sits where its route runs
/// apart; its middle when alone; null for no route.
LatLng? calloutAt(
  MultiPolyline route,
  MultiPolyline others, {
  List<LatLng> placed = const [],
}) {
  final points = [for (final line in route) ...line];
  if (points.isEmpty) return null;
  if (others.isEmpty && placed.isEmpty) {
    return linePart(points, 0.5, 0.5).first;
  }
  double clearM(LatLng p) => [
    if (others.isNotEmpty) pointToPolylineDistance(p, others).distanceMeters,
    for (final b in placed) distanceBetween(p, b) / _bubbleWeight,
  ].reduce(min);
  final step = max(1, points.length ~/ _samples);
  var best = points.first;
  var bestM = -1.0;
  for (var i = 0; i < points.length; i += step) {
    final m = clearM(points[i]);
    if (m > bestM) (best, bestM) = (points[i], m);
  }
  return best;
}
