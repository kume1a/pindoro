import 'package:pindoro_core/pindoro_core.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where Street View opens and which way it looks (degrees from north).
typedef StreetViewSpot = ({LatLng at, double heading});

/// Links that open the Google Maps app (SPEC §10): Maps URLs only, no API
/// key, nothing from Google inside Pindoro.
abstract final class GoogleMaps {
  static Uri streetView(StreetViewSpot spot) =>
      Uri.https('www.google.com', '/maps/@', {
        'api': '1',
        'map_action': 'pano',
        'viewpoint': '${spot.at.lat},${spot.at.lon}',
        'heading': '${spot.heading.round()}',
      });

  static Future<void> open(Uri link) async {
    await launchUrl(link, mode: LaunchMode.externalApplication);
  }
}

/// Street View on [street] at its point nearest [near], looking along it.
StreetViewSpot streetSpot(NamedStreet street, LatLng near) {
  final at = street.nearest(near).nearestPoint;
  return (at: at, heading: headingAlong(street.geometry, at));
}

/// Street View on [street] at its point nearest [place], looking at it.
StreetViewSpot placeSpot(NamedStreet street, LatLng place) {
  final at = street.nearest(place).nearestPoint;
  return (at: at, heading: bearingDegrees(at, place));
}
