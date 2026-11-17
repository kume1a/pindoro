import 'dart:async';
import 'dart:math' as math show max, pi, sin;
import 'dart:math' show Point;

import 'package:flutter/foundation.dart' show Factory, listEquals;
import 'package:flutter/gestures.dart'
    show EagerGestureRecognizer, OneSequenceGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/location.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/core/toast.dart';
import 'package:pindoro/features/map/data/geojson.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/data/maplibre_convert.dart';
import 'package:pindoro/features/map/ui/map_work.dart';
import 'package:pindoro/features/map/ui/poi_icons.dart';
import 'package:pindoro/features/map/ui/route_layers.dart';
import 'package:pindoro/features/map/ui/route_projection.dart';
import 'package:pindoro/features/map/ui/widgets/map_attribution.dart';
import 'package:pindoro/features/map/ui/widgets/map_taps.dart';
import 'package:pindoro/features/map/ui/widgets/map_zoom_controls.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// GeoJSON source ids.
abstract final class _MapSources {
  static const String areaMask = 'area-mask';
  static const String youPin = 'you-pin';
  static const String truthStreet = 'truth-street';
  static const String truthPoint = 'truth-point';
  static const String measure = 'measure';
  static const String measureEnd = 'measure-end';
  static const String measureLabel = 'measure-label';
  static const String trace = 'trace';
  static const String hitStreet = 'hit-street';
}

/// The dotted line from the pin to the nearest point of the street, with its
/// distance chip hanging under its middle (never under the pin).
typedef Measure = ({LatLng from, LatLng to, String label});

/// A drill's street trace (`opacity.street-trace` over `color.map.region.outline`).
const double _traceWidth = 6;

/// How far around a place its map frames, so its crossings show.
const double _placeFrameM = 200;

const String _pinImage = 'player-pin';

/// Builds the game map; widget tests override it so no platform view is made.
final pindoroMapBuilderProvider = Provider<Widget Function(PindoroMap map)>(
  (ref) =>
      (map) => map,
);

/// Self-hosted basemap, unlabelled but for the [names] it is given: the
/// round's area (outside dimmed) plus the pin, truth street and measure line
/// passed in by the caller, or a road [route]. [bottomInset] is the height of
/// whatever covers the bottom of the map (button, sheet): controls and
/// attribution sit above it and the camera frames above it; until the player
/// moves the map, it frames again whenever an inset changes. [frame] replaces the area as what the camera fits (and
/// fits again whenever it changes); [onCamera] hears every camera move.
class PindoroMap extends ConsumerStatefulWidget {
  const PindoroMap({
    super.key,
    required this.area,
    this.pin,
    this.truth,
    this.truthPoint,
    this.measure,
    this.onTap,
    this.bottomInset = 0,
    this.topInset = 0,
    this.showControls = true,
    this.route,
    this.frame,
    this.onCamera,
    this.ownsGestures = false,
    this.names = const MapNames(),
    this.traces = const [],
    this.hit,
    this.morePins = const [],
    this.bearing = 0,
  });

  final AreaShape area;
  final LatLng? pin;
  final MultiPolyline? truth;

  /// A place as the answer: a yellow dot over an ink ring, framed with what
  /// is around it and the pin.
  final LatLng? truthPoint;
  final Measure? measure;
  final ValueChanged<LatLng>? onTap;
  final double bottomInset;

  /// Height covered at the top (top bar and plate), for framing.
  final double topInset;
  final bool showControls;
  final RouteOverlay? route;
  final List<LatLng>? frame;
  final ValueChanged<MapProjection>? onCamera;

  /// Inside a scroll view: drags and pinches on the map move the map, not
  /// the page.
  final bool ownsGestures;

  /// The street and place names the basemap draws (none by default).
  final MapNames names;

  /// A drill's streets, traced grey.
  final MultiPolyline traces;

  /// A Mix-up's hit street, dashed cobalt.
  final MultiPolyline? hit;

  /// The player's other pins (a street's second end).
  final List<LatLng> morePins;

  /// Where the top of the screen faces, degrees clockwise from north: a
  /// turn card drives up the screen.
  final double bearing;

  @override
  ConsumerState<PindoroMap> createState() => _PindoroMapState();
}

