import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/data/maplibre_convert.dart';
import 'package:pindoro/features/map/ui/route_projection.dart';

/// What every MapLibre map here shares: its controller, the size it was laid
/// out at, the bundled style for the theme's brightness (loaded again when
/// it changes) and screen ↔ map through [mapProjection].
mixin MapHost<T extends StatefulWidget> on State<T> {
  @protected
  ml.MapLibreMapController? mapController;

  /// Set by the host's LayoutBuilder.
  @protected
  Size? mapSize;

  @protected
  Future<String>? mapStyle;

  Brightness? _brightness;

  /// Street names in English in the style (PindoroMap's setting).
  @protected
  bool get englishNames => false;

  /// A new style is loading (a theme change): its layers must be added
  /// again once it has.
  @protected
  void styleChanged() {}

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (brightness == _brightness) return;
    _brightness = brightness;
    styleChanged();
    mapStyle = loadMapStyle(brightness, english: englishNames);
  }

  /// The camera as screen ↔ map; null before the map's first camera.
  @protected
  MapProjection? get mapProjection {
    final camera = mapController?.cameraPosition;
    final size = mapSize;
    if (camera == null || size == null) return null;
    return MapProjection(
      target: camera.target.toCore,
      zoom: camera.zoom,
      size: size,
      bearing: camera.bearing,
    );
  }
}
