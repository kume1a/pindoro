import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

import '../../app/config.dart';

/// GeoJSON source ids (`area-mask` is reserved for area selection).
abstract final class MapSources {
  static const String youPin = 'you-pin';
  static const String truthStreet = 'truth-street';
  static const String measure = 'measure';
}

const String osmAttribution = '© OpenStreetMap contributors, Protomaps';

/// Unlabelled self-hosted basemap with the three game overlays. Stateless
/// about the game: callers pass the pin, truth street and measure line.
class PindoroMap extends StatefulWidget {
  const PindoroMap({
    super.key,
    required this.initialCenter,
    this.pin,
    this.truth,
    this.measure,
    this.onTap,
  });

  final LatLng initialCenter;
  final LatLng? pin;
  final MultiPolyline? truth;
  final (LatLng from, LatLng to)? measure;
  final ValueChanged<LatLng>? onTap;

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
    if (_overlaysReady) _syncOverlays();
  }

  Future<void> _addOverlays() async {
    final c = _controller;
    if (c == null) return;
    final theme = PindoroTheme.of(context);
    await c.addGeoJsonSource(MapSources.truthStreet, _lines(const []));
    await c.addLineLayer(
      MapSources.truthStreet,
      '${MapSources.truthStreet}-line',
      ml.LineLayerProperties(
        lineColor: _hex(theme.mapTruth),
        lineWidth: PindoroTokens.sizeMapTruthLineWidth,
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );
    await c.addGeoJsonSource(MapSources.measure, _lines(const []));
    await c.addLineLayer(
      MapSources.measure,
      '${MapSources.measure}-line',
      ml.LineLayerProperties(
        lineColor: _hex(theme.mapMeasure),
        lineWidth: PindoroTokens.sizeMapMeasureLineWidth,
        lineDasharray: [
          PindoroTokens.sizeMapMeasureDash,
          PindoroTokens.sizeMapMeasureGap,
        ],
      ),
    );
    await c.addGeoJsonSource(MapSources.youPin, _points(const []));
    await c.addCircleLayer(
      MapSources.youPin,
      '${MapSources.youPin}-dot',
      ml.CircleLayerProperties(
        circleColor: _hex(theme.mapYou),
        circleRadius: PindoroTokens.sizeMapPin / 2,
      ),
    );
    _overlaysReady = true;
    await _syncOverlays();
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
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _style,
    builder: (context, style) {
      if (!style.hasData) return const SizedBox.expand();
      final center = widget.initialCenter;
      return Stack(
        children: [
          ml.MapLibreMap(
            styleString: style.data!,
            initialCameraPosition: ml.CameraPosition(
              target: ml.LatLng(center.lat, center.lon),
              zoom: PindoroTokens.mapCameraZoom,
            ),
            onMapCreated: (c) => _controller = c,
            onStyleLoadedCallback: _addOverlays,
            onMapClick: (_, at) =>
                widget.onTap?.call(LatLng(at.latitude, at.longitude)),
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            compassEnabled: false,
          ),
          const Positioned(
            left: PindoroTokens.spaceSm,
            bottom: PindoroTokens.spaceSm,
            child: _Attribution(),
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

class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    final theme = PindoroTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(PindoroTokens.radiusSm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PindoroTokens.spaceSm,
          vertical: PindoroTokens.spaceXs,
        ),
        child: Text(
          osmAttribution,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: theme.muted),
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
