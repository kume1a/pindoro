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
/// snaps to the nearest junction under a small panel; Next opens its name,
/// kind, the approach it is seen from and its side.
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

  /// The form is open; until then the panel stays small so the map has room
  /// to pick the spot.
  bool _details = false;

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
    final subtitle = switch ((spot, junction)) {
      (null, _) => l10n.landmarkAddHint,
      (_, null) => l10n.landmarkNoJunction,
      (_, final j?) =>
        junctionName(graph, j, streets, settings) ?? l10n.landmarkSnapped,
    };
    // The form's junction; tapping off the streets closes the form.
    final form = _details ? junction : null;
    return Scaffold(
      // The map runs under the panel (the body gets its height as padding),
      // and the panel rides above the keyboard instead of the map shrinking.
      extendBody: true,
      resizeToAvoidBottomInset: false,
      body: Builder(
        builder: (body) => Stack(
          children: [
            ref.watch(pindoroMapBuilderProvider)(
              PindoroMap(
                area: (bbox: city.bbox, boundary: city.boundary),
                pin: junction == null ? spot : graph.at(junction),
                frame: junction == null ? null : _around(graph.at(junction)),
                onTap: (at) => _mark(graph, at),
                topInset: MediaQuery.paddingOf(context).top + 80,
                bottomInset: MediaQuery.paddingOf(body).bottom,
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
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: BottomPanel(
          // Half the screen at most: the form scrolls, Save stays in view.
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.5,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: PindoroSpace.s3,
              children: [
                Row(
                  spacing: PindoroSpace.s3,
                  children: [
                    RowTile(landmarkGlyph(_kind)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.landmarksAdd,
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
                    if (form != null)
                      PindoroChip.action(
                        label: l10n.landmarkMove,
                        onPressed: () => setState(() => _details = false),
                      ),
                  ],
                ),
                if (form != null)
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: PindoroSpace.s2,
                        children: [
                          SearchField(
                            controller: _name,
                            placeholder: l10n.landmarkName,
                            clearLabel: l10n.commonClear,
                            glyph: PindoroGlyph.edit,
                            textInputAction: TextInputAction.done,
                            textCapitalization: TextCapitalization.sentences,
                            onChanged: (_) => setState(() {}),
                          ),
                          _ChoiceRow(
                            choices: {
                              for (final kind in personalLandmarkKinds)
                                kind: landmarkKindName(l10n, kind),
                            },
                            selected: _kind,
                            onChanged: (kind) => setState(() => _kind = kind),
                          ),
                          _ChoiceRow(
                            choices: {
                              for (final e in _approaches(graph, form))
                                e: _approachLabel(e, form, streets, settings),
                            },
                            selected: approach,
                            onChanged: (e) => setState(() => _approach = e),
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
                            style: PindoroType.bodySm.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (form != null)
                  PindoroButton(
                    label: l10n.landmarkSave,
                    onPressed: canSave
                        ? () => unawaited(_save(nodes, spot))
                        : null,
                  )
                else
                  PindoroButton(
                    label: l10n.commonNext,
                    onPressed: junction == null
                        ? null
                        : () => setState(() => _details = true),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of chips, one of them [selected], that scrolls sideways.
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.choices,
    required this.selected,
    required this.onChanged,
  });

  final Map<T, String> choices;
  final T? selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      spacing: PindoroSpace.s2,
      children: [
        for (final MapEntry(key: value, value: label) in choices.entries)
          Semantics(
            inMutuallyExclusiveGroup: true,
            child: PindoroChip(
              label: label,
              selected: value == selected,
              onPressed: () => onChanged(value),
            ),
          ),
      ],
    ),
  );
}

/// About 150 m around [junction]: close enough to see its approaches.
List<LatLng> _around(LatLng junction) {
  final box = CircleArea(junction, 150).bbox;
  return [LatLng(box.minLat, box.minLon), LatLng(box.maxLat, box.maxLon)];
}
