import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:pindoro/core/format.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Zoom in and zoom out, stacked; [onCamera] moves the map.
class MapZoomControls extends StatelessWidget {
  const MapZoomControls({super.key, required this.onCamera});

  final ValueChanged<ml.CameraUpdate> onCamera;

  @override
  Widget build(BuildContext context) => Column(
    spacing: PindoroSpace.s2,
    children: [
      MapControl(
        glyph: PindoroGlyph.zoomIn,
        semanticLabel: context.l10n.a11yZoomIn,
        onPressed: () => onCamera(ml.CameraUpdate.zoomIn()),
      ),
      MapControl(
        glyph: PindoroGlyph.zoomOut,
        semanticLabel: context.l10n.a11yZoomOut,
        onPressed: () => onCamera(ml.CameraUpdate.zoomOut()),
      ),
    ],
  );
}
