import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/map/ui/route_projection.dart';
import 'package:pindoro/features/map/ui/widgets/geo_anchors.dart';
import 'package:pindoro/features/map/ui/widgets/question_plate.dart';
import 'package:pindoro/features/session/ui/session_controller.dart';
import 'package:pindoro/features/session/ui/widgets/task_scaffold.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The family sweep (SessionScreen `family`): the parent named, its lanes
/// traced with a socket each; the lanes' labels wait in a tray to be dragged
/// (or tapped, then a socket tapped) onto their lanes. Check grades them all.
class SweepView extends ConsumerStatefulWidget {
  const SweepView({
    super.key,
    required this.play,
    required this.topBar,
    required this.onPlace,
    required this.onCheck,
    required this.onNext,
  });

  final SessionPlaying play;
  final Widget topBar;

  /// A label (its street id) dropped on a lane (that lane's street id).
  final void Function(String label, String lane) onPlace;
  final VoidCallback onCheck;
  final Future<void> Function() onNext;

  @override
  ConsumerState<SweepView> createState() => _SweepViewState();
}

class _SweepViewState extends ConsumerState<SweepView> {
  MapProjection? _projection;

  /// The label tapped in the tray, waiting for a socket.
  String? _held;

  void _place(String label, String lane) {
    setState(() => _held = null);
    widget.onPlace(label, lane);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final play = widget.play;
    final task = play.task as SweepTask;
    final parent = play.street;
    final names = {for (final s in task.lanes) s.id: streetName(s, settings)};
    final placedLabels = task.placed.keys.toSet();
    final tray = [
      for (final s in task.lanes)
        if (!placedLabels.contains(s.id)) s.id,
    ]..sort((a, b) => names[a]!.compareTo(names[b]!));
    final tier = task.result;
    final mapOf = ref.watch(pindoroMapBuilderProvider);
    return TaskScaffold(
      topBar: widget.topBar,
      map: (insets) => mapOf(
        PindoroMap(
          area: play.area,
          frame: play.frame,
          traces: [
            for (final s in [parent, ...task.lanes]) ...s.geometry,
          ],
          // The lanes are named once checked.
          names: MapNames(
            streets: {
              parent.name,
              if (tier != null)
                for (final lane in task.lanes) lane.name,
            },
          ),
          onCamera: (p) => setState(() => _projection = p),
          topInset: insets.top,
          bottomInset: insets.bottom,
        ),
      ),
      overlays: [
        Positioned.fill(
          child: GeoAnchors(
            projection: _projection,
            anchors: [
              for (final (i, lane) in task.lanes.indexed)
                (
                  lane.parts.first.midpoint,
                  _Socket(
                    number: i + 1,
                    label: switch (task.placed.entries
                        .where((e) => e.value == lane.id)
                        .firstOrNull) {
                      final e? => names[e.key],
                      null => null,
                    },
                    right: tier == null
                        ? null
                        : task.placed.entries.any(
                            (e) => e.value == lane.id && e.key == lane.id,
                          ),
                    onDrop: tier == null
                        ? (label) => _place(label, lane.id)
                        : null,
                    onTap: tier == null && _held != null
                        ? () => _place(_held!, lane.id)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ],
      header: QuestionPlate(
        key: ValueKey((play.index, 'sweep')),
        street: parent,
        settings: settings,
        compact: tier != null,
        prompt: l10n.sessionSweepPrompt,
        glyph: PindoroGlyph.road,
        detail: l10n.sessionSweepHint,
      ),
      controls: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: PindoroSpace.s4,
        children: [
          Wrap(
            spacing: PindoroSpace.s2,
            runSpacing: PindoroSpace.s1,
            alignment: WrapAlignment.center,
            children: [
              for (final id in tray)
                Draggable<String>(
                  data: id,
                  feedback: Material(
                    type: MaterialType.transparency,
                    child: PindoroChip(
                      label: names[id]!,
                      selected: true,
                      onPressed: () {},
                    ),
                  ),
                  childWhenDragging: Opacity(
                    opacity: PindoroOpacity.hatch,
                    child: PindoroChip.action(
                      label: names[id]!,
                      onPressed: () {},
                    ),
                  ),
                  child: PindoroChip(
                    label: names[id]!,
                    selected: _held == id,
                    onPressed: () =>
                        setState(() => _held = _held == id ? null : id),
                  ),
                ),
            ],
          ),
          PindoroButton(
            label: l10n.sessionSweepCheck(
              task.placed.length,
              task.lanes.length,
            ),
            onPressed: tray.isEmpty ? widget.onCheck : null,
          ),
        ],
      ),
      result: tier == null
          ? null
          : TaskResult(
              resultKey: play.index,
              tier: tier,
              sentence: l10n.sessionSweepResult(task.right, task.lanes.length),
              onNext: widget.onNext,
            ),
    );
  }
}

/// A lane's socket: empty, or the label dropped on it; once checked, in the
/// tier colours of whether it is the lane's own.
class _Socket extends StatelessWidget {
  const _Socket({
    required this.number,
    required this.label,
    required this.right,
    required this.onDrop,
    required this.onTap,
  });

  final int number;
  final String? label;
  final bool? right;
  final ValueChanged<String>? onDrop;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = PindoroTheme.of(context);
    final c = theme.colors;
    final label = this.label;
    final tier = switch (right) {
      true => theme.tier(Tier.great),
      false => theme.tier(Tier.miss),
      null => null,
    };
    Widget face(bool hovering) => Container(
      constraints: const BoxConstraints(minWidth: 34, minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: PindoroSpace.s2),
      decoration: BoxDecoration(
        color:
            tier?.fill ?? (label == null ? c.surfaceRaised : c.chipSelectedBg),
        borderRadius: BorderRadius.circular(PindoroRadius.full),
        border: Border.all(
          color: hovering
              ? c.primaryBase
              : tier?.lip ??
                    (label == null ? c.mapRegionOutline : c.chipSelectedBorder),
          width: PindoroStroke.base,
        ),
      ),
      alignment: Alignment.center,
      child: label == null
          ? null
          : Text(
              label,
              style: PindoroType.labelMd.copyWith(
                color: tier?.on ?? c.chipSelectedText,
              ),
            ),
    );
    return Semantics(
      button: onTap != null,
      label: l10n.a11ySweepSocket(number, label ?? l10n.a11ySweepEmpty),
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(PindoroSpace.s2),
          child: DragTarget<String>(
            onWillAcceptWithDetails: (_) => onDrop != null,
            onAcceptWithDetails: (d) => onDrop?.call(d.data),
            builder: (context, hovering, _) => face(hovering.isNotEmpty),
          ),
        ),
      ),
    );
  }
}
