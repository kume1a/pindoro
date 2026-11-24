import 'dart:ui' show Color;

import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:pindoro/features/map/data/geojson.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/data/maplibre_convert.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// A route on the map (a recital, a drive): A (none on a drive's plan map,
/// which marks its ends itself), B (null until the route reached it), the
/// route drawn so far (cobalt dashes), a drive's [track] (solid cobalt), the
/// best route (yellow, with chevrons), a [turn] arrow over it (the preview's) and a [chip] over
/// a spot on it. [reached] pops B once.
typedef RouteOverlay = ({
  LatLng? a,
  LatLng? b,
  MultiPolyline drawn,
  MultiPolyline track,
  MultiPolyline best,
  Polyline turn,
  ({LatLng at, String label})? chip,
  bool reached,
});

/// GeoJSON source ids of a route.
abstract final class RouteSources {
  static const String best = 'route-best';
  static const String drawn = 'route-drawn';
  static const String track = 'route-track';
  static const String turn = 'route-turn';
  static const String a = 'route-a';
  static const String b = 'route-b';
  static const String chip = 'route-chip';
}

const String _chevron = 'route-chevron';
const String _aImage = 'route-a-pin';
const String _bImage = 'route-b-pin';

/// Chevrons on the best route, every 80 dp (`color.map.route.arrow`).
const double _chevronSpacing = 80;

/// The best route: a 6 dp line in a 2 dp casing.
const double routeWidth = PindoroStroke.answer - PindoroStroke.base;
const double routeCasing = PindoroStroke.answer + PindoroStroke.base;

/// The drawn route: 5 dp dashes 8/7 over a 9 dp halo (`.pd-map-player-route`).
const double drawnWidth = 5;
const double drawnHalo = 9;
const double drawnDash = 8;
const double drawnGap = 7;

/// A drive's track on the plan and review map: 4 dp solid (MapOverlays).
const double trackWidth = 4;

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
/// its turn arrow, the drawn route, A and B, and the chip.
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
  for (final id in [
    RouteSources.best,
    RouteSources.drawn,
    RouteSources.track,
  ]) {
    await c.addGeoJsonSource(id, linesGeoJson(const []));
  }
  for (final id in [RouteSources.a, RouteSources.b, RouteSources.chip]) {
    await c.addGeoJsonSource(id, pointsGeoJson(const []));
  }
  await addCasedLine(
    c,
    RouteSources.best,
    casing: (colors.mapRouteCasing, routeCasing),
    line: (colors.mapRouteLine, routeWidth),
    below: null,
  );
  await c.addSymbolLayer(
    RouteSources.best,
    '${RouteSources.best}-chevrons',
    const ml.SymbolLayerProperties(
      iconImage: _chevron,
      // The chevron glyph was drawn for the 8 dp line.
      iconSize: routeWidth / PindoroStroke.answer,
      symbolPlacement: 'line',
      symbolSpacing: _chevronSpacing,
      iconRotationAlignment: 'map',
      iconAllowOverlap: true,
      iconIgnorePlacement: true,
    ),
    enableInteraction: false,
  );
  await addTurnArrow(
    c,
    colors,
    source: RouteSources.turn,
    width: routeWidth,
    pixelRatio: pixelRatio,
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
  await c.addLineLayer(
    RouteSources.track,
    '${RouteSources.track}-line',
    ml.LineLayerProperties(
      lineColor: hexColor(colors.mapPlayerRoute),
      lineWidth: trackWidth,
      lineCap: 'round',
      lineJoin: 'round',
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
    RouteSources.track: now?.track ?? const [],
  };
  final old = <String, MultiPolyline>{
    RouteSources.best: before?.best ?? const [],
    RouteSources.drawn: before?.drawn ?? const [],
    RouteSources.track: before?.track ?? const [],
  };
  for (final MapEntry(:key, :value) in lines.entries) {
    if (before == null || !identical(value, old[key])) {
      await c.setGeoJsonSource(key, linesGeoJson(value));
    }
  }
  final turn = now?.turn ?? const [];
  if (before == null || !identical(turn, before.turn)) {
    await sendTurnArrow(c, RouteSources.turn, turn);
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

/// A turn arrow (Guided's, the preview's): its line on [source], [width] wide in the drive
/// plate's colours, and its head on `$source-head`, drawn at [pixelRatio] and turned the way the
/// arrow points. Empty until [sendTurnArrow].
Future<void> addTurnArrow(
  ml.MapLibreMapController c,
  PindoroColors colors, {
  required String source,
  required double width,
  required double pixelRatio,
}) async {
  final head = '$source-head';
  await c.addGeoJsonSource(source, linesGeoJson(const []));
  await addCasedLine(
    c,
    source,
    casing: (colors.drivePlate, width + 2 * PindoroStroke.thick),
    line: (colors.drivePlateText, width),
  );
  await c.addImage(
    head,
    await turnArrowHeadPng(
      fill: colors.drivePlateText,
      casing: colors.drivePlate,
      pixelRatio: pixelRatio,
    ),
  );
  await c.addGeoJsonSource(head, pointsGeoJson(const []));
  await c.addSymbolLayer(
    head,
    '$head-mark',
    ml.SymbolLayerProperties(
      iconImage: head,
      iconAnchor: 'bottom',
      iconAllowOverlap: true,
      iconIgnorePlacement: true,
      iconPitchAlignment: 'map',
      iconRotate: const ['get', 'heading'],
      iconRotationAlignment: 'map',
    ),
    enableInteraction: false,
  );
}

/// Draws [turn] as the arrow added on [source] (none under two points).
Future<void> sendTurnArrow(
  ml.MapLibreMapController c,
  String source,
  Polyline turn,
) async {
  final drawn = turn.length > 1;
  await c.setGeoJsonSource(source, linesGeoJson([if (drawn) turn]));
  await c.setGeoJsonSource(
    '$source-head',
    drawn
        ? pointsGeoJson(
            [turn.last],
            properties: {
              'heading': bearingDegrees(turn[turn.length - 2], turn.last),
            },
          )
        : pointsGeoJson(const []),
  );
}

/// A line on [source] over a casing: its `-casing` layer ([casing]'s colour and width) under its
/// `-line` layer, both rounded, under the layer [below] (the basemap's names by default).
Future<void> addCasedLine(
  ml.MapLibreMapController c,
  String source, {
  required (Color, double) casing,
  required (Color, double) line,
  String? below = NameLayers.lowest,
}) async {
  for (final (id, (color, width)) in [('casing', casing), ('line', line)]) {
    await c.addLineLayer(
      source,
      '$source-$id',
      ml.LineLayerProperties(
        lineColor: hexColor(color),
        lineWidth: width,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      belowLayerId: below,
      enableInteraction: false,
    );
  }
}
