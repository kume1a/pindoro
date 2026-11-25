import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/map/ui/widgets/question_plate.dart';
import 'package:pindoro/features/session/ui/session_controller.dart';
import 'package:pindoro/features/session/ui/widgets/task_scaffold.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Name it (SessionScreen `nameHidden`, `nameShown`): the street painted on
/// the map and six names in the answer tray (AnswerChoices): pick, Confirm,
/// the right and wrong names marked on the tray, then the result.
class NameItView extends ConsumerStatefulWidget {
  const NameItView({
    super.key,
    required this.play,
    required this.topBar,
    required this.onPick,
    required this.onNext,
    required this.onDontKnow,
    this.chip,
  });

  final SessionPlaying play;
  final Widget topBar;
  final ValueChanged<NamedStreet> onPick;
  final Future<void> Function() onNext;

  /// "I don't know": the step graded as a miss, its answer shown.
  final VoidCallback onDontKnow;

  /// The result's next-review chip.
  final Widget? chip;

  @override
  ConsumerState<NameItView> createState() => _NameItViewState();
}

class _NameItViewState extends ConsumerState<NameItView> {
  /// The choice confirmed, shown on the tray for [answerResultDelay] before
  /// it is graded.
  int? _confirmed;

  @override
  void didUpdateWidget(NameItView old) {
    super.didUpdateWidget(old);
    if (old.play.index != widget.play.index) _confirmed = null;
  }

  Future<void> _confirm(int i, List<NamedStreet> choices) async {
    setState(() => _confirmed = i);
    await Future<void>.delayed(answerResultDelay);
    if (mounted) widget.onPick(choices[i]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final play = widget.play;
    final chip = widget.chip;
    final onNext = widget.onNext;
    final task = play.task as NameTask;
    final street = play.street;
    final name = streetName(street, settings);
    final picked = task.picked;
    // "I don't know" reveals with nothing picked.
    final revealed = task.result != null;
    final mapOf = ref.watch(pindoroMapBuilderProvider);
    final confirmed = _confirmed;
    return TaskScaffold(
      topBar: widget.topBar,
      map: (insets) => mapOf(
        PindoroMap(
          area: play.area,
          truth: street.geometry,
          frame: play.frame,
          // Asking: places, but none named after the street.
          names: revealed ? MapNames.all : MapNames.asking(street),
          topInset: insets.top,
          bottomInset: insets.bottom,
        ),
      ),
      // Asking, the tray holds the question.
      header: RiseSwitcher(
        child: revealed
            ? QuestionPlate(
                key: ValueKey((play.index, 'name')),
                street: street,
                settings: settings,
                compact: false,
                prompt: l10n.sessionNameDidYouKnow,
                glyph: PindoroGlyph.eye,
              )
            : SizedBox.shrink(key: ValueKey((play.index, 'ask'))),
      ),
      tray: AnswerTray(
        key: ValueKey((play.index, 'tray')),
        question: l10n.sessionNameCheckAsk,
        meta: l10n.answerNames(task.choices.length),
        choices: [
          for (final s in task.choices)
            (label: streetName(s, settings), sublabel: null),
        ],
        confirmLabel: l10n.commonConfirm,
        confirmHint: l10n.answerPickFirst,
        skip: (label: l10n.commonDontKnow, onSkip: widget.onDontKnow),
        // Not known: only the right one shows.
        result: confirmed == null && task.result == null
            ? null
            : (picked: confirmed ?? -1, right: task.choices.indexOf(street)),
        onConfirm: (i) => unawaited(_confirm(i, task.choices)),
      ),
      result: switch (task.result) {
        final tier? => TaskResult(
          resultKey: play.index,
          tier: tier,
          chip: chip,
          sentence: picked == null || picked == street
              ? l10n.sessionNameRight(name)
              : l10n.sessionNameWrong(name, streetName(picked, settings)),
          onNext: onNext,
        ),
        null => null,
      },
    );
  }
}
