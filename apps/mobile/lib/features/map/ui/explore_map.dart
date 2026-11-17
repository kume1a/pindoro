import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:pindoro/features/map/data/geojson.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/data/maplibre_convert.dart';
import 'package:pindoro/features/map/ui/map_work.dart';
import 'package:pindoro/features/map/ui/poi_icons.dart';
import 'package:pindoro/features/map/ui/route_projection.dart';
import 'package:pindoro/features/map/ui/widgets/map_attribution.dart';
import 'package:pindoro/features/map/ui/widgets/map_taps.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// A district on [ExploreMap]: its outline, how much of it is in memory
/// (District fills) and its name chip.
typedef ExploreDistrict = ({
  District district,
  DistrictProgress progress,
  String name,
});

/// Explore's city map: the basemap under a veil so the areas' fill steps
/// read first, their name chips, the play area as the dashed cobalt outline,
/// and [legend] over the attribution above [bottomInset] (what the sheet
/// covers; the camera frames the city above it). Districts show below
/// [PindoroCamera.areaDetailZoom], the areas inside them from it on (the
/// area picker's levels, [detailAt]). Taps report where they land and the
/// zoom.
class ExploreMap extends StatefulWidget {
  const ExploreMap({
    super.key,
    required this.districts,
    required this.playArea,
    required this.bounds,
    required this.onTap,
    this.bottomInset = 0,
    this.legend,
  });

  /// Every area of the pack: districts and the areas inside them.
  final List<ExploreDistrict> districts;

  /// The play area's polygons; empty without one.
  final List<List<Polyline>> playArea;
  final Bbox bounds;
  final void Function(LatLng at, double zoom) onTap;
  final double bottomInset;
  final Widget? legend;

  @override
  State<ExploreMap> createState() => _ExploreMapState();
}

/// Overridden in widget tests (no platform view).
final exploreMapBuilderProvider = Provider<Widget Function(ExploreMap map)>(
  (ref) =>
      (map) => map,
);

const String _veil = 'explore-veil';
const String _districts = 'explore-districts';
const String _play = 'explore-play';
const String _labels = 'explore-labels';

/// The play area's dash, in multiples of its line width (8 on, 6 off at a
/// 3 dp line).
const List<double> _dash = [8 / 3, 2];

class _ExploreMapState extends State<ExploreMap> {
  ml.MapLibreMapController? _controller;
  Future<String>? _style;
  Brightness? _brightness;
  bool _ready = false;
  Size? _size;

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
  void didUpdateWidget(ExploreMap old) {
    super.didUpdateWidget(old);
    if (!_ready) return;
    if (old.districts != widget.districts || old.playArea != widget.playArea) {
      runMapWork(_sync);
    }
  }

  ({LatLng target, double zoom}) _fit(Size size) => MapProjection.fit(
    [
      LatLng(widget.bounds.minLat, widget.bounds.minLon),
      LatLng(widget.bounds.maxLat, widget.bounds.maxLon),
    ],
    size: size,
    padding: EdgeInsets.fromLTRB(
      PindoroSpace.s4,
      PindoroSpace.s16,
      PindoroSpace.s4,
      widget.bottomInset + PindoroSpace.s4,
    ),
  );

  Map<String, dynamic> _districtFeatures(PindoroColors c) => polygonsGeoJson([
    for (final d in widget.districts)
      for (final polygon in d.district.boundary) (polygon, _look(d, c)),
  ]);

  Map<String, dynamic> _look(ExploreDistrict d, PindoroColors c) {
    final (fill, stroke) = d.progress.colorsIn(c);
    return {
      'fill': hexColor(fill ?? c.mapRegionOutline),
      'opacity': fill == null ? 0.0 : fill.a,
      'stroke': hexColor(stroke),
      'width': d.progress == DistrictProgress.notStarted
          ? PindoroStroke.hairline
          : PindoroStroke.base,
      'kind': d.district.kind.name,
    };
  }

  /// A district (the far level), not an area inside one.
  static const List<Object> _isDistrict = [
    '==',
    ['get', 'kind'],
    'district',
  ];

  /// Neighbourhoods are filled zoomed in: quarters overlap them, so only
  /// their outlines show.
  static const List<Object> _isNeighbourhood = [
    '==',
    ['get', 'kind'],
    'neighbourhood',
  ];

  static const List<Object> _isDetail = ['!', _isDistrict];

