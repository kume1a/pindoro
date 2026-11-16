import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/today_plan.dart';
import 'package:pindoro/features/map/ui/area_picker_map.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Home or work (design system Area selector, Home and work): one
/// neighbourhood, picked on the map or from the nearest chips.
class AnchorScreen extends ConsumerStatefulWidget {
  const AnchorScreen({super.key, required this.anchor});

  final Anchor anchor;

  @override
  ConsumerState<AnchorScreen> createState() => _AnchorScreenState();
}

class _AnchorScreenState extends ConsumerState<AnchorScreen> {
  String? _picked;
  LatLng? _center;
  bool _busy = false;

  /// Chips under the title: the pick, then the nearest to the map's centre.
  static const int _chips = 6;

  Future<void> _save(String cityId, String chunkId) async {
    ref.read(feedbackProvider).tap();
    setState(() => _busy = true);
    await ref
        .read(learningDaoProvider)
        .setAnchor(cityId, widget.anchor, chunkId);
    ref.invalidate(learnCityProvider);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final pack = ref.watch(packRepositoryProvider).value;
    final saved = ref.watch(learnCityProvider).value;
    if (pack == null || settings == null) {
      return const Scaffold(body: Center(child: LaneLoader()));
    }
    final city = pack.city();
    final areas = [
      for (final d in pack.districts())
        if (d.kind == DistrictKind.neighbourhood) d,
    ];
    final names = {for (final d in areas) d.id: districtName(d, settings)};
    final picked =
        _picked ??
        switch (widget.anchor) {
          Anchor.home => saved?.homeId,
          Anchor.work => saved?.workId,
        };
    final pickedArea = areas.where((d) => d.id == picked).firstOrNull;
    final chips = [
      ?pickedArea,
      ...nearestAreas(
        areas,
        {?picked},
        _center ?? pickedArea?.center ?? city.center,
        detail: true,
      ).take(_chips - (pickedArea == null ? 0 : 1)),
    ];
    final home = widget.anchor == Anchor.home;
    final name = pickedArea == null ? null : names[pickedArea.id]!;
    void pick(String id) {
      ref.read(feedbackProvider).tap();
      setState(() => _picked = id);
    }

    return Scaffold(
      extendBody: true,
      body: Builder(
        builder: (body) => Stack(
          children: [
            ref.watch(areaPickerMapBuilderProvider)(
              AreaPickerMap(
                key: ObjectKey(pack),
                districts: areas,
                names: names,
                picked: {?picked},
                lastTapped: picked,
                initialBounds: pickedArea?.bbox ?? _around(city.center),
                bottomInset: MediaQuery.paddingOf(body).bottom,
                onTap: (at) {
                  if (areaAt(areas, at, double.infinity) case final d?) {
                    pick(d.id);
                  }
                },
                onCamera: (center, _) => _center = center,
                onCameraIdle: () => setState(() {}),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(PindoroSpace.s4),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: MapControl(
                    glyph: PindoroGlyph.back,
                    semanticLabel: l10n.commonBack,
                    onPressed: context.pop,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: PindoroSpace.s3,
          children: [
            Text(
              switch ((home, name)) {
                (true, final n?) => l10n.anchorHomeTitle(n),
                (false, final n?) => l10n.anchorWorkTitle(n),
                (true, null) => l10n.learnHome,
                (false, null) => l10n.learnWork,
              },
              style: PindoroType.titleLg.copyWith(
                color: PindoroTheme.of(context).colors.textPrimary,
              ),
            ),
            Wrap(
              spacing: PindoroSpace.s2,
              runSpacing: PindoroSpace.s2,
              children: [
                for (final d in chips)
                  Semantics(
                    inMutuallyExclusiveGroup: true,
                    child: PindoroChip(
                      label: names[d.id]!,
                      selected: d.id == picked,
                      onPressed: () => pick(d.id),
                    ),
                  ),
              ],
            ),
            PindoroButton(
              label: home ? l10n.anchorSetHome : l10n.anchorSetWork,
              onPressed: picked == null || _busy
                  ? null
                  : () => _save(city.id, picked),
            ),
          ],
        ),
      ),
    );
  }
}

/// About 2 km each way around [at], close enough for neighbourhood outlines.
Bbox _around(LatLng at) =>
    Bbox(at.lat - 0.02, at.lon - 0.025, at.lat + 0.02, at.lon + 0.025);
