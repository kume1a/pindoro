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

/// Permission refused, or location services off: the UI points to Settings.
final class LocationDenied extends LocationResult {
  const LocationDenied();
}

/// No fix in time and none remembered.
final class LocationUnavailable extends LocationResult {
  const LocationUnavailable();
}

/// The device's position, asking for permission when needed.
class LocationService {
  const LocationService();

  Future<LocationResult> locate() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationDenied();
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
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

  Future<void> openSettings() => Geolocator.openAppSettings();
}

/// Overridden in tests.
final locationServiceProvider = Provider<LocationService>(
  (ref) => const LocationService(),
);
