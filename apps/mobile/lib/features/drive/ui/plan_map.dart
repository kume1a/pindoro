import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/ui/map_layout.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/map/ui/route_projection.dart';
import 'package:pindoro/features/map/ui/widgets/geo_anchors.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The north-up plan and review map (MapOverlays, v3.2: the setup's routes, the route preview,
/// the debrief, a past drive): the [route] in yellow, the [others] (routes not picked) in grey,
/// the [track] in solid cobalt, the [start] ring, the [end] flag and [pins] (key turns' numbers
/// or review marks) on their junctions, framed on [frame] (else everything drawn) above what
/// [bottom] covers; [onTap] hears a tap on the map.
class PlanMapLayout extends ConsumerStatefulWidget {
  const PlanMapLayout({
    super.key,
    required this.semanticsLabel,
    this.route = const [],
    this.others = const [],
    this.track = const [],
    this.start,
    this.end,
    this.pins = const [],
    this.frame,
    this.onTap,
    this.top,
    this.bottom,
    this.front = const [],
  });

  final String semanticsLabel;
  final MultiPolyline route;
  final MultiPolyline others;
  final MultiPolyline track;
  final LatLng? start;
  final LatLng? end;
  final List<(LatLng, Widget)> pins;
  final List<LatLng>? frame;
  final ValueChanged<LatLng>? onTap;
  final Widget? top;
  final Widget? bottom;
  final List<Widget> front;

  @override
  ConsumerState<PlanMapLayout> createState() => _PlanMapLayoutState();
}

class _PlanMapLayoutState extends ConsumerState<PlanMapLayout> {
  final _projection = ValueNotifier<MapProjection?>(null);

  @override
  void dispose() {
    _projection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final city = ref.watch(packRepositoryProvider).value?.city();
    final mapOf = ref.watch(pindoroMapBuilderProvider);
    final start = widget.start;
    final end = widget.end;
    final frame =
        widget.frame ??
        [
          for (final line in [
            ...widget.route,
            ...widget.others,
            ...widget.track,
          ])
            ...line,
          ?start,
          ?end,
        ];
    // The flag's pole stands on the destination: shift its 32 dp box from
    // centred on the point to its foot.
    const half = 16.0;
    final flagShift = Offset(
      -DestinationFlag.foot.x * half,
      -DestinationFlag.foot.y * half,
    );
    return MapLayout(
      map: (insets) => city == null || frame.isEmpty
          ? const SizedBox.expand()
          : Semantics(
              label: widget.semanticsLabel,
              child: mapOf(
                PindoroMap(
                  area: (bbox: city.bbox, boundary: city.boundary),
                  frame: frame,
                  route: (
                    a: null,
                    b: null,
                    drawn: const [],
                    track: widget.track,
                    best: widget.route,
                    chip: null,
                    reached: false,
                  ),
                  traces: widget.others,
                  onTap: widget.onTap,
                  names: MapNames.all,
                  onCamera: (p) => _projection.value = p,
                  topInset: insets.top,
                  bottomInset: insets.bottom,
                ),
              ),
            ),
      behind: [
        Positioned.fill(
          child: IgnorePointer(
            child: GeoAnchors(
              projection: _projection,
              anchors: [
                if (start != null) (start, const StartRing(onMap: true)),
                ...widget.pins,
                if (end != null)
                  (
                    end,
                    Transform.translate(
                      offset: flagShift,
                      child: const DestinationFlag(onMap: true),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
      top: widget.top,
      bottom: widget.bottom,
      front: widget.front,
    );
  }
}
