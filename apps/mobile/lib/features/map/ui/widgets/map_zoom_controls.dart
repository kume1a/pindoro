import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Zoom in and zoom out, stacked [top] below what sits above them; [onZoom]
/// gets +1 or -1. Shown only with Settings → Map → Zoom buttons on.
class MapZoomControls extends ConsumerWidget {
  const MapZoomControls({super.key, required this.onZoom, this.top = 0});

  final ValueChanged<double> onZoom;
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
            onPressed: () => onZoom(1),
          ),
          MapControl(
            glyph: PindoroGlyph.zoomOut,
            semanticLabel: context.l10n.a11yZoomOut,
            onPressed: () => onZoom(-1),
          ),
        ],
      ),
    );
  }
}
