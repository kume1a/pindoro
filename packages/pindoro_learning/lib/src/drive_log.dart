import 'package:pindoro_core/pindoro_core.dart';

import 'constants.dart';
import 'drive.dart';

/// How much a drive helps (SPEC §16.23 item 112); the GPS-free drive is [off].
enum DriveLevel { guided, coached, quiet, off }

/// How a drive ended: within [LearningConfig.driveArriveM] of its destination, short of it, or
/// given up for directions (SPEC §16.23 item 116).
enum DriveOutcome { arrived, stopped, abandoned }

/// What a drive event records (SPEC §16.23 items 121, 124): the preview watched, a turn recited
/// before the drive or recalled in the debrief, the debrief gone through, Point to home.
enum DriveEventKind { preview, recite, recall, debrief, point }

/// A drive's fixes as text for the drive log (SPEC §16.23 item 124): per fix the position (1e-6°)
/// and time (ms) as deltas, then heading (0.1°), speed (cm/s) and accuracy (dm), each one more
/// than its value so that 0 means missing.
String encodeTrack(List<DriveFix> fixes) {
  int optional(double? v, double scale) =>
      v == null ? 0 : (v * scale).round() + 1;
  final values = <int>[];
  var lat = 0, lon = 0, ms = 0;
  for (final f in fixes) {
    final fLat = (f.at.lat * 1e6).round();
    final fLon = (f.at.lon * 1e6).round();
    final fMs = f.t.millisecondsSinceEpoch;
    values.addAll([
      fLat - lat,
      fLon - lon,
      fMs - ms,
      optional(f.headingDeg, 10),
      optional(f.speedMps, 100),
      optional(f.accuracyM, 10),
    ]);
    (lat, lon, ms) = (fLat, fLon, fMs);
  }
  return encodeInts(values);
}

/// The fixes [encodeTrack] wrote, their times in UTC.
List<DriveFix> decodeTrack(String encoded) {
  double? optional(int v, double scale) => v == 0 ? null : (v - 1) / scale;
  final values = decodeInts(encoded);
  if (values.length % 6 != 0) {
    throw FormatException('truncated track', encoded, encoded.length);
  }
  final fixes = <DriveFix>[];
  var lat = 0, lon = 0, ms = 0;
  for (var i = 0; i < values.length; i += 6) {
    lat += values[i];
    lon += values[i + 1];
    ms += values[i + 2];
    fixes.add((
      at: LatLng(lat / 1e6, lon / 1e6),
      t: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
      headingDeg: optional(values[i + 3], 10),
      speedMps: optional(values[i + 4], 100),
      accuracyM: optional(values[i + 5], 10),
    ));
  }
  return fixes;
}

/// How often a drive lost GPS, and for how long at most.
typedef GpsGaps = ({int count, Duration longest});

/// The stretches of a drive from [start] to [end] with no fix for over [LearningConfig.gpsGapS]
/// (before the first fix and after the last count too), and the longest of them. A fix older
/// than one already seen (the cached last position some phones send first) leaves no gap.
GpsGaps gpsGaps(List<DriveFix> fixes, DateTime start, DateTime end) {
  var count = 0;
  var longest = Duration.zero;
  var seen = start;
  for (final t in [for (final f in fixes) f.t, end]) {
    final gap = t.difference(seen);
    if (gap.inMilliseconds > LearningConfig.gpsGapS * 1000) {
      count++;
      if (gap > longest) longest = gap;
    }
    if (t.isAfter(seen)) seen = t;
  }
  return (count: count, longest: longest);
}
