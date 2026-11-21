import 'dart:async';
import 'dart:math' as math;
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:pindoro/features/map/data/geojson.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/data/maplibre_convert.dart';
import 'package:pindoro/features/map/ui/map_host.dart';
import 'package:pindoro/features/map/ui/map_work.dart';
import 'package:pindoro/features/map/ui/poi_icons.dart';
import 'package:pindoro/features/map/ui/widgets/map_attribution.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Builds the Guided map; widget tests override it so no platform view is made.
final driveMapBuilderProvider = Provider<Widget Function(DriveMap map)>(
  (ref) =>
      (map) => map,
);

/// The Guided drive's live map (board V32-20, SPEC §16.23 item 118):
/// heading-up and tilted, following the car at [at] driving [heading], with
/// the [route] yellow on its ink casing and the [destination]. No names, no
/// landmarks and no input. [lost] (GPS lost) dims it.
class DriveMap extends ConsumerStatefulWidget {
  const DriveMap({
    super.key,
    required this.at,
    required this.heading,
    required this.route,
    required this.destination,
    this.lost = false,
    this.bottomInset = 0,
  });

  final LatLng? at;
  final double? heading;
  final MultiPolyline route;
  final LatLng destination;
  final bool lost;

  /// Height covered at the bottom, for the attribution chip.
  final double bottomInset;

  static const double zoom = 16.5;
  static const double tilt = 32;

  @override
  ConsumerState<DriveMap> createState() => _DriveMapState();
}

abstract final class _Sources {
  static const String route = 'drive-route';
  static const String car = 'drive-car';
  static const String end = 'drive-end';
}

const String _carImage = 'drive-car';

class _DriveMapState extends ConsumerState<DriveMap> with MapHost<DriveMap> {
  bool _ready = false;
  double _bearing = 0;

  @override
  void styleChanged() => _ready = false;

  /// Where the camera looks: ahead of the car, so the car sits low on the
  /// screen with the road ahead above it.
  LatLng _target(LatLng at) {
    final height = mapSize?.height ?? 0;
    final metresPerDp =
        156543.03 *
        math.cos(at.lat * math.pi / 180) /
        math.pow(2, DriveMap.zoom);
    return LocalProjection(at).unproject((
      0.25 * height * metresPerDp * math.sin(_bearing * math.pi / 180),
      0.25 * height * metresPerDp * math.cos(_bearing * math.pi / 180),
    ));
  }

  ml.CameraPosition _camera(LatLng at) => ml.CameraPosition(
    target: _target(at).toMapLibre,
    zoom: DriveMap.zoom,
    bearing: _bearing,
    tilt: DriveMap.tilt,
  );

  @override
  void didUpdateWidget(DriveMap old) {
    super.didUpdateWidget(old);
    _bearing = widget.heading ?? _bearing;
    if (!_ready) return;
    if (widget.at != old.at || widget.heading != old.heading) {
      runMapWork(_follow);
    }
    if (!identical(widget.route, old.route)) runMapWork(_sendRoute);
  }

  Future<void> _follow() async {
    final c = mapController;
    final at = widget.at;
    if (c == null || at == null) return;
    await c.setGeoJsonSource(_Sources.car, pointsGeoJson([at]));
    await c.animateCamera(
      ml.CameraUpdate.newCameraPosition(_camera(at)),
      duration: PindoroMotion.durationSlow * 2,
    );
  }

  Future<void> _sendRoute() async => mapController?.setGeoJsonSource(
    _Sources.route,
    linesGeoJson(widget.route),
  );

  Future<void> _addLayers() async {
    final c = mapController;
    if (c == null) return;
    final colors = PindoroTheme.of(context).colors;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    for (final id in [...NameLayers.places, NameLayers.roads, 'pois']) {
      await c.setLayerVisibility(id, false);
    }
    await addBasemapImages(c, colors, pixelRatio);
    await c.addImage(_carImage, await CarMark(colors).toPng(pixelRatio));
    await c.addGeoJsonSource(_Sources.route, linesGeoJson(widget.route));
    for (final (id, color, width) in [
      ('casing', colors.mapAnswerCasing, 2 * PindoroStroke.answer),
      ('line', colors.mapAnswerLine, 2 * PindoroStroke.answer - 8),
    ]) {
      await c.addLineLayer(
        _Sources.route,
        '${_Sources.route}-$id',
        ml.LineLayerProperties(
          lineColor: hexColor(color),
          lineWidth: width,
          lineCap: 'round',
          lineJoin: 'round',
        ),
        belowLayerId: NameLayers.lowest,
        enableInteraction: false,
      );
    }
    await c.addGeoJsonSource(_Sources.end, pointsGeoJson([widget.destination]));
    await c.addCircleLayer(
      _Sources.end,
      '${_Sources.end}-dot',
      ml.CircleLayerProperties(
        circleColor: hexColor(colors.mapAnswerLine),
        circleRadius: 2 * PindoroStroke.answer,
        circleStrokeColor: hexColor(colors.mapAnswerCasing),
        circleStrokeWidth: PindoroStroke.thick,
      ),
      enableInteraction: false,
    );
    await c.addGeoJsonSource(_Sources.car, pointsGeoJson([?widget.at]));
    await c.addSymbolLayer(
      _Sources.car,
      '${_Sources.car}-mark',
      const ml.SymbolLayerProperties(
        iconImage: _carImage,
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        iconPitchAlignment: 'viewport',
        iconRotationAlignment: 'viewport',
      ),
      enableInteraction: false,
    );
    _ready = true;
    await _follow();
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
                ml.MapLibreMap(
                  styleString: style.data!,
                  initialCameraPosition: _camera(start),
                  onMapCreated: (c) => mapController = c,
                  onStyleLoadedCallback: () => runMapWork(_addLayers),
                  scrollGesturesEnabled: false,
                  zoomGesturesEnabled: false,
                  rotateGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  doubleClickZoomEnabled: false,
                  compassEnabled: false,
                  attributionButtonMargins: const Point(-100, -100),
                ),
              if (widget.lost)
                Positioned.fill(
                  child: ColoredBox(
                    color: PindoroTheme.of(
                      context,
                    ).colors.mapMask.withValues(alpha: PindoroOpacity.veil),
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
    },
  );
}
