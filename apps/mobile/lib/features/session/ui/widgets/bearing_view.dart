import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/map/ui/question_scaffold.dart';
import 'package:pindoro/features/session/ui/session_controller.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// A bearing (SessionScreen `orientation`): from the city centre, point the
/// dial's arrow at the street, Check; the truth shows in yellow and the
/// sheet names the angle off.
class BearingView extends ConsumerWidget {
  const BearingView({
    super.key,
    required this.play,
    required this.topBar,
    required this.onTurn,
    required this.onCheck,
    required this.onNext,
    required this.onDontKnow,
  });

  final SessionPlaying play;
  final Widget topBar;
  final ValueChanged<double> onTurn;
  final VoidCallback onCheck;
  final Future<void> Function() onNext;

  /// "I don't know": the step graded as a miss, its answer shown.
  final VoidCallback onDontKnow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final task = play.task as BearingTask;
    final name = streetName(play.street, settings);
    String word(double degrees) =>
        l10n.compassWord(compassPointOf(degrees).name);
    final tier = task.result;
    return QuestionScaffold(
      onDontKnow: onDontKnow,
      topBar: topBar,
      header: AskCard(
        title: l10n.sessionBearingAsk(name),
        note: l10n.sessionBearingNote,
      ),
      body: Padding(
        padding: const EdgeInsets.only(top: PindoroSpace.s6),
        child: BearingDial(
          playerBearing: task.bearing,
          trueBearing: task.checked ? task.trueBearing : null,
          enabled: !task.checked,
          onChanged: onTurn,
          semanticsLabel: l10n.a11yCompass,
          describeBearing: word,
          northLabel: l10n.driveCardinal('n'),
          animate: !MediaQuery.disableAnimationsOf(context),
          caption: task.checked
              ? l10n.sessionBearingCaptionTruth(
                  word(task.bearing),
                  name,
                  word(task.trueBearing),
                )
              : l10n.sessionBearingCaption(word(task.bearing)),
        ),
      ),
      controls: PindoroButton(label: l10n.commonCheck, onPressed: onCheck),
      result: tier == null
          ? null
          : TaskResult(
              resultKey: play.index,
              tier: tier,
              label: l10n.sessionBearingTitle(
                tierLabel(l10n, tier),
                formatNumber(task.error.round()),
              ),
              sentence: l10n.sessionBearingSentence(
                name,
                word(task.trueBearing),
                formatDistance(task.distanceM, l10n),
              ),
              onNext: onNext,
            ),
    );
  }
}
