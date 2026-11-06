import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

import '../map/pindoro_map.dart';

/// The area picker's map: district outlines, picked ones in "you" cobalt.
/// Reports taps and the camera (centre + zoom) so shapes can be drawn over it.
class AreaPickerMap extends StatefulWidget {
  const AreaPickerMap({
    super.key,
    required this.districts,
    required this.picked,
    required this.initialBounds,
    required this.onTap,
    required this.onCamera,
    this.focus,
    this.showDistricts = true,
  });

  final List<District> districts;
  final Set<String> picked;
  final Bbox initialBounds;
  final ValueChanged<LatLng> onTap;
  final void Function(LatLng center, double zoom) onCamera;

  /// Moves the camera to these bounds when it changes.
  final Bbox? focus;

  /// District outlines show only while picking districts.
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

const String _allSource = 'districts-all';
const String _pickedSource = 'districts-picked';

class _AreaPickerMapState extends State<AreaPickerMap> {
  ml.MapLibreMapController? _controller;
  Future<String>? _style;
  Brightness? _brightness;
  bool _ready = false;

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
      unawaited(
        _controller?.setLayerVisibility(
          '$_allSource-outline',
          widget.showDistricts,
        ),
      );
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

  Future<void> _addLayers() async {
    final c = _controller;
    if (c == null) return;
    final colors = PindoroTheme.of(context).colors;
    await c.addGeoJsonSource(_allSource, _polygons(widget.districts));
    await c.addLineLayer(
      _allSource,
      '$_allSource-outline',
      ml.LineLayerProperties(
        lineColor: _hex(colors.mapRegionOutline),
        lineWidth: PindoroStroke.base,
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );
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
    _ready = true;
    await _syncPicked();
    await c.setLayerVisibility('$_allSource-outline', widget.showDistricts);
    await _moveTo(widget.focus ?? widget.initialBounds);
  }

  Future<void> _syncPicked() => _controller!.setGeoJsonSource(
    _pickedSource,
    _polygons([
      for (final d in widget.districts)
        if (widget.picked.contains(d.id)) d,
    ]),
  );

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
          'properties': {'id': d.id},
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
