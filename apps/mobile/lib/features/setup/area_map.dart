import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

import '../../app/format.dart';
import '../map/pindoro_map.dart';

/// Districts show below [PindoroCamera.areaDetailZoom], neighbourhoods from
/// it on.
DistrictKind levelAt(double zoom) => zoom < PindoroCamera.areaDetailZoom
    ? DistrictKind.district
    : DistrictKind.neighbourhood;

/// The area a tap at [at] picks: the smallest one of the zoom's level that
/// contains it, else the smallest of any level.
District? areaAt(List<District> areas, LatLng at, double zoom) {
  final hits = [
    for (final d in areas)
      if (d.boundary.any((p) => polygonContains(p, at))) d,
  ]..sort((a, b) => a.areaM2.compareTo(b.areaM2));
  final level = levelAt(zoom);
  return hits.where((d) => d.kind == level).firstOrNull ?? hits.firstOrNull;
}

/// The area picker's map: outlines and name chips of the zoom's level (see
/// [levelAt]), picked areas in "you" cobalt at every zoom. Reports taps and
/// the camera (centre + zoom) so shapes can be drawn over it.
class AreaPickerMap extends StatefulWidget {
  const AreaPickerMap({
    super.key,
    required this.districts,
    required this.names,
    required this.picked,
    required this.initialBounds,
    required this.onTap,
    required this.onCamera,
    this.focus,
    this.showDistricts = true,
  });

  final List<District> districts;

  /// Each area's display name, by id.
  final Map<String, String> names;
  final Set<String> picked;
  final Bbox initialBounds;
  final ValueChanged<LatLng> onTap;
  final void Function(LatLng center, double zoom) onCamera;

  /// Moves the camera to these bounds when it changes.
  final Bbox? focus;

  /// Outlines and name chips show only while picking areas.
  final bool showDistricts;

  @override
  State<AreaPickerMap> createState() => _AreaPickerMapState();
}

/// Overridden in widget tests (no platform view).
final areaPickerMapBuilderProvider =
    Provider<Widget Function(AreaPickerMap map)>(
      (ref) =>
          (map) => map,
    );

const String _allSource = 'areas-all';
const String _pickedSource = 'areas-picked';
const String _labelSource = 'areas-labels';

/// Layers shown only while picking areas, with the level each one draws.
const List<(String layer, DistrictKind level)> _levelLayers = [
  ('$_allSource-district', DistrictKind.district),
  ('$_allSource-neighbourhood', DistrictKind.neighbourhood),
  ('$_labelSource-district', DistrictKind.district),
  ('$_labelSource-neighbourhood', DistrictKind.neighbourhood),
];

