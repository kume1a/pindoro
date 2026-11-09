import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pindoro_core/pindoro_core.dart';

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
      p = await Geolocator.getLastKnownPosition();
    }
    return p == null
        ? const LocationUnavailable()
        : Located(LatLng(p.latitude, p.longitude));
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
