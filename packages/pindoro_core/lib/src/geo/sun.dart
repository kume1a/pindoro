import 'dart:math';

import 'geo.dart';

/// The sun's height above the horizon at [at] and [time], in degrees (the
/// low-precision almanac formulas, good to about 0.01°).
double sunElevationDeg(LatLng at, DateTime time) {
  const rad = pi / 180;
  // Days since J2000.0 (2000-01-01 12:00 UTC).
  final d = time.toUtc().millisecondsSinceEpoch / 86400000 - 10957.5;
  final g = (357.529 + 0.98560028 * d) * rad;
  final q = 280.459 + 0.98564736 * d;
  final l = (q + 1.915 * sin(g) + 0.020 * sin(2 * g)) * rad;
  final e = (23.439 - 0.00000036 * d) * rad;
  final ra = atan2(cos(e) * sin(l), cos(l));
  final dec = asin(sin(e) * sin(l));
  final gmstDeg = (18.697374558 + 24.06570982441908 * d) * 15;
  final hourAngle = (gmstDeg + at.lon) * rad - ra;
  final lat = at.lat * rad;
  return asin(sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(hourAngle)) / rad;
}

/// Whether the sun is down at [at] and [time]: below the horizon with
/// refraction and its own radius (−0.833°), as sunset and sunrise are timed.
bool isNight(LatLng at, DateTime time) => sunElevationDeg(at, time) < -0.833;
