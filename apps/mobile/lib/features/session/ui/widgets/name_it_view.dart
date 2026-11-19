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
/// the map and six names to pick from, then the result.
class NameItView extends ConsumerWidget {
  const NameItView({
    super.key,
    required this.play,
    required this.topBar,
    required this.onPick,
    required this.onNext,
    this.chip,
  });

  final SessionPlaying play;
  final Widget topBar;
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
    final picked = task.picked;
    final mapOf = ref.watch(pindoroMapBuilderProvider);
    return TaskScaffold(
      topBar: topBar,
      map: (insets) => mapOf(
        PindoroMap(
          area: play.area,
          truth: street.geometry,
          frame: play.frame,
          // Asking: places, but none named after the street.
          names: picked == null ? MapNames.asking(street) : MapNames.all,
          topInset: insets.top,
          bottomInset: insets.bottom,
        ),
      ),
      header: RiseSwitcher(
        child: picked != null
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
                title: l10n.sessionNameCheckAsk,
                note: l10n.sessionNameCheckNote,
              ),
      ),
      controls: Wrap(
        spacing: PindoroSpace.s2,
        runSpacing: PindoroSpace.s1,
        alignment: WrapAlignment.center,
        children: [
          for (final s in task.choices)
            PindoroChip.action(
              label: streetName(s, settings),
              onPressed: () => onPick(s),
            ),
        ],
      ),
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
