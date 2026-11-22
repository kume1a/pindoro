import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the top of the phone points, degrees from north, as it turns; null readings (no
/// sensor, not calibrated) are left out. Point to home reads it (SPEC §16.23 item 121); tests
/// override it.
final compassProvider = Provider<Stream<double>>(
  (ref) => (FlutterCompass.events ?? const Stream<CompassEvent>.empty())
      .map((e) => e.heading)
      .where((h) => h != null)
      .map((h) => (h! % 360 + 360) % 360),
);
