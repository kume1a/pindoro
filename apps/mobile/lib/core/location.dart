import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

sealed class LocationResult {
  const LocationResult();
}

final class Located extends LocationResult {
  const Located(this.position);

  final LatLng position;
}

/// Permission refused: the UI points to the app's settings.
class LocationDenied extends LocationResult {
  const LocationDenied();
}

/// Location services are off; only the system's location settings turn them
/// on (the app's own settings page can't).
final class LocationServicesOff extends LocationDenied {
  const LocationServicesOff();
}

/// No fix in time and none remembered.
final class LocationUnavailable extends LocationResult {
  const LocationUnavailable();
}

/// The device's position, asking for permission when needed.
class LocationService {
  const LocationService();

  Future<LocationResult> locate() async {
    LocationPermission permission;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationServicesOff();
      }
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
    } on Object {
      // e.g. a second request while the system dialog is still up.
      return const LocationUnavailable();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return const LocationDenied();
    }
    Position? p;
    try {
      p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } on Object {
      p = await _lastKnown();
    }
    return p == null
        ? const LocationUnavailable()
        : Located(LatLng(p.latitude, p.longitude));
  }

  static Future<Position?> _lastKnown() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } on Object {
      return null;
    }
  }

  /// The last known position when location is on and already allowed; never
  /// asks and never waits for a fix.
  Future<LatLng?> ifAllowed() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return null;
      }
      final p = await Geolocator.getLastKnownPosition();
      return p == null ? null : LatLng(p.latitude, p.longitude);
    } on Object {
      return null;
    }
  }

  /// A fix about every second while a GPS-free drive records, also with the
  /// screen locked: Android keeps a foreground service up with [title] and
  /// [text] as its notification, iOS goes on in the background (permission
  /// asked first by [locate]). Fixes come while stopped too: hesitations
  /// need them.
  Stream<DriveFix> track({required String title, required String text}) =>
      Geolocator.getPositionStream(
        locationSettings: switch (defaultTargetPlatform) {
          TargetPlatform.android => AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
            intervalDuration: const Duration(seconds: 1),
            foregroundNotificationConfig: ForegroundNotificationConfig(
              notificationTitle: title,
              notificationText: text,
              enableWakeLock: true,
            ),
          ),
          TargetPlatform.iOS => AppleSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            activityType: ActivityType.automotiveNavigation,
            distanceFilter: 0,
            pauseLocationUpdatesAutomatically: false,
            allowBackgroundLocationUpdates: true,
            showBackgroundLocationIndicator: true,
          ),
          _ => const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
          ),
        },
      ).map(
        (p) => (
          at: LatLng(p.latitude, p.longitude),
          t: p.timestamp,
          headingDeg: p.heading >= 0 ? p.heading : null,
          speedMps: p.speed >= 0 ? p.speed : null,
        ),
      );

  /// The settings page that fixes [denial].
  Future<void> openSettings(LocationDenied denial) async {
    await (denial is LocationServicesOff
        ? Geolocator.openLocationSettings()
        : Geolocator.openAppSettings());
  }
}

/// Overridden in tests.
final locationServiceProvider = Provider<LocationService>(
  (ref) => const LocationService(),
);
