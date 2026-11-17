import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Zoom in and zoom out, stacked [top] below what sits above them; [onCamera]
/// moves the map. Shown only with Settings → Map → Zoom buttons on.
class MapZoomControls extends ConsumerWidget {
  const MapZoomControls({super.key, required this.onCamera, this.top = 0});

  final ValueChanged<ml.CameraUpdate> onCamera;
  final double top;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(ref.watch(settingsProvider).value?.zoomButtons ?? false)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Column(
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
      ),
    );
  }
}
