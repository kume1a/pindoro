import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

/// How long the car keeps moving ahead of its last fix before it waits for the next one: a
/// fix comes every second, and a car that went on for longer would run past a stop.
const double predictMaxS = 1.5;

/// How far ahead along the road the car's heading looks, so the map turns into a bend
/// smoothly instead of at its corner.
const double headingAheadM = 12;

/// The point [m] metres along [line] (its end past it) and the way the road runs from there
/// to [headingAheadM] further; null for a line with no length.
({LatLng at, double headingDeg})? alongRoad(Polyline line, double m) {
  if (line.length < 2) return null;
  final at = _pointAt(line, m);
  final ahead = _pointAt(line, m + headingAheadM);
  final heading = distanceBetween(at, ahead) > 0.5
      ? bearingDegrees(at, ahead)
      : bearingDegrees(line[line.length - 2], line.last);
  return (at: at, headingDeg: heading);
}

LatLng _pointAt(Polyline line, double m) {
  var left = max(0.0, m);
  for (var i = 1; i < line.length; i++) {
    final a = line[i - 1], b = line[i];
    final d = distanceBetween(a, b);
    if (d >= left && d > 0) {
      final t = left / d;
      return LatLng(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
    }
    left -= d;
  }
  return line.last;
}

/// [from] turned towards [to] by at most [share] of the way, the short way round (degrees).
double turnToward(double from, double to, double share) {
  final d = (to - from + 540) % 360 - 180;
  return (from + d * share.clamp(0, 1) + 360) % 360;
}
