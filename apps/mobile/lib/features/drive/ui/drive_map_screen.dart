import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/feedback.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/drive/ui/destination_search.dart';
import 'package:pindoro/features/drive/ui/plan_map.dart';
import 'package:pindoro/features/learning/data/drive_places.dart';
import 'package:pindoro/features/learning/data/nav_data.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/learning/ui/landmark_glyph.dart';
import 'package:pindoro/features/map/data/map_places.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/ui/map_layout.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart' show LearningConfig;
import 'package:url_launcher/url_launcher.dart';

/// Choose on the map (SPEC §16.23 items 129, 132): every street and named place on the map; a
/// tap on a place picks it (its outline lit, its details in the sheet: kind, address, opening
/// hours, Call and Website), a tap anywhere else drops the pin right there, named by the road it
/// is by. Drive here pops with it as the destination ([pick]: Use this spot for Home and Work,
/// Add stop for a stop on the way). Opens around where the phone is.
class DriveMapScreen extends ConsumerStatefulWidget {
  const DriveMapScreen({this.pick = MapPick.drive, super.key});

  final MapPick pick;

  @override
  ConsumerState<DriveMapScreen> createState() => _DriveMapScreenState();
}

/// The spot tapped, the place there if one was, and the destination it makes (null out of a
/// road's reach).
typedef _Pick = ({LatLng at, Landmark? place, DriveDest? dest});

class _DriveMapScreenState extends ConsumerState<DriveMapScreen> {
  _Pick? _pick;

  void _spot(RoadGraph graph, Map<String, NamedStreet> streets, LatLng at) {
    ref.read(feedbackProvider).pinDrop();
    setState(
      () => _pick = (at: at, place: null, dest: destNear(graph, streets, at)),
    );
  }

  void _place(
    RoadGraph graph,
    Map<String, NamedStreet> streets,
    Map<String, Landmark> places,
    MapPlace tapped,
  ) {
    ref.read(feedbackProvider).pinDrop();
    final place = placeOf(tapped, places);
    final DriveDest dest = (
      street: null,
      place: place,
      junction: null,
      at: place.at,
    );
    setState(
      () => _pick = (
        at: place.at,
        place: place,
        dest: resolveDest(graph, streets, dest) == null ? null : dest,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pack = ref.watch(packRepositoryProvider).value;
    final graph = ref.watch(drivingGraphProvider).value;
    final streets = ref.watch(cityStreetsProvider).value;
    final places = ref.watch(packPlacesProvider).value;
    final here = ref.watch(driveHereProvider).value?.here;
    if (pack == null || graph == null || streets == null || places == null) {
      return const Scaffold(body: Center(child: LaneLoader()));
    }
    final city = pack.city();
    final pick = _pick;
    final dest = pick?.dest;
    return Scaffold(
      extendBody: true,
      body: Builder(
        builder: (body) => MapLayout(
          map: (insets) => ref.watch(pindoroMapBuilderProvider)(
            PindoroMap(
              area: (bbox: city.bbox, boundary: city.boundary),
              pin: pick?.at,
              placeOutline: pick?.place?.outline,
              frame: here == null ? null : _around(here),
              onTap: (at) => _spot(graph, streets, at),
              onPlaceTap: (p) => _place(graph, streets, places, p),
              names: MapNames.everything,
              topInset: insets.top,
              bottomInset: MediaQuery.paddingOf(body).bottom,
            ),
          ),
          top: PlanMapBack(onPressed: context.pop),
        ),
      ),
      bottomNavigationBar: BottomPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: PindoroSpace.s3,
          children: [
            _PickDetails(pick: pick, graph: graph, streets: streets),
            PindoroButton(
              label: switch (widget.pick) {
                MapPick.drive => l10n.driveMapGo,
                MapPick.place => l10n.driveMapUse,
                MapPick.stop => l10n.driveAddStop,
              },
              icon: switch (widget.pick) {
                MapPick.drive => PindoroGlyph.car,
                MapPick.place => null,
                MapPick.stop => PindoroGlyph.plus,
              },
              onPressed: dest == null ? null : () => context.pop(dest),
            ),
          ],
        ),
      ),
    );
  }
}

/// What was picked on the map, compact: a place's glyph, name, kind, district, distance and
/// minutes, then its address (else the road it is by) and opening hours, and Call and Website
/// when mapped; a pin's road and district; before a tap, the hint.
class _PickDetails extends ConsumerWidget {
  const _PickDetails({
    required this.pick,
    required this.graph,
    required this.streets,
  });

