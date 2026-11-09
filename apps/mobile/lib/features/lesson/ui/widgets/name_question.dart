import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/lesson/ui/lesson_controller.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/map/ui/widgets/question_plate.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Three plates and Check (or the feedback bar), about this tall.
const double _panelInset = 300;

/// "Which street is this?" (canvas R4-21): the street painted on the map,
/// three street plates, Check. After Check a feedback bar replaces it and
/// the plates stay: the right one marked, a wrong pick shaken and marked.
class NameQuestion extends ConsumerWidget {
  const NameQuestion({
    super.key,
    required this.play,
    required this.step,
    required this.topBar,
    required this.onChoose,
    required this.onCheck,
    required this.onNext,
  });

  final LessonPlaying play;
  final NameStep step;
  final Widget topBar;
  final ValueChanged<int> onChoose;
  final VoidCallback onCheck;
  final Future<void> Function() onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final feedback = ref.read(feedbackProvider);
    final run = play.run;
    final answer = run.answered ? run.answers.last : null;
    final right = answer != null && isKnownTier(answer.tier);

    PlateChoiceState stateOf(int i) {
      final option = step.options[i];
      if (answer == null) {
        return i == play.choice
            ? PlateChoiceState.selected
            : PlateChoiceState.idle;
      }
      if (option.id == step.street.id) return PlateChoiceState.right;
      return i == play.choice ? PlateChoiceState.wrong : PlateChoiceState.dim;
    }

    return Scaffold(
      body: Stack(
        children: [
          ref.watch(pindoroMapBuilderProvider)(
            PindoroMap(
              area: play.shape,
              truth: step.street.geometry,
              topInset: MediaQuery.paddingOf(context).top + 120,
              bottomInset: _panelInset + MediaQuery.paddingOf(context).bottom,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(PindoroSpace.s4),
              child: Column(
                spacing: PindoroSpace.s4,
                children: [
                  topBar,
                  Semantics(
                    header: true,
                    child: LipBox(
                      radius: PindoroRadius.lg,
                      shadow: true,
                      padding: const EdgeInsets.fromLTRB(6, 4, 16, 4),
                      child: Row(
                        spacing: 10,
                        children: [
                          const Pindo(PindoExpression.thinking, height: 40),
                          Expanded(
                            child: Text(
                              l10n.lessonWhichStreet,
                              style: PindoroType.titleMd.copyWith(
                                color: PindoroTheme.of(
                                  context,
                                ).colors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      PindoroSpace.s4,
                      0,
                      PindoroSpace.s4,
                      PindoroSpace.s4,
                    ),
                    child: Semantics(
                      label: l10n.lessonWhichStreet,
                      child: Column(
                        spacing: PindoroSpace.s2,
                        children: [
                          for (final (i, option) in step.options.indexed)
                            PlateChoice(
                              name: streetName(option, settings),
                              sub: otherScript(option, settings),
                              state: stateOf(i),
                              onTap: answer != null
                                  ? null
                                  : () {
                                      feedback.tap();
                                      onChoose(i);
                                    },
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (answer == null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        PindoroSpace.s4,
                        0,
                        PindoroSpace.s4,
                        bottomActionGap(context),
                      ),
                      child: PindoroButton(
                        label: l10n.lessonCheck,
                        onPressed: play.choice == null ? null : onCheck,
                      ),
                    )
                  else
                    RiseIn(
                      key: ValueKey(run.index),
                      child: FeedbackBar(
                        right: right,
                        title: right ? l10n.lessonRight : l10n.lessonWrong,
                        body: right
                            ? streetName(step.street, settings)
                            : step.fix
                            ? l10n.lessonWrongFixBody
                            : run.kind == LessonKind.lesson
                            ? l10n.lessonWrongBody
                            : l10n.revealToPitStop,
                        xpLabel: right
                            ? l10n.commonXp(formatNumber(answer.xp))
                            : null,
                        action: right ? l10n.commonContinue : l10n.revealGotIt,
                        onAction: () => unawaited(onNext()),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
