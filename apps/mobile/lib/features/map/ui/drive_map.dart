import 'dart:async';
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:pindoro/features/map/data/geojson.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/data/maplibre_convert.dart';
import 'package:pindoro/features/map/ui/map_host.dart';
import 'package:pindoro/features/map/ui/map_work.dart';
import 'package:pindoro/features/map/ui/poi_icons.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Builds the Guided map; widget tests override it so no platform view is made.
final driveMapBuilderProvider = Provider<Widget Function(DriveMap map)>(
  (ref) =>
      (map) => map,
);

/// The Guided drive's live map (board V32-20, SPEC §16.23 items 116, 118, 130):
/// tilted, following the car at [at] (an arrow laid on the road, or the car
/// disc: [arrow]) with the road it drives ([heading]) straight up while
/// [follow] (north up with [northUp]), the [route] ahead yellow on its ink
/// casing, the [turn] arrow at the next decision and the [destination]. The
/// [overview] shows the route and the other ways on ([alternatives], grey)
/// whole, north up and flat. No names and no landmarks. It drags and pinches
/// at any speed, each touch reported to [onMoved]; the screen stops [follow]
/// and brings it back. [lost] (GPS lost) dims it. The screen shows the
/// attribution.
class DriveMap extends ConsumerStatefulWidget {
  const DriveMap({
    super.key,
    required this.at,
    required this.heading,
    required this.route,
    required this.destination,
    this.turn = const [],
    this.lost = false,
    this.follow = true,
    this.northUp = false,
    this.alternatives = const [],
    this.overview = false,
    this.arrow = true,
    this.onMoved,
  });

  final LatLng? at;
  final double? heading;
  final MultiPolyline route;
  final LatLng destination;

  /// The route around the next decision, drawn as an arrow; empty for none.
  final Polyline turn;
  final bool lost;
  final bool follow;
  final bool northUp;
  final MultiPolyline alternatives;
  final bool overview;

  /// Read once, when the map's layers are made: a change needs a new map (key it).
  final bool arrow;
  final VoidCallback? onMoved;

  static const double zoom = 16.5;
  static const double tilt = 32;

  @override
  ConsumerState<DriveMap> createState() => _DriveMapState();
}

abstract final class _Sources {
  static const String route = 'drive-route';
  static const String alternatives = 'drive-alternatives';
  static const String car = 'drive-car';
  static const String end = 'drive-end';
  static const String turn = 'drive-turn';
  static const String turnHead = 'drive-turn-head';
}

const String _carImage = 'drive-car';
const String _turnHeadImage = 'drive-turn-head';

class _DriveMapState extends ConsumerState<DriveMap> with MapHost<DriveMap> {
  bool _ready = false;

  /// The car's heading: the camera's bearing too, unless north is up.
  double _heading = 0;

  @override
  void styleChanged() => _ready = false;

  /// On the car, which the [_carLow] padding sets about two thirds down the
  /// screen, the road ahead above it.
  ml.CameraPosition _camera(LatLng at) => ml.CameraPosition(
    target: at.toMapLibre,
    zoom: DriveMap.zoom,
    bearing: widget.northUp ? 0 : _heading,
    tilt: DriveMap.tilt,
  );

  /// The top 40 % padded out, so the camera's centre (the car) sits half way
  /// down what is left, 70 % down the map: the road ahead fills the screen,
  /// the car clear of the bottom bar. MapLibre applies it with the tilt's
  /// perspective.
  Future<void> _carLow() async =>
      mapController?.setPadding(top: 0.4 * (mapSize?.height ?? 0));

  @override
  void didUpdateWidget(DriveMap old) {
    super.didUpdateWidget(old);
    _heading = widget.heading ?? _heading;
    if (!_ready) return;
    final moved = widget.at != old.at || widget.heading != old.heading;
    final leftOverview = old.overview && !widget.overview;
    if (moved) runMapWork(_moveCar);
    if (!identical(widget.route, old.route)) runMapWork(_sendRoute);
    if (!identical(widget.alternatives, old.alternatives)) {
      runMapWork(_sendAlternatives);
    }
    if (widget.overview && !old.overview) runMapWork(_showOverview);
    if (leftOverview) runMapWork(_carLow);
    if (moved ||
        leftOverview ||
        widget.northUp != old.northUp ||
        (widget.follow && !old.follow)) {
      runMapWork(_moveCamera);
    }
    if (!identical(widget.turn, old.turn)) runMapWork(_sendTurn);
  }

