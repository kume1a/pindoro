import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:pindoro/core/format.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/ui/widgets/map_attribution.dart';
import 'package:pindoro/features/setup/ui/outline_labels.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Districts show below [PindoroCamera.areaDetailZoom]; from it on, the
/// smaller areas inside them (quarters and neighbourhoods).
bool detailAt(double zoom) => zoom >= PindoroCamera.areaDetailZoom;

bool isDetail(District d) => d.kind != DistrictKind.district;

/// The area a tap at [at] picks: the smallest one of the zoom's level that
/// contains it, else the smallest of any level.
District? areaAt(List<District> areas, LatLng at, double zoom) {
  final hits = [
    for (final d in areas)
      if (d.boundary.any((p) => polygonContains(p, at))) d,
  ]..sort((a, b) => a.areaM2.compareTo(b.areaM2));
  final detail = detailAt(zoom);
  return hits.where((d) => isDetail(d) == detail).firstOrNull ??
      hits.firstOrNull;
}

/// The area picker's map: outlines and name chips of the zoom's level (see
/// [detailAt]), picked areas in "you" cobalt at every zoom. Reports taps and
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
    this.lastTapped,
    this.focus,
    this.showDistricts = true,
  });

  final List<District> districts;

  /// Each area's display name, by id.
  final Map<String, String> names;
  final Set<String> picked;

  /// The area the player touched last: its chip wins collisions after the
  /// picked ones.
  final String? lastTapped;
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

const String _districtOutlines = '$_allSource-district';
const String _quarterOutlines = '$_allSource-quarter';
const String _districtLabels = '$_labelSource-district';
const String _outlineLabels = 'areas-outline-names';
const String _detailLabels = '$_labelSource-detail';
const String _pickedLabels = '$_labelSource-picked';

/// Layers shown only while picking areas.
const List<String> _pickingLayers = [
  _districtOutlines,
  _quarterOutlines,
  _districtLabels,
  _detailLabels,
  _pickedLabels,
  _outlineLabels,
];

/// Outline widths from v1-screens.md (Area picker): districts thinner while
/// they are the level being picked, quarters thinnest.
const double _districtFarOutline = 1.5;
const double _quarterOutline = 1;

const List<Object> _isDistrict = [
  '==',
  ['get', 'kind'],
  'district',
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
    if (old.picked != widget.picked || old.lastTapped != widget.lastTapped) {
      unawaited(_syncPicked());
    }
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

  /// Zoomed in, district names run along their outlines, on the district's
  /// side, so the player still knows which district a quarter is in.
  Future<void> _addOutlineLabels() async {
    final c = _controller!;
    final colors = PindoroTheme.of(context).colors;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final districts = widget.districts.where((d) => !isDetail(d)).toList();
    await Future.wait([
      for (final d in districts)
        () async {
          await c.addImage(
            'outline:${d.id}',
            await outlineLabelPng(
              widget.names[d.id] ?? d.nameKa,
              colors,
              pixelRatio,
            ),
          );
        }(),
    ]);
    await c.addGeoJsonSource(_outlineLabels, {
      'type': 'FeatureCollection',
      'features': [
        for (final d in districts)
          for (final spot in outlineSpots(d.boundary))
            {
              'type': 'Feature',
              'properties': {
                'icon': 'outline:${d.id}',
                'rotate': spot.rotate,
                'below': spot.insideBelow,
              },
              'geometry': {
                'type': 'Point',
                'coordinates': [spot.at.lon, spot.at.lat],
              },
            },
      ],
    });
    await c.addSymbolLayer(
      _outlineLabels,
      _outlineLabels,
      const ml.SymbolLayerProperties(
        iconImage: ['get', 'icon'],
        iconRotate: ['get', 'rotate'],
        iconRotationAlignment: 'map',
        iconOffset: [
          'case',
          ['get', 'below'],
          [
            'literal',
            [0, PindoroSpace.s3],
          ],
          [
            'literal',
            [0, -PindoroSpace.s3],
          ],
        ],
      ),
      minzoom: PindoroCamera.areaDetailZoom,
      enableInteraction: false,
    );
  }

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
    // Districts frame the map at every zoom. Neighbourhoods overlap the
    // quarters, so only a picked one gets an outline (the picked layer).
    await c.addLineLayer(
      _allSource,
      _districtOutlines,
      ml.LineLayerProperties(
        lineColor: _hex(colors.mapRegionOutline),
        lineWidth: [
          'step',
          ['zoom'],
          _districtFarOutline,
          PindoroCamera.areaDetailZoom,
          PindoroStroke.base,
        ],
        lineJoin: 'round',
      ),
      filter: _isDistrict,
      enableInteraction: false,
    );
    await c.addLineLayer(
      _allSource,
      _quarterOutlines,
      ml.LineLayerProperties(
        lineColor: _hex(colors.mapRegionOutline),
        lineWidth: _quarterOutline,
        lineJoin: 'round',
      ),
      filter: [
        '==',
        ['get', 'kind'],
        DistrictKind.quarter.name,
      ],
      minzoom: PindoroCamera.areaDetailZoom,
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
    // Below the chips, so they make way for them.
    await _addOutlineLabels();
    await c.addGeoJsonSource(_labelSource, _labels());
    const unpicked = [
      '!',
      ['get', 'picked'],
    ];
    for (final (layer, filter, minzoom, maxzoom) in [
      (_districtLabels, _isDistrict, null, PindoroCamera.areaDetailZoom),
      (_detailLabels, ['!', _isDistrict], PindoroCamera.areaDetailZoom, null),
    ]) {
      await c.addSymbolLayer(
        _labelSource,
        layer,
        const ml.SymbolLayerProperties(
          iconImage: ['get', 'icon'],
          symbolSortKey: ['get', 'sort'],
        ),
        filter: ['all', filter, unpicked],
        minzoom: minzoom,
        maxzoom: maxzoom,
        enableInteraction: false,
      );
    }
    // Added last, so placed first: picked chips show at every zoom and the
    // others make way for them.
    await c.addSymbolLayer(
      _labelSource,
      _pickedLabels,
      const ml.SymbolLayerProperties(
        iconImage: ['get', 'icon'],
        iconAllowOverlap: true,
      ),
      filter: ['get', 'picked'],
      enableInteraction: false,
    );
    _ready = true;
    await _syncPicked();
    await _syncVisibility();
    await _moveTo(widget.focus ?? widget.initialBounds);
  }

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
    for (final layer in _pickingLayers) {
      await _controller?.setLayerVisibility(layer, widget.showDistricts);
    }
  }

  /// One point per area at its centre. Among unpicked chips the one touched
  /// last wins collisions, then the bigger area.
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
            'sort': d.id == widget.lastTapped ? -1e12 : -d.areaM2,
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