class _PindoroMapState extends ConsumerState<PindoroMap>
    with TickerProviderStateMixin {
  ml.MapLibreMapController? _controller;
  bool _locating = false;

  /// The camera is still where the last fit put it: no touch or control has
  /// moved it since.
  bool _framed = false;

  /// The pin drop: falls 24 dp and bounces once (`motion.pin-drop`).
  late final AnimationController _drop = AnimationController(
    vsync: this,
    duration: PindoroMotion.pinDrop,
  )..addListener(_dropTick);

  /// The answer paint spreading out from the point nearest the pin.
  late final AnimationController _paint = AnimationController(
    vsync: this,
    duration: PindoroMotion.durationBase,
  )..addListener(_paintTick);
  double _paintReachM = 0;
  double _pixelRatio = 1;
  Size? _size;

  /// B pops when the route reaches it (`spring.bouncy`, a quick grow).
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: PindoroMotion.durationBase,
  )..addListener(_popTick);
  Brightness? _brightness;
  Future<String>? _style;

  /// The style's own filters of its name layers, which [MapNames] narrows.
  Map<String, Object?> _baseFilters = const {};
  bool _overlaysReady = false;
  final Set<String> _measureImages = {};

  /// The route as the map last got it; null until it got one (per style).
  RouteOverlay? _sentRoute;
  bool _sendingRoute = false;
  bool _routeChanged = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (brightness != _brightness) {
      _brightness = brightness;
      _overlaysReady = false;
      _style = loadMapStyle(
        brightness,
        english:
            ref.read(settingsProvider).value?.streetNames ==
            StreetNameMode.english,
      );
    }
  }

  /// The pin symbol anchored at its tip, raised by [dy] dp.
  ml.SymbolLayerProperties _pinLayer(double dy) => ml.SymbolLayerProperties(
    iconImage: _pinImage,
    iconAnchor: 'bottom',
    iconOffset: [0, dy * _pixelRatio],
    iconAllowOverlap: true,
    iconIgnorePlacement: true,
  );

  @override
  void dispose() {
    _controller?.removeListener(_cameraMoved);
    _drop.dispose();
    _paint.dispose();
    _pop.dispose();
    super.dispose();
  }

  void _popTick() {
    if (!_overlaysReady || _controller == null) return;
    unawaited(
      scaleB(
        _controller!,
        _pixelRatio,
        1 + 0.25 * math.sin(math.pi * _pop.value),
      ),
    );
  }

  MapProjection? get _projection {
    final camera = _controller?.cameraPosition;
    final size = _size;
    if (camera == null || size == null) return null;
    return MapProjection(
      target: camera.target.toCore,
      zoom: camera.zoom,
      size: size,
      bearing: camera.bearing,
    );
  }

  void _cameraMoved() {
    if (_projection case final projection?) widget.onCamera?.call(projection);
  }

  void _tapped(Offset at) {
    if (_projection case final projection?) {
      widget.onTap?.call(projection.toLatLng(at));
    }
  }

  /// A screen reader's double-tap drops the pin at the centre.
  void _tappedCentre() {
    if (_controller?.cameraPosition case final camera?) {
      widget.onTap?.call(camera.target.toCore);
    }
  }

  /// The truth street as painted so far.
  MultiPolyline get _paintedTruth {
    final truth = widget.truth ?? const [];
    final from = widget.measure?.to;
    if (from == null || !_paint.isAnimating) return truth;
    final eased = PindoroMotion.easeStandard.transform(_paint.value);
    return clipToCircle(truth, from, _paintReachM * eased);
  }

  // Ticks skip frames while a new style (theme change) lacks the sources.
  void _paintTick() {
    if (!_overlaysReady) return;
    _controller?.setGeoJsonSource(
      _MapSources.truthStreet,
      linesGeoJson(_paintedTruth),
    );
  }

  void _startPaint() {
    final from = widget.measure?.to;
    if (from == null || MediaQuery.disableAnimationsOf(context)) return;
    _paintReachM = widget.truth!
        .expand((l) => l)
        .fold(0, (far, p) => math.max(far, distanceBetween(from, p)));
    unawaited(_paint.forward(from: 0));
  }

  void _dropTick() {
    if (!_overlaysReady) return;
    final fall = 24 * (1 - Curves.bounceOut.transform(_drop.value));
    // setLayerProperties replaces every property, so send them all.
    _controller?.setLayerProperties(
      '${_MapSources.youPin}-pin',
      _pinLayer(PinMark.tipInset - fall),
    );
  }

  @override
  void didUpdateWidget(PindoroMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_overlaysReady) return;
    if (widget.pin != null &&
        widget.pin != oldWidget.pin &&
        widget.truth == null &&
        !MediaQuery.disableAnimationsOf(context)) {
      unawaited(_drop.forward(from: 0));
    }
    if (widget.truth != null && widget.measure?.to != oldWidget.measure?.to) {
      _startPaint();
    }
    if (widget.pin != oldWidget.pin ||
        !listEquals(widget.morePins, oldWidget.morePins) ||
        widget.truth != oldWidget.truth ||
        widget.truthPoint != oldWidget.truthPoint ||
        widget.measure != oldWidget.measure ||
        !listEquals(widget.traces, oldWidget.traces) ||
        widget.hit != oldWidget.hit) {
      runMapWork(_syncOverlays);
    }
    if (widget.names != oldWidget.names) runMapWork(_syncNames);
    final frame = widget.frame;
    final insetsMoved =
        widget.topInset != oldWidget.topInset ||
        widget.bottomInset != oldWidget.bottomInset;
    if (widget.truth != oldWidget.truth ||
        widget.truthPoint != oldWidget.truthPoint ||
        (frame != null && !listEquals(frame, oldWidget.frame)) ||
        (insetsMoved && _framed)) {
      unawaited(_fit(_framePoints));
    }
    if (widget.route != oldWidget.route) {
      runMapWork(_sendRoute);
      if ((widget.route?.reached ?? false) &&
          !(oldWidget.route?.reached ?? false) &&
          !MediaQuery.disableAnimationsOf(context)) {
        unawaited(_pop.forward(from: 0));
      }
    }
  }

  /// The [PindoroMap.frame], else the area's bounds.
  List<LatLng> get _areaFrame {
    if (widget.frame case final frame?) return frame;
    final b = widget.area.bbox;
    return [LatLng(b.minLat, b.minLon), LatLng(b.maxLat, b.maxLon)];
  }

  /// What the camera frames: the street (or the place and the streets
  /// around it) and the pin once revealed, else [_areaFrame].
  List<LatLng> get _framePoints => switch ((widget.truth, widget.truthPoint)) {
    (final truth?, _) => [
      ...truth.expand((l) => l),
      ?widget.pin,
      ...widget.morePins,
    ],
    (null, final place?) => [..._around(place), ?widget.pin],
    _ => _areaFrame,
  };

  /// A square [_placeFrameM] out from [at] each way.
  static List<LatLng> _around(LatLng at) {
    final local = LocalProjection(at);
    return [
      local.unproject((-_placeFrameM, -_placeFrameM)),
      local.unproject((_placeFrameM, _placeFrameM)),
    ];
  }

  Future<void> _fitArea() => _fit(_areaFrame);

  /// The camera fitting [points] between the insets. Computed here rather
  /// than with a bounds update, whose padding stays on the camera and moves
  /// its target off the view's centre, where [MapProjection] (taps, road
  /// trips) expects it.
  ({LatLng target, double zoom}) _cameraFor(
    List<LatLng> points,
    Size size,
  ) => MapProjection.fit(
    points,
    size: size,
    bearing: widget.bearing,
    padding: EdgeInsets.fromLTRB(
      PindoroCamera.fitPaddingX,
      widget.topInset + PindoroSpace.s6,
      // A framed street, or a road trip's A and B pins (drawn centred on
      // their point), must clear the map controls on the right.
      widget.showControls && (widget.onCamera != null || widget.truth != null)
          ? PindoroSize.tapMin + 2 * PindoroSpace.s4 + PindoroSize.pinPlayer / 2
          : PindoroCamera.fitPaddingX,
      // Clear of the attribution chip, which sits above the bottom inset.
      widget.bottomInset + MapAttribution.clearance(context),
    ),
  );

  Future<void> _fit(List<LatLng> points) async {
    final size = _size;
    if (size == null) return;
    _framed = true;
    final camera = _cameraFor(points, size);
    await _controller?.animateCamera(
      ml.CameraUpdate.newCameraPosition(
        ml.CameraPosition(
          target: camera.target.toMapLibre,
          zoom: camera.zoom,
          bearing: widget.bearing,
        ),
      ),
    );
  }

  Future<void> _addOverlays() async {
    final c = _controller;
    if (c == null) return;
    final colors = PindoroTheme.of(context).colors;
    final pixelRatio = _pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final pin = PinMark(
      face: colors.mapPlayerPin,
      lip: colors.mapPlayerPinLip,
      dot: colors.mapPlayerHalo,
      halo: colors.mapPlayerHalo,
    );
    await c.addImage(_pinImage, await pin.toPng(pixelRatio));
    // Overlays must stay non-interactive: maplibre_gl reports taps on interactive
    // layers as feature taps instead of map clicks, which would block pin drops.
    // Lines go under the basemap's names, points over them.
    await c.addGeoJsonSource(
      _MapSources.areaMask,
      areaMaskGeoJson(widget.area.boundary),
    );
    await c.addFillLayer(
      _MapSources.areaMask,
      '${_MapSources.areaMask}-fill',
      ml.FillLayerProperties(
        fillColor: hexColor(colors.mapMask),
        fillOpacity: PindoroOpacity.mask,
      ),
      belowLayerId: NameLayers.roads,
      enableInteraction: false,
    );
    if (widget.route != null) await addRouteLayers(c, colors, pixelRatio);
    await c.addGeoJsonSource(_MapSources.trace, linesGeoJson(const []));
    await c.addLineLayer(
      _MapSources.trace,
      '${_MapSources.trace}-line',
      ml.LineLayerProperties(
        lineColor: hexColor(colors.mapRegionOutline),
        lineWidth: _traceWidth,
        lineOpacity: PindoroOpacity.streetTrace,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      belowLayerId: NameLayers.roads,
      enableInteraction: false,
    );
    await c.addGeoJsonSource(_MapSources.truthStreet, linesGeoJson(const []));
    // Yellow paint over an ink casing: on light maps the casing carries contrast.
    for (final (id, color, width) in [
      (
        'casing',
        colors.mapAnswerCasing,
        PindoroStroke.answer + 2 * PindoroStroke.base,
      ),
      ('line', colors.mapAnswerLine, PindoroStroke.answer),
    ]) {
      await c.addLineLayer(
        _MapSources.truthStreet,
        '${_MapSources.truthStreet}-$id',
        ml.LineLayerProperties(
          lineColor: hexColor(color),
          lineWidth: width,
          lineCap: 'round',
          lineJoin: 'round',
        ),
        belowLayerId: NameLayers.roads,
        enableInteraction: false,
      );
    }
    await c.addGeoJsonSource(_MapSources.hitStreet, linesGeoJson(const []));
    for (final (id, color, width, dash) in [
      ('halo', colors.mapPlayerHalo, drawnHalo, null),
      (
        'line',
        colors.mapPlayerRoute,
        drawnWidth,
        [drawnDash / drawnWidth, drawnGap / drawnWidth],
      ),
    ]) {
      await c.addLineLayer(
        _MapSources.hitStreet,
        '${_MapSources.hitStreet}-$id',
        ml.LineLayerProperties(
          lineColor: hexColor(color),
          lineWidth: width,
          lineJoin: 'round',
          lineCap: dash == null ? 'round' : null,
          lineDasharray: dash,
        ),
        belowLayerId: NameLayers.roads,
        enableInteraction: false,
      );
    }
    await c.addGeoJsonSource(_MapSources.measure, linesGeoJson(const []));
    await c.addLineLayer(
      _MapSources.measure,
      '${_MapSources.measure}-line',
      ml.LineLayerProperties(
        lineColor: hexColor(colors.mapMeasureLine),
        lineWidth: PindoroStroke.thick,
        lineCap: 'round',
        // Dots: zero-length dashes with round caps; dash units are line widths.
        lineDasharray: [0, PindoroSize.mapMeasureGap / PindoroStroke.thick],
      ),
      belowLayerId: NameLayers.roads,
      enableInteraction: false,
    );
    await c.addGeoJsonSource(_MapSources.measureEnd, pointsGeoJson(const []));
    await c.addCircleLayer(
      _MapSources.measureEnd,
      '${_MapSources.measureEnd}-ring',
      ml.CircleLayerProperties(
        circleColor: hexColor(colors.mapPlayerHalo),
        circleRadius: PindoroStroke.thick + PindoroStroke.base,
        circleStrokeColor: hexColor(colors.mapMeasureLine),
        circleStrokeWidth: PindoroStroke.base,
      ),
      enableInteraction: false,
    );
    await c.addGeoJsonSource(_MapSources.measureLabel, pointsGeoJson(const []));
    await c.addSymbolLayer(
      _MapSources.measureLabel,
      '${_MapSources.measureLabel}-chip',
      // On the line's far side from the pin (`from`), which stands above its
      // tip: a short line's chip would otherwise hide behind it.
      ml.SymbolLayerProperties(
        iconImage: ['get', 'icon'],
        iconAnchor: ['get', 'anchor'],
        iconOffset: [
          'case',
          [
            '==',
            ['get', 'anchor'],
            'top',
          ],
          [
            'literal',
            [0, PindoroSpace.s2 * pixelRatio],
          ],
          [
            'literal',
            [0, -PindoroSpace.s2 * pixelRatio],
          ],
        ],
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      enableInteraction: false,
    );
    await c.addGeoJsonSource(_MapSources.truthPoint, pointsGeoJson(const []));
    await c.addCircleLayer(
      _MapSources.truthPoint,
      '${_MapSources.truthPoint}-dot',
      ml.CircleLayerProperties(
        circleColor: hexColor(colors.mapAnswerLine),
        circleRadius: PindoroStroke.answer,
        circleStrokeColor: hexColor(colors.mapAnswerCasing),
        circleStrokeWidth: PindoroStroke.base * 2,
      ),
      enableInteraction: false,
    );
    _measureImages.clear();
    _sentRoute = null;
    await c.addGeoJsonSource(_MapSources.youPin, pointsGeoJson(const []));
    await c.addSymbolLayer(
      _MapSources.youPin,
      '${_MapSources.youPin}-pin',
      _pinLayer(PinMark.tipInset),
      enableInteraction: false,
    );
    _overlaysReady = true;
    await _syncOverlays();
    await _fit(_framePoints);
    _cameraMoved();
    if (await _style case final style?) {
      _baseFilters = {
        for (final id in [NameLayers.roads, NameLayers.pois])
          id: styleFilter(style, id),
      };
    }
    await _syncNames();
    await addPoiImages(c, colors, pixelRatio);
  }

  /// Shows [PindoroMap.names] through the style's name layers.
  Future<void> _syncNames() async {
    final c = _controller;
    if (!_overlaysReady || c == null) return;
    final names = widget.names;
    for (final (id, filter) in [
      (NameLayers.roads, names.roadFilter(_baseFilters[NameLayers.roads])),
      (NameLayers.pois, names.placeFilter(_baseFilters[NameLayers.pois])),
    ]) {
      if (filter != null) await c.setFilter(id, filter);
      await c.setLayerVisibility(id, filter != null);
    }
  }

  Future<void> _syncOverlays() async {
    final c = _controller!;
    final pin = widget.pin;
    final measure = widget.measure;
    await c.setGeoJsonSource(
      _MapSources.youPin,
      pointsGeoJson([?pin, ...widget.morePins]),
    );
    await c.setGeoJsonSource(
      _MapSources.truthStreet,
      linesGeoJson(_paintedTruth),
    );
    await c.setGeoJsonSource(
      _MapSources.truthPoint,
      pointsGeoJson([?widget.truthPoint]),
    );
    await c.setGeoJsonSource(
      _MapSources.measure,
      linesGeoJson([
        if (measure != null) [measure.from, measure.to],
      ]),
    );
    await c.setGeoJsonSource(
      _MapSources.measureEnd,
      pointsGeoJson([?measure?.to]),
    );
    await c.setGeoJsonSource(
      _MapSources.measureLabel,
      measure == null ? pointsGeoJson(const []) : await _measureChip(measure),
    );
    await c.setGeoJsonSource(_MapSources.trace, linesGeoJson(widget.traces));
    await c.setGeoJsonSource(
      _MapSources.hitStreet,
      linesGeoJson(widget.hit ?? const []),
    );
    if (widget.route != null) await _sendRoute();
  }

  /// Sends the route's changes since the last send. One send at a time:
  /// changes made meanwhile go out together right after it, so a fast drag
  /// never queues up stale frames on the platform channel.
  Future<void> _sendRoute() async {
    if (_sendingRoute) {
      _routeChanged = true;
      return;
    }
    _sendingRoute = true;
    try {
      do {
        _routeChanged = false;
        final route = widget.route;
        await syncRoute(_controller!, route, _sentRoute, _chipImage);
        _sentRoute = route;
      } while (_routeChanged);
    } finally {
      _sendingRoute = false;
    }
  }

  /// The chip's point half-way along the measure line, its image added once
  /// per label.
  Future<Map<String, dynamic>> _measureChip(Measure m) async {
    final icon = await _chipImage(m.label);
    return pointsGeoJson(
      [
        Bbox.of([m.from, m.to]).center,
      ],
      // A pin south of the middle reaches up to it: the chip goes above.
      properties: {
        'icon': icon,
        'anchor': m.from.lat < m.to.lat ? 'bottom' : 'top',
      },
    );
  }

  /// An ink distance chip's image, added once per label; returns its id.
  Future<String> _chipImage(String label) async {
    final icon = 'measure:$label';
    if (_measureImages.add(icon)) {
      final chip = MapChip.distance(label, PindoroTheme.of(context).colors);
      await _controller!.addImage(icon, await chip.toPng(_pixelRatio));
    }
    return icon;
  }

  /// One locate at a time: the permission prompt answers only the first.
  Future<void> _goToMyLocation() async {
    if (_locating) return;
    _locating = true;
    _framed = false;
    try {
      final result = await ref.read(locationServiceProvider).locate();
      if (!mounted) return;
      switch (result) {
        case Located(:final position):
          await _controller?.animateCamera(
            ml.CameraUpdate.newLatLng(position.toMapLibre),
          );
        case LocationDenied():
          showToast(
            context,
            context.l10n.cityLocationDenied,
            above: widget.bottomInset,
          );
        case LocationUnavailable():
          showToast(
            context,
            context.l10n.locationUnavailable,
            above: widget.bottomInset,
          );
      }
    } finally {
      _locating = false;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = _size = constraints.biggest;
      return _map(context, size);
    },
  );

  Widget _map(BuildContext context, Size size) => FutureBuilder<String>(
    future: _style,
    builder: (context, style) {
      final l10n = context.l10n;
      final taps = widget.onTap != null;
      // Opens where the load would frame it, so nothing zooms in after.
      final start = _cameraFor(_framePoints, size);
      return Stack(
        children: [
          if (style.hasData)
            Semantics(
              label: taps ? l10n.a11yMap : null,
              onTap: taps ? _tappedCentre : null,
              child: MapTaps(
                onTap: taps ? _tapped : null,
                child: Listener(
                  onPointerDown: (_) => _framed = false,
                  child: ml.MapLibreMap(
                    styleString: style.data!,
                    initialCameraPosition: ml.CameraPosition(
                      target: start.target.toMapLibre,
                      zoom: start.zoom,
                      bearing: widget.bearing,
                    ),
                    gestureRecognizers: widget.ownsGestures
                        ? {
                            Factory<OneSequenceGestureRecognizer>(
                              EagerGestureRecognizer.new,
                            ),
                          }
                        : null,
                    onMapCreated: (c) =>
                        _controller = c..addListener(_cameraMoved),
                    trackCameraPosition: widget.onCamera != null || taps,
                    onStyleLoadedCallback: () => runMapWork(_addOverlays),
                    // A tap drops the pin at once, so a second can't zoom.
                    doubleClickZoomEnabled: taps ? false : null,
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                    compassEnabled: false,
                    // Our own chip carries the attribution text.
                    attributionButtonMargins: const Point(-100, -100),
                  ),
                ),
              ),
            ),
          if (widget.showControls)
            Positioned(
              right: PindoroSpace.s4,
              bottom: widget.bottomInset + PindoroSpace.s4,
              child: Column(
                children: [
                  MapControl(
                    glyph: PindoroGlyph.locate,
                    semanticLabel: l10n.a11yGoToMyLocation,
                    onPressed: _goToMyLocation,
                  ),
                  const SizedBox(height: PindoroSpace.s2),
                  MapControl(
                    glyph: PindoroGlyph.compass,
                    semanticLabel: l10n.a11yRecentre,
                    onPressed: _fitArea,
                  ),
                  MapZoomControls(
                    top: PindoroSpace.s2,
                    onCamera: (update) {
                      _framed = false;
                      unawaited(_controller?.animateCamera(update));
                    },
                  ),
                ],
              ),
            ),
          Positioned(
            left: PindoroSpace.s4,
            bottom: widget.bottomInset + MapAttribution.gap,
            child: const MapAttribution(),
          ),
        ],
      );
    },
  );
}
