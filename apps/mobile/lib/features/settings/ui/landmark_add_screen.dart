import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/database/database.dart' show Settings;
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/location.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/core/toast.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/personal_landmarks.dart';
import 'package:pindoro/features/learning/ui/junction_name.dart';
import 'package:pindoro/features/learning/ui/landmark_glyph.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Add a landmark (board V3-32 `landmarkAdd`): a tap on the map, or Here,
/// snaps to the nearest junction; then its name, kind, the approach it is
/// seen from and its side.
class LandmarkAddScreen extends ConsumerStatefulWidget {
  const LandmarkAddScreen({super.key});

  @override
  ConsumerState<LandmarkAddScreen> createState() => _LandmarkAddScreenState();
}

class _LandmarkAddScreenState extends ConsumerState<LandmarkAddScreen> {
  final _name = TextEditingController();
  LatLng? _spot;
  int? _junction;
  RoadEdge? _approach;
  String _kind = personalLandmarkKinds.first;
  bool _onLeft = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// The junction nearest [at] within the snap radius; null when none.
  static int? _nearestJunction(RoadGraph graph, LatLng at) {
    int? best;
    var bestM = LearningConfig.snapSearchM;
    for (final MapEntry(key: id, value: p) in graph.junctions.entries) {
      final m = distanceBetween(at, p);
      if (m <= bestM && graph.edgesAt(id).isNotEmpty) (best, bestM) = (id, m);
    }
    return best;
  }

  /// The edges one can drive in on to [junction].
  static List<RoadEdge> _approaches(RoadGraph graph, int junction) => [
    for (final e in graph.edgesAt(junction))
      if (graph.canDrive(e, e.other(junction))) e,
  ];

  void _mark(RoadGraph graph, LatLng at) {
    ref.read(feedbackProvider).pinDrop();
    final junction = _nearestJunction(graph, at);
    setState(() {
      _spot = at;
      _junction = junction;
      _approach = junction == null
          ? null
          : _approaches(graph, junction).firstOrNull;
    });
  }

  Future<void> _here(RoadGraph graph) async {
    final l10n = context.l10n;
    final result = await ref.read(locationServiceProvider).locate();
    if (!mounted) return;
    switch (result) {
      case Located(:final position):
        _mark(graph, position);
      case LocationDenied():
        showToast(context, l10n.cityLocationDenied);
      case LocationUnavailable():
        showToast(context, l10n.locationUnavailable);
    }
  }

  Future<void> _save(Map<int, int> nodes, LatLng spot) async {
    final junction = _junction, approach = _approach;
    if (junction == null || approach == null) return;
    ref.read(feedbackProvider).tap();
    setState(() => _busy = true);
    await ref
        .read(learningDaoProvider)
        .savePersonalLandmark(
          newPersonalLandmark(
            name: _name.text,
            kind: _kind,
            lat: spot.lat,
            lon: spot.lon,
            junctionNode: nodes[junction]!,
            approachNode: nodes[approach.other(junction)]!,
            onLeft: _onLeft,
            now: ref.read(clockProvider)(),
          ),
        );
    ref.invalidate(personalLandmarksProvider);
    if (mounted) context.pop();
  }

  /// "Seen driving north on Marjanishvili St": the direction of travel
  /// arriving on [e].
  String _approachLabel(
    RoadEdge e,
    int junction,
    Map<String, NamedStreet> streets,
    Settings? settings,
  ) {
    final l10n = context.l10n;
    final line = e.lineFrom(e.other(junction));
    final direction = l10n.compassWord(
      compassPoint(line[line.length - 2], line.last).name,
    );
    return switch (streets[e.streetId]) {
      final s? => l10n.landmarkSeenDrivingOn(
        direction,
        streetName(s, settings),
      ),
      null => l10n.landmarkSeenDriving(direction),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final pack = ref.watch(packRepositoryProvider).value;
    final graph = ref.watch(roadGraphProvider).value;
    final streets = ref.watch(cityStreetsProvider).value ?? const {};
    if (pack == null || graph == null) {
      return const Scaffold(body: Center(child: LaneLoader()));
    }
    final city = pack.city();
    final nodes = pack.junctionNodes();
    final spot = _spot;
    final junction = _junction;
    final approach = _approach;
    final canSave =
        !_busy &&
        spot != null &&
        approach != null &&
        _name.text.trim().isNotEmpty &&
        nodes.isNotEmpty;
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          ref.watch(pindoroMapBuilderProvider)(
            PindoroMap(
              area: (bbox: city.bbox, boundary: city.boundary),
              pin: junction == null ? spot : graph.at(junction),
              onTap: (at) => _mark(graph, at),
              topInset: MediaQuery.paddingOf(context).top + 80,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(PindoroSpace.s4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  MapControl(
                    glyph: PindoroGlyph.back,
                    semanticLabel: l10n.commonBack,
                    onPressed: context.pop,
                  ),
                  PindoroButton(
                    label: l10n.landmarkHere,
                    icon: PindoroGlyph.locate,
                    variant: PindoroButtonVariant.secondary,
                    onPressed: () => unawaited(_here(graph)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomPanel(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.6,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: PindoroSpace.s3,
              children: [
                Text(
                  l10n.landmarksAdd,
                  style: PindoroType.titleLg.copyWith(color: c.textPrimary),
                ),
                if (spot == null || junction == null)
                  Text(
                    spot == null
                        ? l10n.landmarkAddHint
                        : l10n.landmarkNoJunction,
                    style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
                  )
                else ...[
                  SearchField(
                    controller: _name,
                    placeholder: l10n.landmarkName,
                    clearLabel: l10n.commonClear,
                    glyph: PindoroGlyph.edit,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                  ),
                  Wrap(
                    spacing: PindoroSpace.s2,
                    runSpacing: PindoroSpace.s1,
                    children: [
                      for (final kind in personalLandmarkKinds)
                        Semantics(
                          inMutuallyExclusiveGroup: true,
                          child: PindoroChip(
                            label: landmarkKindName(l10n, kind),
                            selected: kind == _kind,
                            onPressed: () => setState(() => _kind = kind),
                          ),
                        ),
                    ],
                  ),
                  ListRow(
                    leading: RowTile(landmarkGlyph(_kind)),
                    title:
                        junctionName(graph, junction, streets, settings) ??
                        l10n.landmarkSnapped,
                    subtitle: l10n.landmarkSnapped,
                  ),
                  Wrap(
                    spacing: PindoroSpace.s2,
                    runSpacing: PindoroSpace.s1,
                    children: [
                      for (final e in _approaches(graph, junction))
                        Semantics(
                          inMutuallyExclusiveGroup: true,
                          child: PindoroChip(
                            label: _approachLabel(
                              e,
                              junction,
                              streets,
                              settings,
                            ),
                            selected: e == approach,
                            onPressed: () => setState(() => _approach = e),
                          ),
                        ),
                    ],
                  ),
                  SegmentedControl(
                    segments: {
                      false: l10n.landmarkSideRight,
                      true: l10n.landmarkSideLeft,
                    },
                    selected: _onLeft,
                    onChanged: (left) => setState(() => _onLeft = left),
                  ),
                  Text(
                    l10n.landmarkSideNote,
                    style: PindoroType.bodySm.copyWith(color: c.textSecondary),
                  ),
                ],
                PindoroButton(
                  label: l10n.landmarkSave,
                  onPressed: canSave
                      ? () => unawaited(_save(nodes, spot))
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
