import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/ui/map_layout.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/map/ui/widgets/map_sprite.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The plan and review map (MapOverlays, v3.2: the setup's routes, the route preview, the
/// debrief, a past drive), north-up unless turned to [bearing]: the [route] in yellow with a
/// [turn] arrow over it, the [others] (routes not picked) in grey, the [track] in solid cobalt,
/// the [start] ring, the [end] flag and [pins] (turns' numbers, review marks, the routes'
/// bubbles), all drawn by the map itself, framed on [frame] (else everything drawn) above what
/// [bottom] covers, with the [names] given (all by default); [onTap] hears a tap on the map.
class PlanMapLayout extends ConsumerWidget {
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
    this.bearing = 0,
    this.turn = const [],
    this.names = MapNames.all,
    this.onTap,
    this.top,
    this.bottom,
    this.front = const [],
  });

  final String semanticsLabel;
  final MultiPolyline route;
  final double bearing;
  final Polyline turn;
  final MultiPolyline others;
  final MultiPolyline track;
  final LatLng? start;
  final LatLng? end;
  final List<MapMark> pins;
  final List<LatLng>? frame;
  final MapNames names;
  final ValueChanged<LatLng>? onTap;
  final Widget? top;
  final Widget? bottom;
  final List<Widget> front;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final city = ref.watch(packRepositoryProvider).value?.city();
    final mapOf = ref.watch(pindoroMapBuilderProvider);
    final start = this.start;
    final end = this.end;
    final frame =
        this.frame ??
        [
          for (final line in [...route, ...others, ...track]) ...line,
          ?start,
          ?end,
        ];
    return MapLayout(
      map: (insets) => city == null || frame.isEmpty
          ? const SizedBox.expand()
          : Semantics(
              label: semanticsLabel,
              child: mapOf(
                PindoroMap(
                  area: (bbox: city.bbox, boundary: city.boundary),
                  frame: frame,
                  bearing: bearing,
                  route: (
                    a: null,
                    b: null,
                    drawn: const [],
                    track: track,
                    best: route,
                    turn: turn,
                    chip: null,
                    reached: false,
                  ),
                  traces: others,
                  onTap: onTap,
                  names: names,
                  marks: [
                    if (start != null)
                      MapMark(start, const StartRing(onMap: true)),
                    ...pins,
                    // The flag's pole stands on the destination.
                    if (end != null)
                      MapMark(
                        end,
                        const DestinationFlag(onMap: true),
                        foot: DestinationFlag.foot,
                      ),
                  ],
                  topInset: insets.top,
                  bottomInset: insets.bottom,
                ),
              ),
            ),
      top: top,
      bottom: bottom,
      front: front,
    );
  }
}

/// Back from a drive screen: to the screen under it, else the Drive tab (a link opened it with
/// nothing under it).
void leaveDrive(BuildContext context) =>
    context.canPop() ? context.pop() : context.go(Routes.driveTab);

/// The plan map's back control, top left ([PlanMapLayout.top]): [leaveDrive].
class PlanMapBack extends StatelessWidget {
  const PlanMapBack({this.onPressed, super.key});

  /// Leaves the drive when null.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: PindoroSpace.s2),
    child: Align(
      alignment: Alignment.centerLeft,
      child: MapControl(
        glyph: PindoroGlyph.back,
        semanticLabel: context.l10n.commonBack,
        onPressed: onPressed ?? () => leaveDrive(context),
      ),
    ),
  );
}
