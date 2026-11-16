import 'package:flutter/widgets.dart';
import 'package:pindoro/features/map/ui/route_projection.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// Flutter widgets pinned to map points, each centred on its point, over a
/// map the same size reporting [projection] (`PindoroMap.onCamera`). Nothing
/// shows before the map's first camera.
class GeoAnchors extends StatelessWidget {
  const GeoAnchors({
    super.key,
    required this.projection,
    required this.anchors,
  });

  final MapProjection? projection;
  final List<(LatLng, Widget)> anchors;

  @override
  Widget build(BuildContext context) {
    final projection = this.projection;
    if (projection == null) return const SizedBox.shrink();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final (at, child) in anchors)
          Positioned(
            left: projection.toScreen(at).dx,
            top: projection.toScreen(at).dy,
            child: FractionalTranslation(
              translation: const Offset(-0.5, -0.5),
              child: child,
            ),
          ),
      ],
    );
  }
}