  Map<String, dynamic> _carGeoJson() =>
      pointsGeoJson([?widget.at], properties: {'heading': _heading});

  Future<void> _moveCar() async =>
      mapController?.setGeoJsonSource(_Sources.car, _carGeoJson());

  /// Onto the car, unless the player has moved the map away or looks at the overview.
  Future<void> _moveCamera() async {
    final at = widget.at;
    if (!widget.follow || widget.overview || at == null) return;
    await mapController?.animateCamera(
      ml.CameraUpdate.newCameraPosition(_camera(at)),
      duration: PindoroMotion.durationSlow * 2,
    );
  }

  Future<void> _sendRoute() async => mapController?.setGeoJsonSource(
    _Sources.route,
    linesGeoJson(widget.route),
  );

  Future<void> _sendAlternatives() async => mapController?.setGeoJsonSource(
    _Sources.alternatives,
    linesGeoJson(widget.alternatives),
  );

  /// The route, the other ways and the car in view, north up and flat, clear of the speeds
  /// above and the routes and the bar below.
  Future<void> _showOverview() async {
    final c = mapController;
    final size = mapSize;
    final points = [
      for (final line in [...widget.route, ...widget.alternatives]) ...line,
      ?widget.at,
    ];
    if (c == null || size == null || points.isEmpty) return;
    await c.setPadding();
    await c.moveCamera(ml.CameraUpdate.bearingTo(0));
    await c.moveCamera(ml.CameraUpdate.tiltTo(0));
    await c.animateCamera(
      ml.CameraUpdate.newLatLngBounds(
        Bbox.of(points).toMapLibre,
        left: PindoroSpace.s8,
        right: PindoroSpace.s8,
        top: 0.15 * size.height,
        bottom: 0.5 * size.height,
      ),
      duration: PindoroMotion.durationSlow,
    );
  }

  Map<String, dynamic> _turnLineGeoJson() =>
      linesGeoJson([if (widget.turn.length > 1) widget.turn]);

  /// The arrow's head on its end, turned the way the arrow points.
  Map<String, dynamic> _turnHeadGeoJson() {
    final turn = widget.turn;
    return turn.length < 2
        ? pointsGeoJson(const [])
        : pointsGeoJson(
            [turn.last],
            properties: {
              'heading': bearingDegrees(turn[turn.length - 2], turn.last),
            },
          );
  }

  Future<void> _sendTurn() async {
    final c = mapController;
    if (c == null) return;
    await c.setGeoJsonSource(_Sources.turn, _turnLineGeoJson());
    await c.setGeoJsonSource(_Sources.turnHead, _turnHeadGeoJson());
  }

