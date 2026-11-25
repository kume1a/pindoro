import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart' show Settings;
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/ui/junction_name.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/map/ui/route_projection.dart';
import 'package:pindoro/features/map/ui/widgets/route_draw_layer.dart';
import 'package:pindoro/features/map/ui/widgets/street_entry.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/session/ui/session_controller.dart';
import 'package:pindoro/features/session/ui/widgets/recital_result.dart';
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
    required this.onDontKnow,
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

  /// "I don't know": the step graded as a miss, its answer shown.
  final VoidCallback onDontKnow;

  /// The result's next-review chip.
  final Widget? chip;

  @override
  ConsumerState<RecitalView> createState() => _RecitalViewState();
}

class _RecitalViewState extends ConsumerState<RecitalView>
    with MapProjectionHost<RecitalView> {
  final _field = TextEditingController();
  bool _notFound = false;

  @override
  void didUpdateWidget(RecitalView old) {
    super.didUpdateWidget(old);
    // Recitals in a row share this state: a new one starts blank.
    if (old.play.index != widget.play.index) {
      _notFound = false;
      _field.clear();
    }
  }

  @override
  void dispose() {
    _field.dispose();
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
      return RecitalResultView(
        play: play,
        task: task,
        graded: graded,
        graph: graph,
        streets: streets,
        settings: settings,
        map: mapBuilder,
        topBar: widget.topBar,
        chip: widget.chip,
        onNext: widget.onNext,
        onReport: widget.onReport,
      );
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
    final controls = ButtonRow(
      flex: const [1, 2],
      spacing: PindoroSpace.s2,
      [undo, check],
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
              turn: const [],
              chip: null,
              reached: task.draft.reached,
            ),
            names: const MapNames(places: true),
            onCamera: onCamera,
            topInset: insets.top,
            bottomInset: insets.bottom,
          ),
        ),
        overlays: [
          Positioned.fill(
            child: RouteDrawLayer(
              projection: projection,
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
        onDontKnow: widget.onDontKnow,
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
            StreetEntry(
              controller: _field,
              placeholder: l10n.recitalNext,
              onChanged: () => setState(() => _notFound = false),
              onSubmitted: _add,
              error: _notFound ? l10n.recitalNotFound : null,
              match: match,
              onMatch: () {
                _field.clear();
                _add(suggested: match);
              },
            ),
          ],
        ),
      ),
      controls: controls,
      onDontKnow: widget.onDontKnow,
    );
  }

  String _stepLabel(AppLocalizations l10n, RecitalStep s, Settings? settings) =>
      recitalOntoLabel(l10n, s.turn, switch (s) {
        (street: final street?, landmark: _, turn: _) => streetName(
          street,
          settings,
        ),
        (landmark: final landmark?, street: _, turn: _) => landmarkName(
          landmark,
          settings,
        ),
        _ => l10n.debriefLinkRoad,
      });
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
