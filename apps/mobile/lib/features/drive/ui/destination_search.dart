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

/// The pack's streets and named places, each with its names (searched on every keystroke).
final _findablesProvider = FutureProvider.autoDispose<List<_Findable>>((
  ref,
) async {
  final streets = await ref.watch(cityStreetsProvider.future);
  final pack = await ref.watch(packRepositoryProvider.future);
  return [
    for (final s in streets.values.toSet())
      (street: s, place: null, forms: nameForms(s)),
    for (final l in pack.landmarks())
      (street: null, place: l, forms: placeForms(l.nameKa, l.nameEn)),
  ];
});

/// Where to (DriveSetup `search`, board V32-10): the search field over the pack's streets and
/// places; with nothing typed, [above], the [quick] rows (today's run, Surprise me), the recent
/// destinations and [below]. [here] gives each its distance.
class DestinationSearch extends ConsumerStatefulWidget {
  const DestinationSearch({
    required this.onPick,
    this.above = const [],
    this.quick = const [],
    this.below = const [],
    this.here,
    super.key,
  });

  final ValueChanged<DriveDest> onPick;
  final List<Widget> above;
  final List<Widget> quick;
  final List<Widget> below;
  final LatLng? here;

  @override
  ConsumerState<DestinationSearch> createState() => _DestinationSearchState();
}

class _DestinationSearchState extends ConsumerState<DestinationSearch> {
  final _field = TextEditingController();

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
    final found = typed.isEmpty
        ? const <_Findable>[]
        : searchNames(
            typed,
            ref.watch(_findablesProvider).value ?? const <_Findable>[],
            (f) => f.forms,
          );
    final where = PlaceLine(here: widget.here);
    Widget row({
      required PindoroGlyph glyph,
      required String title,
      required LatLng at,
      required DriveDest dest,
    }) => ListRow(
      leading: RowTile(glyph),
      title: title,
      subtitle: where.of(context, ref, at),
      trailing: const PindoroIcon(PindoroGlyph.chevronRight),
      onTap: () => widget.onPick(dest),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: PindoroSpace.s4,
      children: [
        SearchField(
          controller: _field,
          placeholder: l10n.driveWhereTo,
          clearLabel: l10n.commonClear,
          autocorrect: false,
          onChanged: (_) => setState(() {}),
        ),
        if (typed.isNotEmpty)
          found.isEmpty
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
                          dest: (street: s, place: null, junction: null),
                        ),
                        (street: _, place: final p?, forms: _) => row(
                          glyph: landmarkGlyph(p.kind),
                          title: placeLabel(p, settings),
                          at: p.at,
                          dest: (street: null, place: p, junction: null),
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
                        : landmarkGlyph(t.place!.kind),
                    title: targetName(t, settings),
                    at: t.place?.at ?? _nearestPart(t.street, widget.here),
                    dest: (
                      street: t.street,
                      place: t.place,
                      junction: t.junction,
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