  Future<void> _addLayers() async {
    final c = mapController;
    if (c == null) return;
    final colors = PindoroTheme.of(context).colors;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    for (final id in [...NameLayers.places, NameLayers.roads, 'pois']) {
      await c.setLayerVisibility(id, false);
    }
    await addBasemapImages(c, colors, pixelRatio);
    await c.addImage(
      _carImage,
      await (widget.arrow ? ArrowMark(colors).toPng : CarMark(colors).toPng)(
        pixelRatio,
      ),
    );
    // The other ways first, so the route lies over them.
    await c.addGeoJsonSource(
      _Sources.alternatives,
      linesGeoJson(widget.alternatives),
    );
    for (final (id, color, width) in [
      ('casing', colors.drivePlate, 2 * PindoroStroke.answer - 2),
      ('line', colors.drivePlateText2, PindoroStroke.answer),
    ]) {
      await c.addLineLayer(
        _Sources.alternatives,
        '${_Sources.alternatives}-$id',
        ml.LineLayerProperties(
          lineColor: hexColor(color),
          lineWidth: width,
          lineCap: 'round',
          lineJoin: 'round',
        ),
        belowLayerId: NameLayers.lowest,
        enableInteraction: false,
      );
    }
    await c.addGeoJsonSource(_Sources.route, linesGeoJson(widget.route));
    for (final (id, color, width) in [
      ('casing', colors.mapAnswerCasing, 2 * PindoroStroke.answer),
      ('line', colors.mapAnswerLine, 2 * PindoroStroke.answer - 8),
    ]) {
      await c.addLineLayer(
        _Sources.route,
        '${_Sources.route}-$id',
        ml.LineLayerProperties(
          lineColor: hexColor(color),
          lineWidth: width,
          lineCap: 'round',
          lineJoin: 'round',
        ),
        belowLayerId: NameLayers.lowest,
        enableInteraction: false,
      );
    }
    // The turn arrow, in the plate's colours over the route.
    await c.addGeoJsonSource(_Sources.turn, _turnLineGeoJson());
    for (final (id, color, width) in [
      ('casing', colors.drivePlate, 2 * PindoroStroke.answer),
      ('line', colors.drivePlateText, PindoroStroke.answer + 2),
    ]) {
      await c.addLineLayer(
        _Sources.turn,
        '${_Sources.turn}-$id',
        ml.LineLayerProperties(
          lineColor: hexColor(color),
          lineWidth: width,
          lineCap: 'round',
          lineJoin: 'round',
        ),
        belowLayerId: NameLayers.lowest,
        enableInteraction: false,
      );
    }
    await c.addImage(
      _turnHeadImage,
      await turnArrowHeadPng(
        fill: colors.drivePlateText,
        casing: colors.drivePlate,
        pixelRatio: pixelRatio,
      ),
    );
    await c.addGeoJsonSource(_Sources.turnHead, _turnHeadGeoJson());
    await c.addSymbolLayer(
      _Sources.turnHead,
      '${_Sources.turnHead}-mark',
      const ml.SymbolLayerProperties(
        iconImage: _turnHeadImage,
        iconAnchor: 'bottom',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        iconPitchAlignment: 'map',
        iconRotate: ['get', 'heading'],
        iconRotationAlignment: 'map',
      ),
      enableInteraction: false,
    );
    await c.addGeoJsonSource(_Sources.end, pointsGeoJson([widget.destination]));
    await c.addCircleLayer(
      _Sources.end,
      '${_Sources.end}-dot',
      ml.CircleLayerProperties(
        circleColor: hexColor(colors.mapAnswerLine),
        circleRadius: 2 * PindoroStroke.answer,
        circleStrokeColor: hexColor(colors.mapAnswerCasing),
        circleStrokeWidth: PindoroStroke.thick,
      ),
      enableInteraction: false,
    );
    await c.addGeoJsonSource(_Sources.car, _carGeoJson());
    await c.addSymbolLayer(
      _Sources.car,
      '${_Sources.car}-mark',
      ml.SymbolLayerProperties(
        iconImage: _carImage,
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        // The arrow lies on the road; the car disc faces the screen.
        iconPitchAlignment: widget.arrow ? 'map' : 'viewport',
        // Turned by its heading on the map: up while the map follows it, and
        // still the right way once the player has moved the map.
        iconRotate: const ['get', 'heading'],
        iconRotationAlignment: 'map',
      ),
      enableInteraction: false,
    );
    await _carLow();
    _ready = true;
    await _moveCamera();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      mapSize = constraints.biggest;
      return FutureBuilder<String>(
        future: mapStyle,
        builder: (context, style) {
          final start = widget.at ?? widget.destination;
          return Stack(
            children: [
              if (style.hasData)
                Listener(
                  onPointerMove: (_) => widget.onMoved?.call(),
                  child: ml.MapLibreMap(
                    styleString: style.data!,
                    initialCameraPosition: _camera(start),
                    onMapCreated: (c) => mapController = c,
                    onStyleLoadedCallback: () => runMapWork(_addLayers),
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                    compassEnabled: false,
                    attributionButtonMargins: const Point(-100, -100),
                  ),
                ),
              if (widget.lost)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: PindoroTheme.of(
                        context,
                      ).colors.mapMask.withValues(alpha: PindoroOpacity.veil),
                    ),
                  ),
                ),
            ],
          );
        },
      );
    },
  );
}
