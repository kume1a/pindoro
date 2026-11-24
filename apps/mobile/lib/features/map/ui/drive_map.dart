import 'dart:async';
import 'dart:math' show Point;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/map/data/car_motion.dart';
import 'package:pindoro/features/map/data/geojson.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/data/maplibre_convert.dart';
import 'package:pindoro/features/map/ui/map_host.dart';
import 'package:pindoro/features/map/ui/map_work.dart';
import 'package:pindoro/features/map/ui/poi_icons.dart';
import 'package:pindoro/features/map/ui/route_layers.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Builds the Guided map; widget tests override it so no platform view is made.
final driveMapBuilderProvider = Provider<Widget Function(DriveMap map)>(
  (ref) =>
      (map) => map,
);

/// The Guided drive's live map (board V32-20, SPEC §16.23 items 116, 118, 130, 132, 133):
/// steeply tilted, the buildings raised, following the car at [at] (an arrow, or the car
/// disc: [arrow]) with the road it drives ([heading]) straight up while [follow] (north up
/// with [northUp]), the [route] ahead yellow on its ink casing, the [turn] arrow at the next
/// decision and the [destination]'s pin; every name and place, house numbers and the traffic
/// lights. The [overview] shows the route and the other ways on ([alternatives], grey)
/// whole, north up and flat. It drags and pinches at any speed, each touch reported to
/// [onMoved]; the screen stops [follow] and brings it back. [lost] (GPS lost) dims it. The
/// screen shows the attribution.
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
    this.via = const [],
    this.places,
    this.speedKmh = 0,
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

  /// The stops on the way not reached yet, in order: a numbered pin each (item 134).
  final List<LatLng> via;

  /// The tile ids of the places kept while the map follows the car (those near the route,
  /// item 135); every place shows in the overview, when the map is moved, or when null.
  final Set<int>? places;

  /// The car's speed: on the car, the map flows on along [route] at it between fixes
  /// (item 135).
  final double speedKmh;
  final VoidCallback? onMoved;

  static const double zoom = 17;
  static const double tilt = 55;

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
  static const String lights = 'drive-lights';
  static const String via = 'drive-via';
}

const String _carImage = 'drive-car';
const String _carLayer = 'drive-car-mark';
const String _turnHeadImage = 'drive-turn-head';
const String _endImage = 'drive-end';
const String _lightsImage = 'drive-lights';

/// A stop's pin image by its number: `drive-via-1`….
String _viaImage(int n) => 'drive-via-$n';

/// The basemap's source and its building footprints, raised on Guided's map.
const String _basemap = 'protomaps';
const String _buildings = 'buildings';

/// The car and the turn arrow's head, drawn this much bigger than their marks: read at a
/// glance from the holder.
const double _markScale = 1.5;

/// The route (and the turn arrow) on Guided's map: 10 dp, in a 2 dp casing.
const double _routeWidth = PindoroStroke.answer + PindoroStroke.base;

/// Buildings rise from this zoom, house numbers show from [_numbersZoom].
const double _raisedZoom = 15;
const double _numbersZoom = 16.5;

/// A building without a height is raised this many metres; every height is scaled by
/// [_heightScale] so tall blocks don't hide the road ahead.
const double _defaultHeightM = 6;
const double _heightScale = 0.5;

/// How far ahead each fix sends the camera, at an even speed: a little past the next fix (a
/// second away), so the camera is still moving when it comes and never stops to wait.
const Duration _fixEvery = Duration(milliseconds: 1200);

class _DriveMapState extends ConsumerState<DriveMap> with MapHost<DriveMap> {
  bool _ready = false;

  /// On the car (item 135): the map eases, at an even speed, to where the car will be at the
  /// next fix, and the car is drawn over it where the camera centres it, still on the screen,
  /// instead of jumping a step with each fix as a map symbol.
  bool _onCar = false;

  /// The car drawn over the map: its image and its turn against the map's bearing, in degrees
  /// (kept unwrapped, so it turns the short way).
  Uint8List? _carPng;
  double _carTurn = 0;

  bool get _following => widget.follow && !widget.overview;

  /// The style's own filters of the every-place layers, which [DriveMap.places] narrows.
  Map<String, Object?> _placeFilters = const {};

  /// The car's heading: the camera's bearing too, unless north is up.
  double _heading = 0;

  /// The camera's bearing, as last sent or about to be: the car, facing the screen, turns
  /// against it (straight up while the map follows it heading up).
  double _bearing = 0;

