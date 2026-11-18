import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:pindoro/features/map/data/area_levels.dart';
import 'package:pindoro/features/map/data/geojson.dart';
import 'package:pindoro/features/map/data/maplibre_convert.dart';
import 'package:pindoro/features/map/ui/map_host.dart';
import 'package:pindoro/features/map/ui/map_work.dart';
import 'package:pindoro/features/map/ui/outline_labels.dart';
import 'package:pindoro/features/map/ui/poi_icons.dart';
import 'package:pindoro/features/map/ui/route_projection.dart';
import 'package:pindoro/features/map/ui/widgets/map_attribution.dart';
import 'package:pindoro/features/map/ui/widgets/map_taps.dart';
import 'package:pindoro/features/map/ui/widgets/map_zoom_controls.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The area picker's map: outlines and name chips of the zoom's level (see
/// [detailAt]), picked areas in "you" cobalt at every zoom. Reports taps and
/// the camera (centre + zoom) so shapes can be drawn over it. [bottomInset]
/// is the height the sheet covers: controls sit above it and the camera
/// frames and centres above it, so the map never resizes with the sheet.
class AreaPickerMap extends StatefulWidget {
  const AreaPickerMap({
    super.key,
    required this.districts,
    required this.names,
    required this.picked,
    required this.initialBounds,
    required this.onTap,
    required this.onCamera,
    this.onCameraIdle,
    this.lastTapped,
    this.focus,
    this.showDistricts = true,
    this.bottomInset = 0,
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

  /// Every camera move: the centre of the part the sheet leaves uncovered,
  /// and the zoom.
  final void Function(LatLng center, double zoom) onCamera;

  /// The camera stopped moving.
  final VoidCallback? onCameraIdle;

  /// Moves the camera to these bounds when it changes.
  final Bbox? focus;

  /// Outlines and name chips show only while picking areas.
  final bool showDistricts;
  final double bottomInset;

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

class _AreaPickerMapState extends State<AreaPickerMap>
    with MapHost<AreaPickerMap> {
  bool _ready = false;
  bool _startReported = false;
  final Set<String> _pickedImages = {};

  @override
  void styleChanged() => _ready = false;

  @override
  void didUpdateWidget(AreaPickerMap old) {
    super.didUpdateWidget(old);
    if (old.bottomInset != widget.bottomInset) {
      // The uncovered part's centre moved under a still camera.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reportCamera();
      });
    }
    final focus = widget.focus;
    if (focus != null && focus != old.focus) runMapWork(() => _moveTo(focus));
    if (!_ready) return;
    if (old.picked != widget.picked || old.lastTapped != widget.lastTapped) {
      runMapWork(_syncPicked);
    }
    if (old.showDistricts != widget.showDistricts) {
      runMapWork(_syncVisibility);
    }
  }

  /// The camera that frames [b] above the sheet. Computed here rather than
  /// with a bounds update, whose padding stays on the camera and moves its
  /// target off the view's centre, where [MapProjection] expects it. Equal
  /// top and bottom padding centre [b] where the shapes and [_reportCamera]
  /// put the uncovered part's centre.
  ({LatLng target, double zoom}) _fit(Bbox b, Size size) => MapProjection.fit(
    [LatLng(b.minLat, b.minLon), LatLng(b.maxLat, b.maxLon)],
    size: size,
    padding: EdgeInsets.fromLTRB(
      PindoroSpace.s8,
      PindoroSpace.s16,
      PindoroSpace.s8,
      widget.bottomInset + PindoroSpace.s16,
    ),
  );

  Future<void> _moveTo(Bbox b) async {
    final size = mapSize;
    if (size == null) return;
    final camera = _fit(b, size);
    await mapController?.animateCamera(
      ml.CameraUpdate.newLatLngZoom(camera.target.toMapLibre, camera.zoom),
    );
  }

  String _image(String id, {required bool picked}) =>
      picked ? 'area:$id:picked' : 'area:$id';

  /// Zoomed in, district names run along their outlines, on the district's
  /// side, so the player still knows which district a quarter is in.
  Future<void> _addOutlineLabels() async {
    final c = mapController!;
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
    await c.addGeoJsonSource(
      _outlineLabels,
      labelledPointsGeoJson([
        for (final d in districts)
          for (final spot in outlineSpots(d.boundary))
            (
              spot.at,
              {
                'icon': 'outline:${d.id}',
                'rotate': spot.rotate,
                'below': spot.insideBelow,
              },
            ),
      ]),
    );
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
    final c = mapController!;
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
    final c = mapController;
    if (c == null) return;
    final colors = PindoroTheme.of(context).colors;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    _pickedImages.clear();
    await _addImages(widget.districts, picked: false);
    await c.addGeoJsonSource(_allSource, _polygons(widget.districts));
    // Districts frame the map at every zoom. Neighbourhoods overlap the
    // quarters, so only a picked one gets an outline (the picked layer).
    await c.addLineLayer(
      _allSource,
      _districtOutlines,
      ml.LineLayerProperties(
        lineColor: hexColor(colors.mapRegionOutline),
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
        lineColor: hexColor(colors.mapRegionOutline),
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
        fillColor: hexColor(colors.mapAreaStroke),
        fillOpacity: PindoroOpacity.area,
      ),
      enableInteraction: false,
    );
    await c.addLineLayer(
      _pickedSource,
      '$_pickedSource-outline',
      ml.LineLayerProperties(
        lineColor: hexColor(colors.mapAreaStroke),
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
    await addPoiImages(c, colors, pixelRatio);
  }

  Future<void> _syncPicked() async {
    final c = mapController!;
    await _addImages([
      for (final d in widget.districts)
        if (widget.picked.contains(d.id) && _pickedImages.add(d.id)) d,
    ], picked: true);
    // Read after the await: a later toggle may have synced meanwhile, and
    // the last write must be the current pick.
    final picked = [
      for (final d in widget.districts)
        if (widget.picked.contains(d.id)) d,
    ];
    await c.setGeoJsonSource(_pickedSource, _polygons(picked));
    await c.setGeoJsonSource(_labelSource, _labels());
  }

  Future<void> _syncVisibility() async {
    for (final layer in _pickingLayers) {
      await mapController?.setLayerVisibility(layer, widget.showDistricts);
    }
  }

  /// One point per area at its centre. Among unpicked chips the one touched
  /// last wins collisions, then the bigger area.
  Map<String, dynamic> _labels() => labelledPointsGeoJson([
    for (final d in widget.districts)
      (
        d.center,
        {
          'kind': d.kind.name,
          'picked': widget.picked.contains(d.id),
          'icon': _image(d.id, picked: widget.picked.contains(d.id)),
          'sort': d.id == widget.lastTapped ? -1e12 : -d.areaM2,
        },
      ),
  ]);

  void _reportCamera() {
    if (mapProjection case final projection?) _report(projection);
  }

  /// Reports the opening camera after the first frame: the platform may not
  /// report a camera until the player moves the map.
  void _reportStart(({LatLng target, double zoom}) start, Size size) {
    if (_startReported) return;
    _startReported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _report(
        MapProjection(target: start.target, zoom: start.zoom, size: size),
      );
      widget.onCameraIdle?.call();
    });
  }

  /// The centre of what the sheet leaves uncovered.
  Offset _focus(Size size) =>
      Offset(size.width / 2, (size.height - widget.bottomInset) / 2);

  void _report(MapProjection projection) => widget.onCamera(
    projection.toLatLng(_focus(projection.size)),
    projection.zoom,
  );

  /// Zooms [by] levels around [_focus], not the view's centre under the sheet.
  void _zoom(double by) {
    final projection = mapProjection;
    if (projection == null) return;
    final camera = projection.zoomedAround(_focus(projection.size), by);
    unawaited(
      mapController?.animateCamera(
        ml.CameraUpdate.newLatLngZoom(camera.target.toMapLibre, camera.zoom),
      ),
    );
  }

  void _tapped(Offset at) {
    if (mapProjection case final projection?) {
      widget.onTap(projection.toLatLng(at));
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = mapSize = constraints.biggest;
      return FutureBuilder<String>(
        future: mapStyle,
        builder: (context, style) {
          // Opens where the load would frame it, so nothing zooms in after.
          final start = _fit(widget.focus ?? widget.initialBounds, size);
          _reportStart(start, size);
          return Stack(
            children: [
              if (style.hasData)
                MapTaps(
                  onTap: _tapped,
                  child: ml.MapLibreMap(
                    styleString: style.data!,
                    initialCameraPosition: ml.CameraPosition(
                      target: start.target.toMapLibre,
                      zoom: start.zoom,
                    ),
                    trackCameraPosition: true,
                    onMapCreated: (c) {
                      mapController = c..addListener(_reportCamera);
                    },
                    onCameraIdle: () => widget.onCameraIdle?.call(),
                    onStyleLoadedCallback: () => runMapWork(_addLayers),
                    // A tap picks an area; a second would unpick it.
                    doubleClickZoomEnabled: false,
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                    compassEnabled: false,
                    attributionButtonMargins: const math.Point(-100, -100),
                  ),
                ),
              Positioned(
                left: PindoroSpace.s4,
                bottom: widget.bottomInset + MapAttribution.gap,
                child: const MapAttribution(),
              ),
              Positioned(
                right: PindoroSpace.s4,
                bottom: widget.bottomInset + PindoroSpace.s4,
                child: MapZoomControls(onZoom: _zoom),
              ),
            ],
          );
        },
      );
    },
  );

  @override
  void dispose() {
    mapController?.removeListener(_reportCamera);
    super.dispose();
  }
}

Map<String, dynamic> _polygons(List<District> districts) => polygonsGeoJson([
  for (final d in districts)
    for (final polygon in d.boundary)
      (polygon, {'id': d.id, 'kind': d.kind.name}),
]);
