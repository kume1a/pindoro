import 'dart:async';

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
import 'package:pindoro_design/pindoro_design.dart';

/// The family sweep (SessionScreen `family`, AnswerChoices' sweep): the
/// parent named, its lanes traced with a socket each; the lanes' labels wait
/// in the tray to be dragged (or tapped, then a socket tapped) onto their
/// lanes. Confirm grades them all and marks each socket before the result.
class SweepView extends ConsumerStatefulWidget {
  const SweepView({
    super.key,
    required this.play,
    required this.topBar,
    required this.onPlace,
    required this.onCheck,
    required this.onNext,
    required this.onDontKnow,
  });

  final SessionPlaying play;
  final Widget topBar;

  /// A label (its street id) dropped on a lane (that lane's street id).
  final void Function(String label, String lane) onPlace;
  final VoidCallback onCheck;
  final Future<void> Function() onNext;

  /// "I don't know": the step graded as a miss, its answer shown.
  final VoidCallback onDontKnow;

  @override
  ConsumerState<SweepView> createState() => _SweepViewState();
}

class _SweepViewState extends ConsumerState<SweepView> {
  final _projection = ValueNotifier<MapProjection?>(null);

  /// The label (its tray index) picked up, waiting for a socket.
  int? _held;

  /// The question whose result sheet shows: Check marks the sockets first,
  /// then the sheet takes over after [answerResultDelay].
  int? _resultFor;

  @override
  void dispose() {
    _projection.dispose();
    super.dispose();
  }

  void _place(String label, String lane) {
    setState(() => _held = null);
    widget.onPlace(label, lane);
  }

  Future<void> _check(int index) async {
    widget.onCheck();
    await Future<void>.delayed(answerResultDelay);
    if (mounted) setState(() => _resultFor = index);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final play = widget.play;
    final task = play.task as SweepTask;
    final parent = play.street;
    final names = {for (final s in task.lanes) s.id: streetName(s, settings)};
    final labels = [for (final s in task.lanes) s.id]
      ..sort((a, b) => names[a]!.compareTo(names[b]!));
    final placed = task.placed;
    final tier = task.result;
    final held = _held;
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
          onCamera: (p) => _projection.value = p,
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
                () {
                  final label = placed.entries
                      .where((e) => e.value == lane.id)
                      .firstOrNull
                      ?.key;
                  final right = tier == null ? null : label == lane.id;
                  return (
                    lane.parts.first.midpoint,
                    SweepSocket(
                      semanticsLabel: l10n.a11ySweepSocket(
                        i + 1,
                        label == null ? l10n.a11ySweepEmpty : names[label]!,
                      ),
                      label: label == null ? null : names[label],
                      waking: held != null && label == null,
                      right: right,
                      truth: right == false ? names[lane.id] : null,
                      onAccept: tier == null
                          ? (l) => _place(labels[l], lane.id)
                          : null,
                      onTap: tier == null && held != null
                          ? () => _place(labels[held], lane.id)
                          : null,
                    ),
                  );
                }(),
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
      tray: SweepTray(
        question: l10n.answerWhichLane,
        meta: l10n.answerPlaced(placed.length, task.lanes.length),
        labels: [for (final id in labels) (label: names[id]!, sublabel: null)],
        placed: {
          for (final (i, id) in labels.indexed)
            if (placed.containsKey(id)) i,
        },
        held: held,
        onHold: (i) => setState(() => _held = i),
        confirmLabel: l10n.commonConfirm,
        confirmHint: l10n.answerPlaceAll,
        skip: tier == null
            ? (label: l10n.commonDontKnow, onSkip: widget.onDontKnow)
            : null,
        onConfirm: tier == null && placed.length == task.lanes.length
            ? () => unawaited(_check(play.index))
            : null,
      ),
      result: tier == null || _resultFor != play.index
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
