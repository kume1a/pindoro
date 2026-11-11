import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:pindoro/features/map/data/geojson.dart';
import 'package:pindoro/features/map/data/maplibre_convert.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// A road trip on the map: A and B, the route drawn so far (cobalt dashes),
/// the best route as painted so far (yellow, with chevrons), the first-trip
/// ghost, the replay [car] and the distance [chip] at the route's end (its
/// [chipAnchor] keeps it on screen). [reached] pops B once.
typedef RouteOverlay = ({
  LatLng a,
  LatLng b,
  MultiPolyline drawn,
  MultiPolyline best,
  MultiPolyline ghost,
  LatLng? car,
  ({LatLng at, String label, String anchor})? chip,
  bool reached,
});

/// The distance chip's MapLibre icon anchor for a route end at [x] on a map
/// [width] wide: near an edge the chip grows inwards instead of off screen.
String chipAnchor(double x, double width) => x < width / 4
    ? 'bottom-left'
    : x > width * 3 / 4
    ? 'bottom-right'
    : 'bottom';

/// GeoJSON source ids of a road trip.
abstract final class RouteSources {
  static const String best = 'route-best';
  static const String drawn = 'route-drawn';
  static const String ghost = 'route-ghost';
  static const String a = 'route-a';
  static const String b = 'route-b';
  static const String car = 'route-car';
  static const String chip = 'route-chip';
}

const String _chevron = 'route-chevron';
const String _aImage = 'route-a-pin';
const String _bImage = 'route-b-pin';
const String _carImage = 'route-car-mark';

/// Chevrons on the best route, every 80 dp (`color.map.route.arrow`).
const double _chevronSpacing = 80;

/// The drawn route: 5 dp dashes 8/7 over a 9 dp halo (`.pd-map-player-route`).
const double _drawnWidth = 5;
const double _drawnHalo = 9;

/// The ghost: round dots 9 dp apart (`.pd-map-ghost`).
const double _ghostWidth = 6;

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

/// Adds the road-trip sources, images and layers, bottom to top: the best
/// route, the drawn route, the ghost, A and B, the car and the chip.
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
  await c.addImage(_carImage, await CarMark(colors).toPng(pixelRatio));
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
  for (final id in [
    RouteSources.best,
    RouteSources.drawn,
    RouteSources.ghost,
  ]) {
    await c.addGeoJsonSource(id, linesGeoJson(const []));
  }
  for (final id in [
    RouteSources.a,
    RouteSources.b,
    RouteSources.car,
    RouteSources.chip,
  ]) {
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
      lineWidth: _drawnHalo,
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
      lineWidth: _drawnWidth,
      lineJoin: 'round',
      // Dash units are line widths.
      lineDasharray: [8 / _drawnWidth, 7 / _drawnWidth],
    ),
    enableInteraction: false,
  );
  await c.addLineLayer(
    RouteSources.ghost,
    '${RouteSources.ghost}-dots',
    ml.LineLayerProperties(
      lineColor: hexColor(colors.coachBg),
      lineWidth: _ghostWidth,
      lineCap: 'round',
      lineDasharray: [0, 9 / _ghostWidth],
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
    RouteSources.car,
    '${RouteSources.car}-mark',
    const ml.SymbolLayerProperties(
      iconImage: _carImage,
      iconAllowOverlap: true,
      iconIgnorePlacement: true,
    ),
    enableInteraction: false,
  );
  await c.addSymbolLayer(
    RouteSources.chip,
    '${RouteSources.chip}-label',
    const ml.SymbolLayerProperties(
      iconImage: ['get', 'icon'],
      iconAnchor: ['get', 'anchor'],
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
    RouteSources.ghost: now?.ghost ?? const [],
  };
  final old = <String, MultiPolyline>{
    RouteSources.best: before?.best ?? const [],
    RouteSources.drawn: before?.drawn ?? const [],
    RouteSources.ghost: before?.ghost ?? const [],
  };
  for (final MapEntry(:key, :value) in lines.entries) {
    if (before == null || !identical(value, old[key])) {
      await c.setGeoJsonSource(key, linesGeoJson(value));
    }
  }
  final points = <String, LatLng?>{
    RouteSources.a: now?.a,
    RouteSources.b: now?.b,
    RouteSources.car: now?.car,
  };
  final oldPoints = <String, LatLng?>{
    RouteSources.a: before?.a,
    RouteSources.b: before?.b,
    RouteSources.car: before?.car,
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
              properties: {
                'icon': await chipImage(chip.label),
                'anchor': chip.anchor,
              },
            ),
    );
  }
}
