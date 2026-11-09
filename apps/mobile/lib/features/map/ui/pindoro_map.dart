import 'dart:async';
import 'dart:math' as math show max, pi, sin;
import 'dart:math' show Point;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/location.dart';
import 'package:pindoro/core/toast.dart';
import 'package:pindoro/features/map/data/geojson.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/data/maplibre_convert.dart';
import 'package:pindoro/features/map/ui/map_work.dart';
import 'package:pindoro/features/map/ui/route_layers.dart';
import 'package:pindoro/features/map/ui/route_projection.dart';
import 'package:pindoro/features/map/ui/widgets/map_attribution.dart';
import 'package:pindoro/features/map/ui/widgets/map_zoom_controls.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// GeoJSON source ids.
abstract final class _MapSources {
  static const String areaMask = 'area-mask';
  static const String youPin = 'you-pin';
  static const String truthStreet = 'truth-street';
  static const String measure = 'measure';
  static const String measureEnd = 'measure-end';
  static const String measureLabel = 'measure-label';
}

/// The dotted line from the pin to the nearest point of the street, with its
/// distance chip half-way.
typedef Measure = ({LatLng from, LatLng to, String label});

const String _pinImage = 'player-pin';

/// Builds the game map; widget tests override it so no platform view is made.
final pindoroMapBuilderProvider = Provider<Widget Function(PindoroMap map)>(
  (ref) =>
      (map) => map,
);

/// Unlabelled self-hosted basemap: the round's area (outside dimmed) plus the
/// pin, truth street and measure line passed in by the caller, or a road
/// [route]. [bottomInset] is the height of whatever covers the bottom of the
/// map (button, sheet): controls and attribution sit above it and the camera
/// frames above it. [frame] replaces the area as what the camera fits (and
/// fits again whenever it changes); [onCamera] hears every camera move.
class PindoroMap extends ConsumerStatefulWidget {
  const PindoroMap({
    super.key,
    required this.area,
    this.pin,
    this.truth,
    this.measure,
    this.onTap,
    this.bottomInset = 0,
    this.topInset = 0,
    this.showControls = true,
    this.route,
    this.frame,
    this.onCamera,
  });

  final AreaShape area;
  final LatLng? pin;
  final MultiPolyline? truth;
  final Measure? measure;
  final ValueChanged<LatLng>? onTap;
  final double bottomInset;

  /// Height covered at the top (top bar and plate), for framing.
  final double topInset;
  final bool showControls;
  final RouteOverlay? route;
  final List<LatLng>? frame;
  final ValueChanged<MapProjection>? onCamera;

  @override
  ConsumerState<PindoroMap> createState() => _PindoroMapState();
}

