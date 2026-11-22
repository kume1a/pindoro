import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/feedback.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/drive/ui/destination_search.dart';
import 'package:pindoro/features/learning/data/drive_places.dart';
import 'package:pindoro/features/learning/data/nav_data.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/learning/ui/junction_name.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/ui/map_layout.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Choose on the map (SPEC §16.23 item 129): a tap drops the pin, snapped to the nearest
/// junction on a named street, named under it; Drive here (or, for Home and Work, [place]:
/// Use this spot) pops with it as the destination. Opens around where the phone is.
class DriveMapScreen extends ConsumerStatefulWidget {
  const DriveMapScreen({this.place = false, super.key});

  final bool place;

  @override
  ConsumerState<DriveMapScreen> createState() => _DriveMapScreenState();
}

class _DriveMapScreenState extends ConsumerState<DriveMapScreen> {
  LatLng? _spot;
  DriveDest? _dest;

  void _mark(RoadGraph graph, Map<String, NamedStreet> streets, LatLng at) {
    ref.read(feedbackProvider).pinDrop();
    setState(() {
      _spot = at;
      _dest = destNear(graph, streets, at);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final pack = ref.watch(packRepositoryProvider).value;
    final graph = ref.watch(drivingGraphProvider).value;
    final streets = ref.watch(cityStreetsProvider).value;
    final here = ref.watch(driveHereProvider).value?.here;
    if (pack == null || graph == null || streets == null) {
      return const Scaffold(body: Center(child: LaneLoader()));
    }
    final city = pack.city();
    final dest = _dest;
    final junction = dest?.junction;
    final subtitle = switch ((_spot, junction)) {
      (null, _) => l10n.driveMapHint,
      (_, null) => l10n.landmarkNoJunction,
      (_, final j?) => [
        junctionName(graph, j, streets, settings) ?? l10n.landmarkSnapped,
        const PlaceLine().of(context, ref, graph.at(j)),
      ].where((s) => s.isNotEmpty).join(' · '),
    };
    return Scaffold(
      extendBody: true,
      body: Builder(
        builder: (body) => MapLayout(
          map: (insets) => ref.watch(pindoroMapBuilderProvider)(
            PindoroMap(
              area: (bbox: city.bbox, boundary: city.boundary),
              pin: junction == null ? _spot : graph.at(junction),
              frame: here == null ? null : _around(here),
              onTap: (at) => _mark(graph, streets, at),
              names: MapNames.all,
              topInset: insets.top,
              bottomInset: MediaQuery.paddingOf(body).bottom,
            ),
          ),
          top: Padding(
            padding: const EdgeInsets.symmetric(vertical: PindoroSpace.s2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: MapControl(
                glyph: PindoroGlyph.back,
                semanticLabel: l10n.commonBack,
                onPressed: context.pop,
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: PindoroSpace.s3,
          children: [
            Row(
              spacing: PindoroSpace.s3,
              children: [
                const RowTile(PindoroGlyph.pin),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.driveMap,
                        style: PindoroType.titleMd.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: PindoroType.bodySm.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            PindoroButton(
              label: widget.place ? l10n.driveMapUse : l10n.driveMapGo,
              icon: widget.place ? null : PindoroGlyph.car,
              onPressed: dest == null ? null : () => context.pop(dest),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Choose on the map" among Where to's rows: the map, then [onPick] with the spot chosen
/// ([place]: for Home or Work).
class ChooseOnMapRow extends StatelessWidget {
  const ChooseOnMapRow({required this.onPick, this.place = false, super.key});

  final ValueChanged<DriveDest> onPick;
  final bool place;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListRow(
      leading: const RowTile(PindoroGlyph.map),
      title: l10n.driveMap,
      subtitle: l10n.driveMapNote,
      trailing: const PindoroIcon(PindoroGlyph.chevronRight),
      onTap: () => unawaited(() async {
        final dest = await context.push<DriveDest>(
          place ? Routes.driveMapPlace : Routes.driveMap,
        );
        if (dest != null) onPick(dest);
      }()),
    );
  }
}

/// About 600 m around [at]: a few blocks, close enough to tap a street.
List<LatLng> _around(LatLng at) {
  final box = CircleArea(at, 600).bbox;
  return [LatLng(box.minLat, box.minLon), LatLng(box.maxLat, box.maxLon)];
}
