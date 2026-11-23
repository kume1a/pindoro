import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/drive_places.dart';
import 'package:pindoro/features/learning/data/nav_data.dart';
import 'package:pindoro/features/learning/ui/drive_labels.dart';
import 'package:pindoro/features/learning/ui/landmark_glyph.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// A street or a place of the open pack, with the names it is found by.
typedef _Findable = ({NamedStreet? street, Landmark? place, Set<String> forms});

/// The pack's streets and every named place (by its name or brand), each with its names
/// (searched on every keystroke).
final _findablesProvider = FutureProvider.autoDispose<List<_Findable>>((
  ref,
) async {
  final streets = await ref.watch(cityStreetsProvider.future);
  final places = await ref.watch(packPlacesProvider.future);
  return [
    for (final s in streets.values.toSet())
      (street: s, place: null, forms: nameForms(s)),
    for (final p in places.values)
      (
        street: null,
        place: p,
        forms: {
          ...placeForms(p.nameKa, p.nameEn),
          if (p.brand case final brand?) ...placeForms(brand, null),
        },
      ),
  ];
});

/// Where to (DriveSetup `search`, board V32-10): the search field over the pack's streets and
/// places ([placeholder], else Where to; [autofocus] on a screen of its own, [trailing] beside
/// it: Cancel); with nothing typed, [above], the [quick] rows (today's run, Surprise me), the
/// recent destinations and [below]. [here] gives each its distance.
class DestinationSearch extends ConsumerStatefulWidget {
  const DestinationSearch({
    required this.onPick,
    this.above = const [],
    this.quick = const [],
    this.below = const [],
    this.here,
    this.placeholder,
    this.autofocus = false,
    this.trailing,
    super.key,
  });

  final ValueChanged<DriveDest> onPick;
  final List<Widget> above;
  final List<Widget> quick;
  final List<Widget> below;
  final LatLng? here;
  final String? placeholder;
  final bool autofocus;
  final Widget? trailing;

  @override
  ConsumerState<DestinationSearch> createState() => _DestinationSearchState();
}

class _DestinationSearchState extends ConsumerState<DestinationSearch> {
  final _field = TextEditingController();

  /// The findables nearest [DestinationSearch.here] first, so equal matches (a chain's
  /// branches) come nearest first; sorted once per list and spot.
  (List<_Findable>, LatLng?, List<_Findable>)? _sorted;

  List<_Findable> _nearestFirst(List<_Findable> all, LatLng? here) {
    if (_sorted case (
      final list,
      final at,
      final sorted,
    ) when identical(list, all) && at == here) {
      return sorted;
    }
    double far(_Findable f) => here == null
        ? 0
        : distanceBetween(here, f.place?.at ?? _nearestPart(f.street!, here));
    final byDistance = [for (final f in all) (far(f), f)]
      ..sort((a, b) => a.$1.compareTo(b.$1));
    final sorted = [for (final (_, f) in byDistance) f];
    _sorted = (all, here, sorted);
    return sorted;
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final typed = _field.text.trim();
    final recents = ref.watch(recentDestinationsProvider).value ?? const [];
    // Watched from the start, so the names are ready by the first letters.
    final findables = ref.watch(_findablesProvider).value;
    // searchNames needs two letters; under that the usual rows stay.
    final searching = typed.length >= 2;
    final found = searching && findables != null
        ? searchNames(
            typed,
            _nearestFirst(findables, widget.here),
            (f) => f.forms,
          )
        : const <_Findable>[];
    final where = PlaceLine(here: widget.here);
    Widget row({
      required PindoroGlyph glyph,
      required String title,
      required LatLng at,
      required DriveDest dest,
      String? kind,
    }) => ListRow(
      leading: RowTile(glyph),
      title: title,
      subtitle: [
        ?kind,
        where.of(context, ref, at),
      ].where((s) => s.isNotEmpty).join(' · '),
      trailing: const PindoroIcon(PindoroGlyph.chevronRight),
      onTap: () => widget.onPick(dest),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: PindoroSpace.s4,
      children: [
        Row(
          spacing: PindoroSpace.s2,
          children: [
            Expanded(
              child: SearchField(
                controller: _field,
                placeholder: widget.placeholder ?? l10n.driveWhereTo,
                clearLabel: l10n.commonClear,
                autocorrect: false,
                autofocus: widget.autofocus,
                onChanged: (_) => setState(() {}),
              ),
            ),
            ?widget.trailing,
          ],
        ),
        if (searching)
          findables == null
              ? const Center(child: LaneLoader())
              : found.isEmpty
              ? Text(
                  l10n.driveNoMatch,
                  style: PindoroType.bodyMd.copyWith(
                    color: PindoroTheme.of(context).colors.textSecondary,
                  ),
                )
              : ListGroup(
                  children: [
                    for (final f in found)
                      switch (f) {
                        (street: final s?, place: _, forms: _) => row(
                          glyph: PindoroGlyph.road,
                          title: streetName(s, settings),
                          at: _nearestPart(s, widget.here),
                          dest: (
                            street: s,
                            place: null,
                            junction: null,
                            at: null,
                          ),
                        ),
                        (street: _, place: final p?, forms: _) => row(
                          glyph: placeGlyph(p),
                          title: placeLabel(p, settings),
                          kind: placeKindName(l10n, p),
                          at: p.at,
                          dest: (
                            street: null,
                            place: p,
                            junction: null,
                            at: null,
                          ),
                        ),
                        _ => const SizedBox.shrink(),
                      },
                  ],
                )
        else ...[
          ...widget.above,
          if (widget.quick.isNotEmpty) ListGroup(children: widget.quick),
          if (recents.isNotEmpty) ...[
            SectionTitle(l10n.driveRecent),
            ListGroup(
              children: [
                for (final t in recents)
                  row(
                    glyph: t.place == null
                        ? PindoroGlyph.pin
                        : placeGlyph(t.place!),
                    title: targetName(t, settings),
                    at:
                        t.at ??
                        t.place?.at ??
                        _nearestPart(t.street, widget.here),
                    dest: (
                      street: t.street,
                      place: t.place,
                      junction: t.junction,
                      at: t.at,
                    ),
                  ),
              ],
            ),
          ],
          ...widget.below,
        ],
      ],
    );
  }
}

/// The midpoint of [street]'s part nearest [here] (its first without one).
LatLng _nearestPart(NamedStreet street, LatLng? here) => here == null
    ? street.parts.first.midpoint
    : street.parts
          .map((p) => p.midpoint)
          .reduce(
            (a, b) =>
                distanceBetween(here, a) <= distanceBetween(here, b) ? a : b,
          );

/// "Vake · 4.8 km": the district a point lies in and how far it is from [here].
class PlaceLine {
  const PlaceLine({this.here});

  final LatLng? here;

  String of(BuildContext context, WidgetRef ref, LatLng at) {
    final settings = ref.watch(settingsProvider).value;
    final districts =
        ref.watch(packRepositoryProvider).value?.districts() ?? const [];
    final here = this.here;
    return [
      if (districtAt(districts, at) case final d?) districtName(d, settings),
      if (here != null) formatDistance(distanceBetween(here, at), context.l10n),
    ].join(' · ');
  }
}