class _PindoroMapState extends ConsumerState<PindoroMap>
    with TickerProviderStateMixin {
  ml.MapLibreMapController? _controller;
  bool _locating = false;

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
  bool _overlaysReady = false;
  final Set<String> _measureImages = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (brightness != _brightness) {
      _brightness = brightness;
      _overlaysReady = false;
      _style = loadMapStyle(brightness);
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

  void _cameraMoved() {
    final camera = _controller?.cameraPosition;
    final size = _size;
    if (camera == null || size == null) return;
    widget.onCamera?.call(
      MapProjection(
        target: camera.target.toCore,
        zoom: camera.zoom,
        size: size,
      ),
    );
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
        widget.truth != oldWidget.truth ||
        widget.measure != oldWidget.measure) {
      runMapWork(_syncOverlays);
    }
    if (widget.truth != null && widget.truth != oldWidget.truth) {
      unawaited(_fit([...widget.truth!.expand((l) => l), ?widget.pin]));
    } else if (widget.truth == null && oldWidget.truth != null) {
      unawaited(_fitArea());
    }
    if (widget.route != oldWidget.route) {
      final before = oldWidget.route;
      runMapWork(
        () => syncRoute(_controller!, widget.route, before, _chipImage),
      );
      if ((widget.route?.reached ?? false) &&
          !(before?.reached ?? false) &&
          !MediaQuery.disableAnimationsOf(context)) {
        unawaited(_pop.forward(from: 0));
      }
    }
    final frame = widget.frame;
    if (frame != null && !listEquals(frame, oldWidget.frame)) {
      unawaited(_fit(frame));
    }
  }

  Future<void> _fitArea() {
    if (widget.frame case final frame?) return _fit(frame);
    final b = widget.area.bbox;
    return _fit([LatLng(b.minLat, b.minLon), LatLng(b.maxLat, b.maxLon)]);
  }

  Future<void> _fit(List<LatLng> points) async {
    final padding = EdgeInsets.fromLTRB(
      PindoroCamera.fitPaddingX,
      widget.topInset + PindoroSpace.s6,
      // A road trip's A and B must clear the map controls on the right.
      widget.onCamera != null && widget.showControls
          ? PindoroSize.tapMin + 2 * PindoroSpace.s4
          : PindoroCamera.fitPaddingX,
      widget.bottomInset + PindoroSpace.s6,
    );
    final size = _size;
    // A bounds update keeps its padding on the camera, which moves the target
    // off the view's centre; [MapProjection] needs it there.
    if (widget.onCamera != null && size != null) {
      final camera = MapProjection.fit(points, size: size, padding: padding);
      await _controller?.animateCamera(
        ml.CameraUpdate.newLatLngZoom(camera.target.toMapLibre, camera.zoom),
      );
      return;
    }
    await _controller?.animateCamera(
      ml.CameraUpdate.newLatLngBounds(
        Bbox.of(points).toMapLibre,
        left: padding.left,
        top: padding.top,
        right: padding.right,
        bottom: padding.bottom,
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
      enableInteraction: false,
    );
    if (widget.route != null) await addRouteLayers(c, colors, pixelRatio);
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
      const ml.SymbolLayerProperties(
        iconImage: ['get', 'icon'],
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      enableInteraction: false,
    );
    _measureImages.clear();
    await c.addGeoJsonSource(_MapSources.youPin, pointsGeoJson(const []));
    await c.addSymbolLayer(
      _MapSources.youPin,
      '${_MapSources.youPin}-pin',
      _pinLayer(PinMark.tipInset),
      enableInteraction: false,
    );
    _overlaysReady = true;
    await _syncOverlays();
    await (widget.truth == null
        ? _fitArea()
        : _fit([...widget.truth!.expand((l) => l), ?widget.pin]));
    _cameraMoved();
  }

  Future<void> _syncOverlays() async {
    final c = _controller!;
    final pin = widget.pin;
    final measure = widget.measure;
    await c.setGeoJsonSource(_MapSources.youPin, pointsGeoJson([?pin]));
    await c.setGeoJsonSource(
      _MapSources.truthStreet,
      linesGeoJson(_paintedTruth),
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
    if (widget.route != null) {
      await syncRoute(c, widget.route, null, _chipImage);
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
      properties: {'icon': icon},
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
    try {
      final result = await ref.read(locationServiceProvider).locate();
      if (!mounted) return;
      switch (result) {
        case Located(:final position):
          await _controller?.animateCamera(
            ml.CameraUpdate.newLatLng(position.toMapLibre),
          );
        case LocationDenied():
          showToast(context, context.l10n.cityLocationDenied);
        case LocationUnavailable():
          showToast(context, context.l10n.locationUnavailable);
      }
    } finally {
      _locating = false;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _size = constraints.biggest;
      return _map(context);
    },
  );

  Widget _map(BuildContext context) => FutureBuilder<String>(
    future: _style,
    builder: (context, style) {
      final l10n = context.l10n;
      final center = widget.area.bbox.center;
      return Stack(
        children: [
          if (style.hasData)
            Semantics(
              label: widget.onTap == null ? null : l10n.a11yMap,
              child: ml.MapLibreMap(
                styleString: style.data!,
                initialCameraPosition: ml.CameraPosition(
                  target: center.toMapLibre,
                  zoom: PindoroCamera.zoom,
                ),
                onMapCreated: (c) => _controller = c..addListener(_cameraMoved),
                trackCameraPosition: widget.onCamera != null,
                onStyleLoadedCallback: () => runMapWork(_addOverlays),
                onMapClick: (_, at) => widget.onTap?.call(at.toCore),
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                compassEnabled: false,
                // Our own chip carries the attribution text.
                attributionButtonMargins: const Point(-100, -100),
              ),
            ),
          if (widget.showControls)
            Positioned(
              right: PindoroSpace.s4,
              bottom: widget.bottomInset + PindoroSpace.s4,
              child: Column(
                spacing: PindoroSpace.s2,
                children: [
                  MapControl(
                    glyph: PindoroGlyph.locate,
                    semanticLabel: l10n.a11yGoToMyLocation,
                    onPressed: _goToMyLocation,
                  ),
                  MapControl(
                    glyph: PindoroGlyph.compass,
                    semanticLabel: l10n.a11yRecentre,
                    onPressed: _fitArea,
                  ),
                  MapZoomControls(
                    onCamera: (update) => _controller?.animateCamera(update),
                  ),
                ],
              ),
            ),
          Positioned(
            left: PindoroSpace.s4,
            bottom: widget.bottomInset + PindoroSpace.s2,
            child: const MapAttribution(),
          ),
        ],
      );
    },
  );
}
