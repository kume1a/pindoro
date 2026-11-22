import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart' show Settings;
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/map/ui/route_projection.dart';
import 'package:pindoro/features/map/ui/widgets/route_draw_layer.dart';
import 'package:pindoro/features/map/ui/widgets/street_match_row.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/session/ui/session_controller.dart';
import 'package:pindoro/features/session/ui/widgets/task_scaffold.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Room the controls take under a scrolling body.
const double _controlsInset = 96;

/// A recital (RecitalScreen `typing`, Draw, `result`, `resultIllegal`): A
/// and B by heart, typed step by step or drawn along the streets, then the
/// graded route over the best one.
class RecitalView extends ConsumerStatefulWidget {
  const RecitalView({
    super.key,
    required this.play,
    required this.topBar,
    required this.onMode,
    required this.onTurn,
    required this.onAdd,
    required this.onUndo,
    required this.onDraw,
    required this.onCheck,
    required this.onReport,
    required this.onNext,
    this.chip,
  });

  final SessionPlaying play;
  final Widget topBar;
  final ValueChanged<RecitalMode> onMode;
  final ValueChanged<Turn> onTurn;

  /// Adds the typed (or [suggested]) next step; false when it names nothing.
  final bool Function(String typed, {NamedStreet? suggested}) onAdd;
  final VoidCallback onUndo;
  final ValueChanged<RouteDraft> onDraw;
  final VoidCallback onCheck;
  final VoidCallback onReport;
  final Future<void> Function() onNext;

  /// The result's next-review chip.
  final Widget? chip;

  @override
  ConsumerState<RecitalView> createState() => _RecitalViewState();
}

class _RecitalViewState extends ConsumerState<RecitalView> {
  final _field = TextEditingController();
  final _projection = ValueNotifier<MapProjection?>(null);
  bool _notFound = false;

  @override
  void dispose() {
    _field.dispose();
    _projection.dispose();
    super.dispose();
  }

