import 'dart:async';
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

import '../../app/config.dart';
import '../../app/format.dart';
import '../../app/location.dart';
import '../../app/toast.dart';

/// GeoJSON source ids.
abstract final class MapSources {
  static const String areaMask = 'area-mask';
  static const String youPin = 'you-pin';
  static const String truthStreet = 'truth-street';
  static const String measure = 'measure';
  static const String measureEnd = 'measure-end';
}

const String _pinImage = 'player-pin';

/// Builds the game map; widget tests override it so no platform view is made.
final pindoroMapBuilderProvider = Provider<Widget Function(PindoroMap map)>(
  (ref) =>
      (map) => map,
);

/// Unlabelled self-hosted basemap: the round's area (outside dimmed) plus the
/// pin, truth street and measure line passed in by the caller. [bottomInset]
/// is the height of whatever covers the bottom of the map (button, sheet):
/// controls and attribution sit above it and the camera frames above it.
class PindoroMap extends StatefulWidget {
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
  });

  final AreaShape area;
  final LatLng? pin;
  final MultiPolyline? truth;
  final (LatLng from, LatLng to)? measure;
  final ValueChanged<LatLng>? onTap;
  final double bottomInset;

  /// Height covered at the top (top bar and plate), for framing.
  final double topInset;
  final bool showControls;

  @override
  State<PindoroMap> createState() => _PindoroMapState();
}

class _PindoroMapState extends State<PindoroMap> {
  ml.MapLibreMapController? _controller;
  Brightness? _brightness;
  Future<String>? _style;
  bool _overlaysReady = false;

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