class _AreaPickerMapState extends State<AreaPickerMap> {
  ml.MapLibreMapController? _controller;
  Future<String>? _style;
  Brightness? _brightness;
  bool _ready = false;
  final Set<String> _pickedImages = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (brightness != _brightness) {
      _brightness = brightness;
      _ready = false;
      _style = loadMapStyle(brightness);
    }
  }

  @override
  void didUpdateWidget(AreaPickerMap old) {
    super.didUpdateWidget(old);
    if (!_ready) return;
    if (old.picked != widget.picked) unawaited(_syncPicked());
    if (old.showDistricts != widget.showDistricts) {
      unawaited(_syncVisibility());
    }
    final focus = widget.focus;
    if (focus != null && focus != old.focus) unawaited(_moveTo(focus));
  }

  Future<void> _moveTo(Bbox b) async {
    await _controller?.animateCamera(
      ml.CameraUpdate.newLatLngBounds(
        ml.LatLngBounds(
          southwest: ml.LatLng(b.minLat, b.minLon),
          northeast: ml.LatLng(b.maxLat, b.maxLon),
        ),
        left: PindoroSpace.s8,
        top: PindoroSpace.s16,
        right: PindoroSpace.s8,
        bottom: PindoroSpace.s8,
      ),
    );
  }

  String _image(String id, {required bool picked}) =>
      picked ? 'area:$id:picked' : 'area:$id';

  Future<void> _addImages(Iterable<District> areas, {required bool picked}) {
    final c = _controller!;
    final colors = PindoroTheme.of(context).colors;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return Future.wait([
      for (final d in areas)
        () async {
          final name = widget.names[d.id] ?? d.nameKa;
          final chip = picked
              ? MapChip.picked(name, colors)
              : MapChip.region(name, colors);
          await c.addImage(
            _image(d.id, picked: picked),
            await chip.toPng(pixelRatio),
          );
        }(),
    ]);
  }

  Future<void> _addLayers() async {
    final c = _controller;
    if (c == null) return;
    final colors = PindoroTheme.of(context).colors;
    _pickedImages.clear();
    await _addImages(widget.districts, picked: false);
    await c.addGeoJsonSource(_allSource, _polygons(widget.districts));
    for (final (layer, level) in _levelLayers.take(2)) {
      await c.addLineLayer(
        _allSource,
        layer,
        ml.LineLayerProperties(
          lineColor: _hex(colors.mapRegionOutline),
          lineWidth: PindoroStroke.base,
          lineJoin: 'round',
        ),
        filter: ['==', 'kind', level.name],
        minzoom: _minZoom(level),
        maxzoom: _maxZoom(level),
        enableInteraction: false,
      );
    }
    await c.addGeoJsonSource(_pickedSource, _polygons(const []));
    await c.addFillLayer(
      _pickedSource,
      '$_pickedSource-fill',
      ml.FillLayerProperties(
        fillColor: _hex(colors.mapAreaStroke),
        fillOpacity: PindoroOpacity.area,
      ),
      enableInteraction: false,
    );
    await c.addLineLayer(
      _pickedSource,
      '$_pickedSource-outline',
      ml.LineLayerProperties(
        lineColor: _hex(colors.mapAreaStroke),
        lineWidth: PindoroStroke.thick,
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );
    await c.addGeoJsonSource(_labelSource, _labels());
    for (final (layer, level) in _levelLayers.skip(2)) {
      await c.addSymbolLayer(
        _labelSource,
        layer,
        const ml.SymbolLayerProperties(
          iconImage: ['get', 'icon'],
          symbolSortKey: ['get', 'sort'],
        ),
        // Picked areas keep their chip at every zoom.
        filter: [
          'any',
          ['==', 'kind', level.name],
          ['==', 'picked', true],
        ],
        minzoom: _minZoom(level),
        maxzoom: _maxZoom(level),
        enableInteraction: false,
      );
    }
    _ready = true;
    await _syncPicked();
    await _syncVisibility();
    await _moveTo(widget.focus ?? widget.initialBounds);
  }

  static double? _minZoom(DistrictKind level) =>
      level == DistrictKind.neighbourhood ? PindoroCamera.areaDetailZoom : null;

  static double? _maxZoom(DistrictKind level) =>
      level == DistrictKind.district ? PindoroCamera.areaDetailZoom : null;

  Future<void> _syncPicked() async {
    final c = _controller!;
    final picked = [
      for (final d in widget.districts)
        if (widget.picked.contains(d.id)) d,
    ];
    final missing = [
      for (final d in picked)
        if (_pickedImages.add(d.id)) d,
    ];
    await _addImages(missing, picked: true);
    await c.setGeoJsonSource(_pickedSource, _polygons(picked));
    await c.setGeoJsonSource(_labelSource, _labels());
  }

  Future<void> _syncVisibility() async {
    for (final (layer, _) in _levelLayers) {
      await _controller?.setLayerVisibility(layer, widget.showDistricts);
    }
  }

  /// One point per area at its centre; bigger areas win label collisions,
  /// picked ones beat all.
  Map<String, dynamic> _labels() => {
    'type': 'FeatureCollection',
    'features': [
      for (final d in widget.districts)
        {
          'type': 'Feature',
          'properties': {
            'kind': d.kind.name,
            'picked': widget.picked.contains(d.id),
            'icon': _image(d.id, picked: widget.picked.contains(d.id)),
            'sort': widget.picked.contains(d.id) ? -1e12 : -d.areaM2,
          },
          'geometry': {
            'type': 'Point',
            'coordinates': [d.center.lon, d.center.lat],
          },
        },
    ],
  };

  void _reportCamera() {
    final position = _controller?.cameraPosition;
    if (position == null) return;
    widget.onCamera(
      LatLng(position.target.latitude, position.target.longitude),
      position.zoom,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _style,
    builder: (context, style) {
      final center = widget.initialBounds.center;
      return Stack(
        children: [
          if (style.hasData)
            ml.MapLibreMap(
              styleString: style.data!,
              initialCameraPosition: ml.CameraPosition(
                target: ml.LatLng(center.lat, center.lon),
                zoom: PindoroCamera.zoom,
              ),
              trackCameraPosition: true,
              onMapCreated: (c) {
                _controller = c..addListener(_reportCamera);
              },
              onStyleLoadedCallback: _addLayers,
              onMapClick: (_, at) =>
                  widget.onTap(LatLng(at.latitude, at.longitude)),
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              compassEnabled: false,
              attributionButtonMargins: const math.Point(-100, -100),
            ),
          const Positioned(
            left: PindoroSpace.s4,
            bottom: PindoroSpace.s2,
            child: MapAttribution(),
          ),
          Positioned(
            right: PindoroSpace.s4,
            bottom: PindoroSpace.s4,
            child: Column(
              spacing: PindoroSpace.s2,
              children: [
                MapControl(
                  glyph: PindoroGlyph.zoomIn,
                  semanticLabel: context.l10n.a11yZoomIn,
                  onPressed: () =>
                      _controller?.animateCamera(ml.CameraUpdate.zoomIn()),
                ),
                MapControl(
                  glyph: PindoroGlyph.zoomOut,
                  semanticLabel: context.l10n.a11yZoomOut,
                  onPressed: () =>
                      _controller?.animateCamera(ml.CameraUpdate.zoomOut()),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  @override
  void dispose() {
    _controller?.removeListener(_reportCamera);
    super.dispose();
  }
}

/// Metres per logical pixel at [zoom] (512 px tiles) and latitude [lat].
double metresPerPixel(double zoom, double lat) =>
    40075016.686 * math.cos(lat * math.pi / 180) / (512 * math.pow(2, zoom));

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

Map<String, dynamic> _polygons(List<District> districts) => {
  'type': 'FeatureCollection',
  'features': [
    for (final d in districts)
      for (final polygon in d.boundary)
        {
          'type': 'Feature',
          'properties': {'id': d.id, 'kind': d.kind.name},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              for (final ring in polygon)
                [
                  for (final p in ring) [p.lon, p.lat],
                ],
            ],
          },
        },
  ],
};
