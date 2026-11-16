import 'package:pindoro_core/pindoro_core.dart';
import 'package:url_launcher/url_launcher.dart';

/// Links that open the Google Maps app (SPEC §10): Maps URLs only, no API
/// key, nothing from Google inside Pindoro.
abstract final class GoogleMaps {
  static Uri directions(LatLng to) => Uri.https(
    'www.google.com',
    '/maps/dir/',
    {'api': '1', 'destination': '${to.lat},${to.lon}', 'travelmode': 'driving'},
  );

  /// Street View at [at], looking along [heading] (degrees from north).
  static Uri streetView(LatLng at, double heading) =>
      Uri.https('www.google.com', '/maps/@', {
        'api': '1',
        'map_action': 'pano',
        'viewpoint': '${at.lat},${at.lon}',
        'heading': '${heading.round()}',
      });

  static Future<void> openExternally(Uri link) async {
    await launchUrl(link, mode: LaunchMode.externalApplication);
  }
}