  @override
  void didUpdateWidget(PindoroMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_overlaysReady) return;
    unawaited(_syncOverlays());
    if (widget.truth != null && widget.truth != oldWidget.truth) {
      unawaited(_fit([...widget.truth!.expand((l) => l), ?widget.pin]));
    } else if (widget.truth == null && oldWidget.truth != null) {
      unawaited(_fitArea());
    }
  }

  Future<void> _fitArea() {
    final b = widget.area.bbox;
    return _fit([LatLng(b.minLat, b.minLon), LatLng(b.maxLat, b.maxLon)]);
  }

  Future<void> _fit(List<LatLng> points) async {
    final b = Bbox.of(points);
    await _controller?.animateCamera(
      ml.CameraUpdate.newLatLngBounds(
        ml.LatLngBounds(
          southwest: ml.LatLng(b.minLat, b.minLon),
          northeast: ml.LatLng(b.maxLat, b.maxLon),
        ),
        left: PindoroCamera.fitPaddingX,
        top: widget.topInset + PindoroSpace.s6,
        right: PindoroCamera.fitPaddingX,
        bottom: widget.bottomInset + PindoroSpace.s6,
      ),
    );
  }

  Future<void> _addOverlays() async {
    final c = _controller;
    if (c == null) return;
    final colors = PindoroTheme.of(context).colors;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
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
      MapSources.areaMask,
      areaMaskGeoJson(widget.area.boundary),
    );
    await c.addFillLayer(
      MapSources.areaMask,
      '${MapSources.areaMask}-fill',
      ml.FillLayerProperties(
        fillColor: _hex(colors.mapMask),
        fillOpacity: PindoroOpacity.mask,
      ),
      enableInteraction: false,
    );
    await c.addGeoJsonSource(MapSources.truthStreet, _lines(const []));
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
        MapSources.truthStreet,
        '${MapSources.truthStreet}-$id',
        ml.LineLayerProperties(
          lineColor: _hex(color),
          lineWidth: width,
          lineCap: 'round',
          lineJoin: 'round',
        ),
        enableInteraction: false,
      );
    }
    await c.addGeoJsonSource(MapSources.measure, _lines(const []));
    await c.addLineLayer(
      MapSources.measure,
      '${MapSources.measure}-line',
      ml.LineLayerProperties(
        lineColor: _hex(colors.mapMeasureLine),
        lineWidth: PindoroStroke.thick,
        lineCap: 'round',
        // Dots: zero-length dashes with round caps; dash units are line widths.
        lineDasharray: [0, PindoroSize.mapMeasureGap / PindoroStroke.thick],
      ),
      enableInteraction: false,
    );
    await c.addGeoJsonSource(MapSources.measureEnd, _points(const []));
    await c.addCircleLayer(
      MapSources.measureEnd,
      '${MapSources.measureEnd}-ring',
      ml.CircleLayerProperties(
        circleColor: _hex(colors.mapPlayerHalo),
        circleRadius: PindoroStroke.thick + PindoroStroke.base,
        circleStrokeColor: _hex(colors.mapMeasureLine),
        circleStrokeWidth: PindoroStroke.base,
      ),
      enableInteraction: false,
    );
    await c.addGeoJsonSource(MapSources.youPin, _points(const []));
    await c.addSymbolLayer(
      MapSources.youPin,
      '${MapSources.youPin}-pin',
      ml.SymbolLayerProperties(
        iconImage: _pinImage,
        iconAnchor: 'bottom',
        iconOffset: [0, PinMark.tipInset * pixelRatio],
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      enableInteraction: false,
    );
    _overlaysReady = true;
    await _syncOverlays();
    await (widget.truth == null
        ? _fitArea()
        : _fit([...widget.truth!.expand((l) => l), ?widget.pin]));
  }

  Future<void> _syncOverlays() async {
    final c = _controller!;
    final pin = widget.pin;
    final measure = widget.measure;
    await c.setGeoJsonSource(MapSources.youPin, _points([?pin]));
    await c.setGeoJsonSource(
      MapSources.truthStreet,
      _lines(widget.truth ?? []),
    );
    await c.setGeoJsonSource(
      MapSources.measure,
      _lines([
        if (measure != null) [measure.$1, measure.$2],
      ]),
    );
    await c.setGeoJsonSource(MapSources.measureEnd, _points([?measure?.$2]));
  }

  Future<void> _goToMyLocation() async {
    final result = await ProviderScope.containerOf(
      context,
    ).read(locationServiceProvider).locate();
    if (!mounted) return;
    switch (result) {
      case Located(:final position):
        await _controller?.animateCamera(
          ml.CameraUpdate.newLatLng(ml.LatLng(position.lat, position.lon)),
        );
      case LocationDenied():
        showToast(context, context.l10n.cityLocationDenied);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _style,
    builder: (context, style) {
      final l10n = context.l10n;
      final center = widget.area.bbox.center;
      return Stack(
        children: [
          if (style.hasData)
            ml.MapLibreMap(
              styleString: style.data!,
              initialCameraPosition: ml.CameraPosition(
                target: ml.LatLng(center.lat, center.lon),
                zoom: PindoroCamera.zoom,
              ),
              onMapCreated: (c) => _controller = c,
              onStyleLoadedCallback: _addOverlays,
              onMapClick: (_, at) =>
                  widget.onTap?.call(LatLng(at.latitude, at.longitude)),
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              compassEnabled: false,
              // Our own chip carries the attribution text.
              attributionButtonMargins: const Point(-100, -100),
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
                  MapControl(
                    glyph: PindoroGlyph.zoomIn,
                    semanticLabel: l10n.a11yZoomIn,
                    onPressed: () =>
                        _controller?.animateCamera(ml.CameraUpdate.zoomIn()),
                  ),
                  MapControl(
                    glyph: PindoroGlyph.zoomOut,
                    semanticLabel: l10n.a11yZoomOut,
                    onPressed: () =>
                        _controller?.animateCamera(ml.CameraUpdate.zoomOut()),
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

/// Bundled style with the tile server injected (Martin source `georgia`).
Future<String> loadMapStyle(Brightness brightness) async {
  final json = await rootBundle.loadString(
    'assets/map_styles/pindoro_${brightness.name}.json',
  );
  return json.replaceAll('{TILES_BASE_URL}', AppConfig.tilesBaseUrl);
}

/// "© OpenStreetMap contributors, Protomaps" on every map: `label.sm` on a
/// raised chip. Not interactive; the full credits are in Settings.
class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = PindoroTheme.of(context).colors;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width - 2 * PindoroSpace.s4,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.mapAttributionBg,
          borderRadius: BorderRadius.circular(PindoroRadius.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PindoroSpace.s2,
            vertical: 2,
          ),
          child: Text(
            context.l10n.commonAttribution,
            style: PindoroType.labelSm.copyWith(
              color: colors.mapAttributionText,
            ),
          ),
        ),
      ),
    );
  }
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

List<double> _coord(LatLng p) => [p.lon, p.lat];

Map<String, dynamic> _collection(List<Map<String, dynamic>> geometries) => {
  'type': 'FeatureCollection',
  'features': [
    for (final g in geometries)
      {'type': 'Feature', 'properties': <String, dynamic>{}, 'geometry': g},
  ],
};

Map<String, dynamic> _points(List<LatLng> points) => _collection([
  for (final p in points) {'type': 'Point', 'coordinates': _coord(p)},
]);

Map<String, dynamic> _lines(MultiPolyline lines) => _collection([
  if (lines.isNotEmpty)
    {
      'type': 'MultiLineString',
      'coordinates': [
        for (final line in lines) [for (final p in line) _coord(p)],
      ],
    },
]);

/// The world with every area polygon cut out; filled, it dims all but the area.
Map<String, dynamic> areaMaskGeoJson(List<List<Polyline>> boundary) =>
    _collection([
      {
        'type': 'Polygon',
        'coordinates': [
          const [
            [-180.0, -85.0],
            [180.0, -85.0],
            [180.0, 85.0],
            [-180.0, 85.0],
            [-180.0, -85.0],
          ],
          for (final polygon in boundary)
            [for (final p in polygon.first) _coord(p)],
        ],
      },
    ]);