  double get _wantedBearing => widget.overview
      ? 0
      : widget.follow
      ? (widget.northUp ? 0 : _heading)
      : _bearing;

  /// A new style (day or night) comes without the layers: they, and the car, are set up again
  /// once it has loaded.
  @override
  void styleChanged() {
    _ready = false;
    _onCar = false;
  }

  /// On the car, a fix: the camera eases, at an even speed over [_fixEvery], to where the car
  /// will be by then, on along the road at its speed; slow or off the road, to the fix.
  Future<void> _glide() async {
    final at = widget.at;
    final c = mapController;
    if (at == null || c == null || !_onCar) return;
    final mps = widget.speedKmh / 3.6;
    final next = mps < 1
        ? null
        : alongRoad([
            for (final line in widget.route) ...line,
          ], mps * _fixEvery.inMilliseconds / 1000);
    final heading = next?.headingDeg ?? _heading;
    final bearing = widget.northUp ? 0.0 : heading;
    final turn = heading - bearing;
    setState(() => _carTurn += (turn - _carTurn + 540) % 360 - 180);
    await c.easeCamera(
      ml.CameraUpdate.newCameraPosition(
        ml.CameraPosition(
          target: (next?.at ?? at).toMapLibre,
          zoom: DriveMap.zoom,
          bearing: bearing,
          tilt: DriveMap.tilt,
        ),
      ),
      duration: _fixEvery,
      interpolation: ml.CameraAnimationInterpolation.linear,
    );
  }

  /// Eases the camera onto the car and from then on glides with it, the car drawn over the
  /// map; off the car (moved away, the overview) the car is the map's symbol again.
  Future<void> _followCar() async {
    final c = mapController;
    if (c == null || !_ready) return;
    if (!_following) {
      if (_onCar) setState(() => _onCar = false);
      await c.setGeoJsonSource(_Sources.car, _carGeoJson());
      await c.setLayerVisibility(_carLayer, true);
      return;
    }
    if (_onCar) return;
    await _moveCamera();
    if (!mounted || !_following || _onCar) return;
    setState(() {
      _onCar = true;
      _carTurn = 0;
    });
    await c.setLayerVisibility(_carLayer, false);
  }

  @override
  bool get englishNames =>
      ref.read(settingsProvider).value?.streetNames == StreetNameMode.english;

  /// On the car, which the [_carLow] padding sets about two thirds down the
  /// screen, the road ahead above it.
  ml.CameraPosition _camera(LatLng at) => ml.CameraPosition(
    target: at.toMapLibre,
    zoom: DriveMap.zoom,
    bearing: widget.northUp ? 0 : _heading,
    tilt: DriveMap.tilt,
  );

  /// The top half padded out, so the camera's centre (the car) sits half way
  /// down what is left, 75 % down the map: the road ahead fills the screen,
  /// the car clear of the bottom bar. MapLibre applies it with the tilt's
  /// perspective.
  Future<void> _carLow() async =>
      mapController?.setPadding(top: 0.5 * (mapSize?.height ?? 0));

  @override
  void didUpdateWidget(DriveMap old) {
    super.didUpdateWidget(old);
    _heading = widget.heading ?? _heading;
    final bearing = _bearing;
    _bearing = _wantedBearing;
    if (!_ready) return;
    final moved = widget.at != old.at || widget.heading != old.heading;
    final leftOverview = old.overview && !widget.overview;
    if (!_onCar && (moved || _bearing != bearing)) runMapWork(_moveCar);
    if (!identical(widget.route, old.route)) runMapWork(_sendRoute);
    if (!identical(widget.alternatives, old.alternatives)) {
      runMapWork(_sendAlternatives);
    }
    if (widget.overview && !old.overview) runMapWork(_showOverview);
    if (leftOverview) runMapWork(_carLow);
    if (_following != (old.follow && !old.overview)) {
      runMapWork(_followCar);
    } else if (_onCar && (moved || widget.northUp != old.northUp)) {
      runMapWork(_glide);
    }
    if (!identical(widget.turn, old.turn)) runMapWork(_sendTurn);
    if (!listEquals(widget.via, old.via)) runMapWork(_sendVia);
    if (_keptPlaces(widget) != _keptPlaces(old)) runMapWork(_sendPlaces);
  }

  /// The places shown: only [DriveMap.places] while following the car, else all (null).
  static Set<int>? _keptPlaces(DriveMap m) =>
      m.follow && !m.overview ? m.places : null;

