import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:pindoro/features/map/data/geojson.dart';
import 'package:pindoro/features/map/data/maplibre_convert.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// A route on the map (a recital, a drive): A, B (null until the route
/// reached it), the route drawn so far (cobalt dashes), the best route
/// (yellow, with chevrons) and a [chip] over a spot on it. [reached] pops B
/// once.
typedef RouteOverlay = ({
  LatLng a,
  LatLng? b,
  MultiPolyline drawn,
  MultiPolyline best,
  ({LatLng at, String label})? chip,
  bool reached,
});

/// GeoJSON source ids of a route.
abstract final class RouteSources {
  static const String best = 'route-best';
  static const String drawn = 'route-drawn';
  static const String a = 'route-a';
  static const String b = 'route-b';
  static const String chip = 'route-chip';
}

const String _chevron = 'route-chevron';
const String _aImage = 'route-a-pin';
const String _bImage = 'route-b-pin';

/// Chevrons on the best route, every 80 dp (`color.map.route.arrow`).
const double _chevronSpacing = 80;

/// The drawn route: 5 dp dashes 8/7 over a 9 dp halo (`.pd-map-player-route`).
const double drawnWidth = 5;
const double drawnHalo = 9;
const double drawnDash = 8;
const double drawnGap = 7;

/// An endpoint pin, anchored at its tip and grown by [scale] (B's pop).
ml.SymbolLayerProperties endpointLayer(
  String image,
  double pixelRatio, {
  double scale = 1,
}) => ml.SymbolLayerProperties(
  iconImage: image,
  iconAnchor: 'bottom',
  iconOffset: [0, PinMark.tipInset * pixelRatio],
  iconSize: scale,
  iconAllowOverlap: true,
  iconIgnorePlacement: true,
);

/// Adds the route sources, images and layers, bottom to top: the best route,
/// the drawn route, A and B, and the chip.
/// Overlays never take taps (see PindoroMap).
Future<void> addRouteLayers(
  ml.MapLibreMapController c,
  PindoroColors colors,
  double pixelRatio,
) async {
  await c.addImage(
    _aImage,
    await PinMark.endpoint('A', colors).toPng(pixelRatio),
  );
  await c.addImage(
    _bImage,
    await PinMark.endpoint('B', colors).toPng(pixelRatio),
  );
  await c.addImage(
    _chevron,
    await glyphPng(
      PindoroGlyph.chevronRight,
      ink: colors.mapRouteArrow,
      cut: colors.mapRouteLine,
      size: PindoroSize.iconSm,
      pixelRatio: pixelRatio,
    ),
  );
  for (final id in [RouteSources.best, RouteSources.drawn]) {
    await c.addGeoJsonSource(id, linesGeoJson(const []));
  }
  for (final id in [RouteSources.a, RouteSources.b, RouteSources.chip]) {
    await c.addGeoJsonSource(id, pointsGeoJson(const []));
  }
  for (final (id, color, width) in [
    (
      'casing',
      colors.mapRouteCasing,
      PindoroStroke.answer + 2 * PindoroStroke.base,
    ),
    ('line', colors.mapRouteLine, PindoroStroke.answer),
  ]) {
    await c.addLineLayer(
      RouteSources.best,
      '${RouteSources.best}-$id',
      ml.LineLayerProperties(
        lineColor: hexColor(color),
        lineWidth: width,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );
  }
  await c.addSymbolLayer(
    RouteSources.best,
    '${RouteSources.best}-chevrons',
    const ml.SymbolLayerProperties(
      iconImage: _chevron,
      symbolPlacement: 'line',
      symbolSpacing: _chevronSpacing,
      iconRotationAlignment: 'map',
      iconAllowOverlap: true,
      iconIgnorePlacement: true,
    ),
    enableInteraction: false,
  );
  await c.addLineLayer(
    RouteSources.drawn,
    '${RouteSources.drawn}-halo',
    ml.LineLayerProperties(
      lineColor: hexColor(colors.mapPlayerHalo),
      lineWidth: drawnHalo,
      lineCap: 'round',
      lineJoin: 'round',
    ),
    enableInteraction: false,
  );
  await c.addLineLayer(
    RouteSources.drawn,
    '${RouteSources.drawn}-line',
    ml.LineLayerProperties(
      lineColor: hexColor(colors.mapPlayerRoute),
      lineWidth: drawnWidth,
      lineJoin: 'round',
      // Dash units are line widths.
      lineDasharray: [drawnDash / drawnWidth, drawnGap / drawnWidth],
    ),
    enableInteraction: false,
  );
  for (final (id, image) in [
    (RouteSources.a, _aImage),
    (RouteSources.b, _bImage),
  ]) {
    await c.addSymbolLayer(
      id,
      '$id-pin',
      endpointLayer(image, pixelRatio),
      enableInteraction: false,
    );
  }
  await c.addSymbolLayer(
    RouteSources.chip,
    '${RouteSources.chip}-label',
    const ml.SymbolLayerProperties(
      iconImage: ['get', 'icon'],
      iconAnchor: 'bottom',
      iconAllowOverlap: true,
      iconIgnorePlacement: true,
    ),
    enableInteraction: false,
  );
}

/// Pops B: the endpoint layer at [scale].
Future<void> scaleB(
  ml.MapLibreMapController c,
  double pixelRatio,
  double scale,
) => c.setLayerProperties(
  '${RouteSources.b}-pin',
  endpointLayer(_bImage, pixelRatio, scale: scale),
);

/// Sends what changed between [before] and [now] to the map; [chipImage]
/// adds a chip's image and returns its id.
Future<void> syncRoute(
  ml.MapLibreMapController c,
  RouteOverlay? now,
  RouteOverlay? before,
  Future<String> Function(String label) chipImage,
) async {
  final lines = <String, MultiPolyline>{
    RouteSources.best: now?.best ?? const [],
    RouteSources.drawn: now?.drawn ?? const [],
  };
  final old = <String, MultiPolyline>{
    RouteSources.best: before?.best ?? const [],
    RouteSources.drawn: before?.drawn ?? const [],
  };
  for (final MapEntry(:key, :value) in lines.entries) {
    if (before == null || !identical(value, old[key])) {
      await c.setGeoJsonSource(key, linesGeoJson(value));
    }
  }
  final points = <String, LatLng?>{
    RouteSources.a: now?.a,
    RouteSources.b: now?.b,
  };
  final oldPoints = <String, LatLng?>{
    RouteSources.a: before?.a,
    RouteSources.b: before?.b,
  };
  for (final MapEntry(:key, :value) in points.entries) {
    if (before == null || value != oldPoints[key]) {
      await c.setGeoJsonSource(key, pointsGeoJson([?value]));
    }
  }
  final chip = now?.chip;
  if (before == null || chip != before.chip) {
    await c.setGeoJsonSource(
      RouteSources.chip,
      chip == null
          ? pointsGeoJson(const [])
          : pointsGeoJson(
              [chip.at],
              properties: {'icon': await chipImage(chip.label)},
            ),
    );
  }
}