  final _Pick? pick;
  final RoadGraph graph;
  final Map<String, NamedStreet> streets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final pick = this.pick;
    final place = pick?.place;
    final dest = pick?.dest;
    final target = dest == null ? null : resolveDest(graph, streets, dest);
    final here = ref.watch(driveHereProvider).value?.here;
    final minutes = target == null
        ? null
        : ref.watch(driveMinutesProvider(target)).value;
    final road = target == null ? null : streetName(target.street, settings);
    final title = switch ((pick, place)) {
      (null, _) => l10n.driveMap,
      (_, final p?) => placeLabel(p, settings),
      _ => l10n.driveMapPin,
    };
    final summary = pick == null
        ? l10n.driveMapHint
        : [
            if (place != null) placeKindName(l10n, place) else ?road,
            PlaceLine(here: here).of(context, ref, pick.at),
            if (minutes != null) l10n.driveAboutMin(minutes),
            if (dest == null) l10n.driveMapNoRoad,
          ].where((s) => s.isNotEmpty).join(' · ');
    final details = place is Poi ? place : null;
    final address = switch (details) {
      Poi(street: final s?, housenumber: final n?) => '$s $n',
      Poi(street: final s?) => s,
      _ when place != null => road,
      _ => null,
    };
    final phone = phoneLink(details?.phone);
    final web = webLink(details?.website);
    Widget line(PindoroGlyph glyph, String text) => Row(
      spacing: PindoroSpace.s2,
      children: [
        PindoroIcon(glyph, size: PindoroSize.iconSm, color: c.textSecondary),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: PindoroType.bodySm.copyWith(color: c.textSecondary),
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: PindoroSpace.s2,
      children: [
        Row(
          spacing: PindoroSpace.s3,
          children: [
            RowTile(place == null ? PindoroGlyph.pin : placeGlyph(place)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: PindoroType.titleMd.copyWith(color: c.textPrimary),
                  ),
                  Text(
                    summary,
                    style: PindoroType.bodySm.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (address != null) line(PindoroGlyph.pin, address),
        if (details?.hours case final hours?) line(PindoroGlyph.timer, hours),
        if (phone != null || web != null)
          Row(
            spacing: PindoroSpace.s3,
            children: [
              if (phone != null)
                Expanded(
                  child: PindoroButton(
                    label: l10n.placeCall,
                    variant: PindoroButtonVariant.secondary,
                    onPressed: () => unawaited(launchUrl(phone)),
                  ),
                ),
              if (web != null)
                Expanded(
                  child: PindoroButton(
                    label: l10n.placeWebsite,
                    icon: PindoroGlyph.external,
                    variant: PindoroButtonVariant.secondary,
                    onPressed: () => unawaited(
                      launchUrl(web, mode: LaunchMode.externalApplication),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// The pack's place for a [tapped] one (item 132): by its OSM id, else the one of its name
/// within [LearningConfig.placeTapNameM], else the tiles' own name and kind with no details.
Landmark placeOf(MapPlace tapped, Map<String, Landmark> places) {
  if (places[tapped.id] case final p?) return p;
  final name = tapped.name;
  if (name != null) {
    for (final p in places.values) {
      if (p.nameKa == name &&
          distanceBetween(p.at, tapped.at) <= LearningConfig.placeTapNameM) {
        return p;
      }
    }
  }
  return Poi(
    id: tapped.id ?? '',
    osmKey: '',
    kind: tapped.kind,
    nameKa: name ?? '',
    nameEn: null,
    brand: null,
    at: tapped.at,
  );
}

/// A call to the first of OSM's [phone] numbers; null without one.
Uri? phoneLink(String? phone) => switch (phone?.split(';').first.trim()) {
  final n? when n.isNotEmpty => Uri(
    scheme: 'tel',
    path: n.replaceAll(RegExp(r'[^+\d]'), ''),
  ),
  _ => null,
};

/// The first of OSM's [website]s, https when it names no scheme; null without one.
Uri? webLink(String? website) => switch (website?.split(';').first.trim()) {
  final w? when w.isNotEmpty => Uri.tryParse(
    w.contains('://') ? w : 'https://$w',
  ),
  _ => null,
};

/// What a spot chosen on the map is for: a drive's destination, Home or Work, or a stop on the
/// way (item 134).
enum MapPick { drive, place, stop }

/// "Choose on the map" among Where to's rows: the map, then [onPick] with the spot chosen
/// for [pick].
class ChooseOnMapRow extends StatelessWidget {
  const ChooseOnMapRow({
    required this.onPick,
    this.pick = MapPick.drive,
    super.key,
  });

  final ValueChanged<DriveDest> onPick;
  final MapPick pick;

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
          pick == MapPick.drive
              ? Routes.driveMap
              : Routes.driveMapFor(pick.name),
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
