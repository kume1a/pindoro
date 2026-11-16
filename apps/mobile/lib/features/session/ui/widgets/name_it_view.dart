import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/core/speech.dart';
import 'package:pindoro/features/map/ui/pin_drop_view.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/map/ui/widgets/question_plate.dart';
import 'package:pindoro/features/session/ui/session_controller.dart';
import 'package:pindoro/features/session/ui/widgets/task_scaffold.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Name it (SessionScreen `nameHidden`, `nameShown`): the street painted on
/// the map; Show name, then Forgot or Knew it. A checked review offers six
/// names instead and shows the result.
class NameItView extends ConsumerWidget {
  const NameItView({
    super.key,
    required this.play,
    required this.topBar,
    required this.onShow,
    required this.onRate,
    required this.onPick,
    required this.onNext,
    this.chip,
  });

  final SessionPlaying play;
  final Widget topBar;
  final VoidCallback onShow;
  final ValueChanged<bool> onRate;
  final ValueChanged<NamedStreet> onPick;
  final Future<void> Function() onNext;

  /// The result's next-review chip.
  final Widget? chip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final task = play.task as NameTask;
    final street = play.street;
    final name = streetName(street, settings);
    final choices = task.choices;
    final shown = task.shown || task.picked != null;
    final language = speechLanguage(name);
    final canSpeak = ref.watch(canSpeakProvider(language)).value ?? false;
    final picked = task.picked;
    return TaskScaffold(
      topBar: topBar,
      map: ref.watch(pindoroMapBuilderProvider)(
        PindoroMap(
          area: play.area,
          truth: street.geometry,
          frame: play.frame,
          topInset: MediaQuery.paddingOf(context).top + 180,
          bottomInset: PinDropView.confirmInset(context),
        ),
      ),
      header: RiseSwitcher(
        child: shown
            ? QuestionPlate(
                key: ValueKey((play.index, 'name')),
                street: street,
                settings: settings,
                compact: false,
                prompt: l10n.sessionNameDidYouKnow,
                glyph: PindoroGlyph.eye,
              )
            : AskCard(
                key: ValueKey((play.index, 'ask')),
                title: choices == null
                    ? l10n.sessionNameAsk
                    : l10n.sessionNameCheckAsk,
                note: choices == null
                    ? l10n.sessionNameAskNote
                    : l10n.sessionNameCheckNote,
              ),
      ),
      controls: switch ((choices, shown)) {
        (final options?, _) => Wrap(
          spacing: PindoroSpace.s2,
          runSpacing: PindoroSpace.s1,
          alignment: WrapAlignment.center,
          children: [
            for (final s in options)
              PindoroChip.action(
                label: streetName(s, settings),
                onPressed: () => onPick(s),
              ),
          ],
        ),
        (null, false) => PindoroButton(
          label: l10n.sessionNameShow,
          icon: PindoroGlyph.eye,
          onPressed: onShow,
        ),
        (null, true) => Row(
          spacing: PindoroSpace.s3,
          children: [
            if (canSpeak)
              PindoroIconButton(
                glyph: PindoroGlyph.soundOn,
                semanticLabel: l10n.lessonHearName,
                size: PindoroSize.buttonLg,
                onPressed: () =>
                    unawaited(ref.read(speechProvider).speak(name, language)),
              ),
            Expanded(
              child: PindoroButton(
                label: l10n.sessionNameForgot,
                variant: PindoroButtonVariant.secondary,
                onPressed: () => onRate(false),
              ),
            ),
            Expanded(
              child: PindoroButton(
                label: l10n.sessionNameKnew,
                tier: Tier.great,
                onPressed: () => onRate(true),
              ),
            ),
          ],
        ),
      },
      result: switch ((task.result, picked)) {
        (final tier?, final picked?) => TaskResult(
          resultKey: play.index,
          tier: tier,
          chip: chip,
          sentence: picked == street
              ? l10n.sessionNameRight(name)
              : l10n.sessionNameWrong(name, streetName(picked, settings)),
          onNext: onNext,
        ),
        _ => null,
      },
    );
  }
}