  void _add({NamedStreet? suggested}) {
    final typed = _field.text.trim();
    if (suggested == null && typed.isEmpty) return;
    final added = widget.onAdd(typed, suggested: suggested);
    setState(() => _notFound = !added);
    if (added) _field.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final streets = ref.watch(cityStreetsProvider).value ?? const {};
    final play = widget.play;
    final task = play.task as RecitalTask;
    final graph = task.draft.graph;
    String name(NamedStreet s) => streetName(s, settings);
    final endpoints = RecitalEnds(
      from: name(task.fromStreet),
      fromAt: crossingAt(graph, task.from, task.fromStreet, streets, settings),
      to: name(task.toStreet),
      toAt: crossingAt(graph, task.to, task.toStreet, streets, settings),
    );
    final mapBuilder = ref.watch(pindoroMapBuilderProvider);
    final graded = task.graded;
    if (graded != null) {
      return _result(task, graded, graph, streets, settings, mapBuilder);
    }
    final modes = SegmentedControl<RecitalMode>(
      segments: {
        RecitalMode.type: l10n.recitalType,
        RecitalMode.draw: l10n.recitalDraw,
      },
      selected: task.mode,
      onChanged: widget.onMode,
    );
    final drawing = task.mode == RecitalMode.draw;
    final undo = PindoroButton(
      label: l10n.commonUndo,
      variant: PindoroButtonVariant.tertiary,
      onPressed: (drawing ? task.draft.edges.isEmpty : task.steps.isEmpty)
          ? null
          : drawing
          ? () => widget.onDraw(task.draft.undo())
          : widget.onUndo,
    );
    final check = PindoroButton(
      label: l10n.recitalCheck,
      onPressed: (drawing ? task.draft.reached : task.steps.isNotEmpty)
          ? widget.onCheck
          : null,
    );
    final controls = Row(
      spacing: PindoroSpace.s2,
      children: [
        undo,
        Expanded(child: check),
      ],
    );
    if (drawing) {
      return TaskScaffold(
        topBar: widget.topBar,
        header: endpoints,
        map: (insets) => mapBuilder(
          PindoroMap(
            area: play.area,
            frame: [graph.at(task.from), graph.at(task.to)],
            route: (
              a: graph.at(task.from),
              b: task.draft.reached ? graph.at(task.to) : null,
              drawn: task.draft.lines,
              track: const [],
              best: const [],
              chip: null,
              reached: task.draft.reached,
            ),
            names: const MapNames(places: true),
            onCamera: (p) => _projection.value = p,
            topInset: insets.top,
            bottomInset: insets.bottom,
          ),
        ),
        overlays: [
          Positioned.fill(
            child: RouteDrawLayer(
              projection: _projection,
              draft: task.draft,
              onDraft: widget.onDraw,
              onTouch: () {},
              onDrawing: (_) {},
              onOffRoad: (_) {},
            ),
          ),
        ],
        body: Column(
          spacing: PindoroSpace.s2,
          children: [
            modes,
            Text(
              l10n.recitalDrawHint,
              style: PindoroType.bodySm.copyWith(
                color: PindoroTheme.of(context).colors.textSecondary,
              ),
            ),
          ],
        ),
        controls: controls,
      );
    }
    final match = suggestStreet(_field.text, streets.values.toSet());
    return TaskScaffold(
      topBar: widget.topBar,
      header: endpoints,
      body: Expanded(
        child: ListView(
          padding: const EdgeInsets.only(bottom: _controlsInset),
          children: [
            modes,
            const SizedBox(height: PindoroSpace.s3),
            ListGroup(
              children: [
                ListRow(
                  title: l10n.recitalStep('1', name(task.fromStreet)),
                  subtitle: l10n.recitalStart,
                ),
                for (final (i, s) in task.steps.indexed)
                  ListRow(
                    title: l10n.recitalStep(
                      formatNumber(i + 2),
                      _stepLabel(l10n, s, settings),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: PindoroSpace.s3),
            Row(
              spacing: PindoroSpace.s2,
              children: [
                for (final (turn, label) in [
                  (Turn.left, l10n.recitalLeft),
                  (Turn.straight, l10n.recitalStraight),
                  (Turn.right, l10n.recitalRight),
                ])
                  Expanded(
                    child: PindoroButton(
                      label: label,
                      variant: task.turn == turn
                          ? PindoroButtonVariant.primary
                          : PindoroButtonVariant.secondary,
                      onPressed: () => widget.onTurn(turn),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: PindoroSpace.s3),
            SearchField(
              controller: _field,
              placeholder: l10n.recitalNext,
              clearLabel: l10n.commonClear,
              glyph: PindoroGlyph.signpost,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() => _notFound = false),
              onSubmitted: (_) => _add(),
            ),
            if (_notFound)
              Padding(
                padding: const EdgeInsets.only(top: PindoroSpace.s2),
                child: Text(
                  l10n.recitalNotFound,
                  style: PindoroType.bodySm.copyWith(
                    color: PindoroTheme.of(context).colors.textSecondary,
                  ),
                ),
              ),
            if (match != null)
              StreetMatchRow(
                match,
                note: l10n.sessionCrossingsMatch,
                onTap: () {
                  _field.clear();
                  _add(suggested: match);
                },
              ),
          ],
        ),
      ),
      controls: controls,
    );
  }

  Widget _result(
    RecitalTask task,
    RecitalResult graded,
    RoadGraph graph,
    Map<String, NamedStreet> streets,
    Settings? settings,
    Widget Function(PindoroMap) map,
  ) {
    final l10n = context.l10n;
    final play = widget.play;
    final path = graded.path;
    final best = graded.best;
    final illegal = graded.illegal;
    String nameOf(RoadEdge? e) => switch (streets[e?.streetId]) {
      final s? => streetName(s, settings),
      null => '',
    };
    final extraM = graded.extraM ?? 0;
    final chip = switch (illegal) {
      final m? => (
        at: _middle(m.edge.line),
        label: m.reason == IllegalReason.oneway
            ? l10n.recitalOnewayChip
            : l10n.recitalNoTurnChip,
      ),
      null when graded.divergence != null && extraM >= 1 => (
        at: graph.at(graded.divergence!),
        label: '+${formatDistance(extraM, l10n)}',
      ),
      null => null,
    };
    final turns = [
      for (final d in graded.decisions)
        if (d.newStreet && d.turn != null) d,
    ];
    final right = graded.decisions.where((d) => d.correct).length;
    final stretch = graded.stretch;
    final sentence = switch (illegal) {
      final m? when m.reason == IllegalReason.oneway => l10n.recitalOneway(
        nameOf(m.edge),
      ),
      final m? => l10n.recitalNoTurn(nameOf(m.approach), nameOf(m.edge)),
      null when path == null => l10n.recitalNoRoute,
      null when stretch == null => l10n.recitalNotThere,
      null => [
        if (extraM < 1)
          l10n.recitalBestDrive
        else
          l10n.recitalExtra(formatDistance(extraM, l10n)),
        if (graded.decisions.isNotEmpty)
          l10n.recitalTurnsMatch(
            formatNumber(right),
            formatNumber(graded.decisions.length),
          ),
      ].join(' '),
    };
    final label = illegal != null
        ? l10n.recitalNotDrivable
        : stretch != null && extraM >= 1 && graded.tier != Tier.miss
        ? l10n.recitalLonger(
            tierWord(l10n, graded.tier),
            formatNumber(((stretch - 1) * 100).round()),
          )
        : null;
    final a = graph.at(task.from);
    final b = graph.at(task.to);
    return TaskScaffold(
      topBar: widget.topBar,
      header: const SizedBox.shrink(),
      map: (insets) => map(
        PindoroMap(
          area: play.area,
          frame: [
            a,
            b,
            for (final line in [...?best?.lines, ...?path?.lines]) ...line,
          ],
          route: (
            a: a,
            b: b,
            drawn: path?.lines ?? const [],
            track: const [],
            best: best?.lines ?? const [],
            chip: chip,
            reached: true,
          ),
          names: MapNames.all,
          topInset: insets.top,
          bottomInset: insets.bottom,
        ),
      ),
      overlays: [
        Positioned.fill(
          child: Semantics(
            container: true,
            label: l10n.a11yRecitalMap,
            child: const SizedBox.expand(),
          ),
        ),
      ],
      result: TaskResult(
        resultKey: play.index,
        tier: graded.tier,
        label: label,
        chip: widget.chip,
        sentence: sentence,
        onNext: widget.onNext,
        chips: [
          for (final d in turns)
            _DecisionRow(
              tier: d.correct ? Tier.great : Tier.close,
              title: _ontoLabel(l10n, d.turn, nameOf(d.exit)),
              subtitle: d.correct
                  ? l10n.recitalOnBest
                  : graph
                        .legalExits(d.junction, approach: d.approach)
                        .any((e) => e.id == d.exit.id)
                  ? l10n.recitalDetour
                  : l10n.recitalWrongWay,
            ),
          if (task.practice.isNotEmpty)
            StatChip(
              label: l10n.recitalPractice(task.practice.length),
              glyph: PindoroGlyph.retry,
            ),
          if (illegal != null)
            task.reported
                ? StatChip(
                    label: l10n.recitalReported,
                    glyph: PindoroGlyph.check,
                  )
                : Tappable(
                    onTap: widget.onReport,
                    label: l10n.recitalReport,
                    child: StatChip(
                      label: l10n.recitalReport,
                      glyph: PindoroGlyph.flag,
                    ),
                  ),
        ],
      ),
    );
  }

  String _stepLabel(AppLocalizations l10n, RecitalStep s, Settings? settings) =>
      _ontoLabel(l10n, s.turn, switch (s) {
        (street: final street?, landmark: _, turn: _) => streetName(
          street,
          settings,
        ),
        (landmark: final landmark?, street: _, turn: _) => landmarkName(
          landmark,
          settings,
        ),
        _ => '',
      });
}

LatLng _middle(Polyline line) => line[line.length ~/ 2];

String _ontoLabel(AppLocalizations l10n, Turn? turn, String place) =>
    switch (turn) {
      Turn.left => l10n.recitalLeftOnto(place),
      Turn.right => l10n.recitalRightOnto(place),
      Turn.straight => l10n.recitalStraightOnto(place),
      Turn.uTurn => l10n.recitalUTurnOnto(place),
      null => l10n.recitalThen(place),
    };

/// "At Chavchavadze Avenue": another street meeting [on] at [junction];
/// null where none does.
String? crossingAt(
  RoadGraph graph,
  int junction,
  NamedStreet on,
  Map<String, NamedStreet> streets,
  Settings? settings,
) {
  final other = {
    for (final e in graph.edgesAt(junction))
      if (streets[e.streetId] case final s? when s != on)
        streetName(s, settings),
  }.toList()..sort();
  return other.firstOrNull;
}

/// A recital's ends (RecitalScreen's endpoint card): "By heart, no map", A
/// and B with the street each is at.
class RecitalEnds extends StatelessWidget {
  const RecitalEnds({
    super.key,
    required this.from,
    required this.fromAt,
    required this.to,
    required this.toAt,
  });

  final String from;
  final String? fromAt;
  final String to;
  final String? toAt;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    Widget end(String letter, String street, String? at) => Row(
      spacing: PindoroSpace.s3,
      children: [
        CircleAvatar(
          radius: PindoroSize.iconMd / 2 + PindoroSpace.s1,
          backgroundColor: c.primarySoft,
          child: Text(
            letter,
            style: PindoroType.titleSm.copyWith(color: c.primaryText),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                street,
                style: PindoroType.titleSm.copyWith(color: c.textPrimary),
              ),
              if (at != null)
                Text(
                  l10n.recitalAt(at),
                  style: PindoroType.bodySm.copyWith(color: c.textSecondary),
                ),
            ],
          ),
        ),
      ],
    );
    return LipBox(
      shadow: true,
      padding: const EdgeInsets.symmetric(
        horizontal: PindoroSpace.s4,
        vertical: PindoroSpace.s3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: PindoroSpace.s2,
        children: [
          Text(
            l10n.recitalByHeart,
            style: PindoroType.labelMd.copyWith(color: c.textSecondary),
          ),
          end('A', from, fromAt),
          end('B', to, toAt),
        ],
      ),
    );
  }
}

/// One turn of a graded recital: its tier icon, "Left onto X" and whether
/// it was on the best route.
class _DecisionRow extends StatelessWidget {
  const _DecisionRow({
    required this.tier,
    required this.title,
    required this.subtitle,
  });

  final Tier tier;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return SizedBox(
      width: double.infinity,
      child: Row(
        spacing: PindoroSpace.s3,
        children: [
          TierBadge(tier, size: PindoroSize.iconMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: PindoroType.titleSm.copyWith(color: c.textPrimary),
                ),
                Text(
                  subtitle,
                  style: PindoroType.bodySm.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