  /// Narrows the every-place icons and names to [_keptPlaces], or lets them all show again.
  Future<void> _sendPlaces() async {
    final c = mapController;
    if (c == null || !_ready) return;
    final kept = _keptPlaces(widget);
    for (final id in [PoiLayers.all, NameLayers.poisAll]) {
      final base = _placeFilters[id] ?? ['all'];
      await c.setFilter(
        id,
        kept == null
            ? base
            : [
                'all',
                base,
                [
                  'in',
                  ['id'],
                  ['literal', kept.toList()],
                ],
              ],
      );
    }
  }

  Map<String, dynamic> _viaGeoJson() => labelledPointsGeoJson([
    for (final (i, at) in widget.via.indexed) (at, {'image': _viaImage(i + 1)}),
  ]);

  Future<void> _sendVia() async =>
      mapController?.setGeoJsonSource(_Sources.via, _viaGeoJson());

  Map<String, dynamic> _carGeoJson() =>
      pointsGeoJson([?widget.at], properties: {'turn': _heading - _bearing});

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
        // Clear of the speeds and the destination's pin above, the routes card (with Take
        // this route) and the bar below.
        top: 0.2 * size.height,
        bottom: 0.55 * size.height,
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
    // The icons before their layer shows: tiles laid out without an image keep no icon.
    await addBasemapImages(c, colors, pixelRatio);
    // A navigator shows every name and place (item 132), not only the landmarks.
    for (final (id, on) in [
      (NameLayers.pois, false),
      (PoiLayers.curated, false),
      (NameLayers.poisAll, true),
      (PoiLayers.all, true),
      (NameLayers.areas, true),
      (NameLayers.water, true),
      (NameLayers.roads, true),
      // Raised below instead.
      (_buildings, false),
    ]) {
      await c.setLayerVisibility(id, on);
    }
    await _addCity(c, colors, pixelRatio);
    // Rendered at a higher pixel ratio, the marks come out bigger and still sharp.
    final car = _carPng = await (widget.arrow
        ? ArrowMark(colors).toPng
        : CarMark(colors).toPng)(pixelRatio * _markScale);
    await c.addImage(_carImage, car);
    // The other ways first, so the route lies over them.
    await c.addGeoJsonSource(
      _Sources.alternatives,
      linesGeoJson(widget.alternatives),
    );
    await addCasedLine(
      c,
      _Sources.alternatives,
      casing: (colors.drivePlate, routeCasing),
      line: (colors.drivePlateText2, routeWidth),
    );
    await c.addGeoJsonSource(_Sources.route, linesGeoJson(widget.route));
    // A band about as wide as the road, in a thin casing; the tilt narrows it ahead.
    await addCasedLine(
      c,
      _Sources.route,
      casing: (colors.mapAnswerCasing, _routeWidth + 2 * PindoroStroke.base),
      line: (colors.mapAnswerLine, _routeWidth),
    );
    // The turn arrow, in the plate's colours over the route, as wide as it.
    await c.addGeoJsonSource(_Sources.turn, _turnLineGeoJson());
    await addCasedLine(
      c,
      _Sources.turn,
      casing: (colors.drivePlate, _routeWidth + 2 * PindoroStroke.thick),
      line: (colors.drivePlateText, _routeWidth),
    );
    await c.addImage(
      _turnHeadImage,
      await turnArrowHeadPng(
        fill: colors.drivePlateText,
        casing: colors.drivePlate,
        pixelRatio: pixelRatio * _markScale,
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
    // The destination: a pin standing on it, in the route's colours.
    await c.addImage(
      _endImage,
      await PinMark(
        face: colors.mapAnswerLine,
        lip: colors.mapAnswerCasing,
        outline: colors.mapAnswerCasing,
        dot: colors.mapAnswerCasing,
      ).toPng(pixelRatio),
    );
    for (var n = 1; n <= LearningConfig.navViaMax; n++) {
      await c.addImage(
        _viaImage(n),
        await PinMark.endpoint('$n', colors).toPng(pixelRatio),
      );
    }
    await c.addGeoJsonSource(_Sources.via, _viaGeoJson());
    await c.addSymbolLayer(
      _Sources.via,
      '${_Sources.via}-pin',
      ml.SymbolLayerProperties(
        iconImage: const ['get', 'image'],
        iconAnchor: 'bottom',
        iconOffset: [0, PinMark.tipInset * pixelRatio],
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      enableInteraction: false,
    );
    await c.addGeoJsonSource(_Sources.end, pointsGeoJson([widget.destination]));
    await c.addSymbolLayer(
      _Sources.end,
      '${_Sources.end}-pin',
      endpointLayer(_endImage, pixelRatio),
      enableInteraction: false,
    );
    await c.addGeoJsonSource(_Sources.car, _carGeoJson());
    await c.addSymbolLayer(
      _Sources.car,
      _carLayer,
      const ml.SymbolLayerProperties(
        iconImage: _carImage,
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        // Facing the screen (laid on the steeply tilted road it would flatten), turned on it
        // by its heading against the camera's: MapLibre skews a map-turned icon that faces
        // the screen of a tilted map.
        iconPitchAlignment: 'viewport',
        iconRotate: ['get', 'turn'],
        iconRotationAlignment: 'viewport',
      ),
      enableInteraction: false,
    );
    await _carLow();
    if (await mapStyle case final style?) {
      _placeFilters = {
        for (final id in [PoiLayers.all, NameLayers.poisAll])
          id: styleFilter(style, id),
      };
    }
    _ready = true;
    await _followCar();
    await _sendPlaces();
  }

  /// The city as a navigator shows it: the buildings raised, their house numbers and the
  /// traffic lights at the junctions that have them; all under the route and the names.
  Future<void> _addCity(
    ml.MapLibreMapController c,
    PindoroColors colors,
    double pixelRatio,
  ) async {
    await c.addFillExtrusionLayer(
      _basemap,
      'drive-buildings',
      ml.FillExtrusionLayerProperties(
        fillExtrusionColor: hexColor(colors.mapVectorBuilding),
        fillExtrusionHeight: [
          '*',
          [
            'coalesce',
            ['get', 'height'],
            _defaultHeightM,
          ],
          _heightScale,
        ],
        fillExtrusionBase: [
          '*',
          [
            'coalesce',
            ['get', 'min_height'],
            0,
          ],
          _heightScale,
        ],
        fillExtrusionOpacity: PindoroOpacity.buildingRaised,
      ),
      sourceLayer: _buildings,
      minzoom: _raisedZoom,
      belowLayerId: NameLayers.lowest,
      enableInteraction: false,
    );
    await c.addSymbolLayer(
      _basemap,
      'drive-house-numbers',
      ml.SymbolLayerProperties(
        textField: ['get', 'addr_housenumber'],
        textFont: const ['FiraGO Regular'],
        textSize: PindoroType.labelSm.fontSize,
        textColor: hexColor(colors.mapVectorLabel),
        textHaloColor: hexColor(colors.mapVectorLand),
        textHaloWidth: PindoroStroke.hairline,
      ),
      sourceLayer: _buildings,
      minzoom: _numbersZoom,
      filter: ['has', 'addr_housenumber'],
      belowLayerId: NameLayers.lowest,
      enableInteraction: false,
    );
    final graph = ref.read(packRepositoryProvider).value?.roadGraph();
    await c.addImage(
      _lightsImage,
      await driveGlyphPng(
        DriveGlyphName.lights,
        color: colors.drivePlate,
        cut: colors.drivePlateGlyph,
        size: PindoroSize.iconMd,
        pixelRatio: pixelRatio,
      ),
    );
    await c.addGeoJsonSource(
      _Sources.lights,
      pointsGeoJson([
        if (graph != null)
          for (final j in graph.signals) ?graph.junctions[j],
      ]),
    );
    // Lights that would overlap a name or each other (a junction's several nodes) give way.
    await c.addSymbolLayer(
      _Sources.lights,
      '${_Sources.lights}-mark',
      const ml.SymbolLayerProperties(iconImage: _lightsImage),
      minzoom: _raisedZoom,
      enableInteraction: false,
    );
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
              if (_onCar && _carPng != null)
                Positioned(
                  // Where the camera centres the car: half way down the half [_carLow]
                  // leaves below its padding.
                  left: mapSize!.width / 2,
                  top: mapSize!.height * 0.75,
                  child: IgnorePointer(
                    child: FractionalTranslation(
                      translation: const Offset(-0.5, -0.5),
                      child: AnimatedRotation(
                        turns: _carTurn / 360,
                        duration: _fixEvery,
                        child: Image.memory(
                          _carPng!,
                          scale: MediaQuery.devicePixelRatioOf(context),
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
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
