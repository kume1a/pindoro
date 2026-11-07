import 'package:flutter/services.dart';

import 'package:pindoro/core/config.dart';

/// Bundled style with the tile server injected (Martin source `georgia`).
Future<String> loadMapStyle(Brightness brightness) async {
  final json = await rootBundle.loadString(
    'assets/map_styles/pindoro_${brightness.name}.json',
  );
  return json.replaceAll('{TILES_BASE_URL}', AppConfig.tilesBaseUrl);
}