  Future<void> _addLayers() async {
    final c = _controller;
    if (c == null) return;
    final colors = PindoroTheme.of(context).colors;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    await Future.wait([
      for (final d in widget.districts)
        () async {
          await c.addImage(
            'explore:${d.district.id}',
            await MapChip.region(d.name, colors).toPng(pixelRatio),
          );
        }(),
    ]);
    await c.addGeoJsonSource(_veil, areaMaskGeoJson(const []));
    await c.addFillLayer(
      _veil,
      '$_veil-fill',
      ml.FillLayerProperties(
        fillColor: hexColor(colors.surfaceBase),
        fillOpacity: PindoroOpacity.veil,
      ),
      enableInteraction: false,
    );
    await c.addGeoJsonSource(_districts, _districtFeatures(colors));
    const detailZoom = PindoroCamera.areaDetailZoom;
    for (final (id, filter, minzoom, maxzoom) in [
      ('fill', _isDistrict, null, detailZoom),
      ('detail-fill', _isNeighbourhood, detailZoom, null),
    ]) {
      await c.addFillLayer(
        _districts,
        '$_districts-$id',
        const ml.FillLayerProperties(
          fillColor: ['get', 'fill'],
          fillOpacity: ['get', 'opacity'],
        ),
        filter: filter,
        minzoom: minzoom,
        maxzoom: maxzoom,
        enableInteraction: false,
      );
    }
    // Districts frame the map at every zoom; the areas inside them join it
    // zoomed in.
    for (final (id, filter, minzoom) in [
      ('outline', _isDistrict, null),
      ('detail-outline', _isDetail, detailZoom),
    ]) {
      await c.addLineLayer(
        _districts,
        '$_districts-$id',
        const ml.LineLayerProperties(
          lineColor: ['get', 'stroke'],
          lineWidth: ['get', 'width'],
          lineJoin: 'round',
        ),
        filter: filter,
        minzoom: minzoom,
        enableInteraction: false,
      );
    }
    await c.addGeoJsonSource(_play, polygonsGeoJson(const []));
    await c.addFillLayer(
      _play,
      '$_play-fill',
      ml.FillLayerProperties(
        fillColor: hexColor(colors.mapAreaFill),
        fillOpacity: colors.mapAreaFill.a,
      ),
      enableInteraction: false,
    );
    await c.addLineLayer(
      _play,
      '$_play-outline',
      ml.LineLayerProperties(
        lineColor: hexColor(colors.mapAreaStroke),
        lineWidth: PindoroStroke.thick,
        lineDasharray: _dash,
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );
    await c.addGeoJsonSource(_labels, _labelFeatures());
    for (final (id, filter, minzoom, maxzoom) in [
      (_labels, _isDistrict, null, detailZoom),
      ('$_labels-detail', _isDetail, detailZoom, null),
    ]) {
      await c.addSymbolLayer(
        _labels,
        id,
        const ml.SymbolLayerProperties(
          iconImage: ['get', 'icon'],
          symbolSortKey: ['get', 'sort'],
        ),
        filter: filter,
        minzoom: minzoom,
        maxzoom: maxzoom,
        enableInteraction: false,
      );
    }
    _ready = true;
    await _sync();
    await addPoiImages(c, colors, pixelRatio);
  }

  Map<String, dynamic> _labelFeatures() => labelledPointsGeoJson([
    for (final d in widget.districts)
      (
        d.district.center,
        {
          'icon': 'explore:${d.district.id}',
          'sort': -d.district.areaM2,
          'kind': d.district.kind.name,
        },
      ),
  ]);

  Future<void> _sync() async {
    final c = _controller!;
    final colors = PindoroTheme.of(context).colors;
    await c.setGeoJsonSource(_districts, _districtFeatures(colors));
    await c.setGeoJsonSource(
      _play,
      polygonsGeoJson([
        for (final polygon in widget.playArea) (polygon, const {}),
      ]),
    );
  }

  void _tapped(Offset at) {
    final camera = _controller?.cameraPosition;
    final size = _size;
    if (camera == null || size == null) return;
    widget.onTap(
      MapProjection(
        target: camera.target.toCore,
        zoom: camera.zoom,
        size: size,
      ).toLatLng(at),
      camera.zoom,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = _size = constraints.biggest;
      return FutureBuilder<String>(
        future: _style,
        builder: (context, style) {
          final start = _fit(size);
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
                    onMapCreated: (c) => _controller = c,
                    onStyleLoadedCallback: () => runMapWork(_addLayers),
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                    compassEnabled: false,
                    minMaxZoomPreference: ml.MinMaxZoomPreference(
                      math.max(0, start.zoom - 1),
                      null,
                    ),
                    attributionButtonMargins: const math.Point(-100, -100),
                  ),
                ),
              Positioned(
                left: PindoroSpace.s4,
                right: PindoroSpace.s4,
                bottom: widget.bottomInset + MapAttribution.gap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: PindoroSpace.s2,
                  children: [?widget.legend, const MapAttribution()],
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
