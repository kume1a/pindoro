import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/core/speech.dart';
import 'package:pindoro/features/lesson/ui/lesson_controller.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/map/ui/widgets/question_plate.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Crossings per street: counting walks the city's streets, once is enough.
final _crossings = Expando<int>();

/// The card sheet's rough height, so the camera frames the street above it.
const double _sheetInset = 260;

/// "New street · 1 of 4" (canvas R4-20): the map flies to the street and
/// paints it; a sheet says where it is, its length, type and crossings, Hear
/// the name (when the device has a voice for it) and Got it (the last card:
/// Start the test).
class NewStreetCard extends ConsumerWidget {
  const NewStreetCard({
    super.key,
    required this.play,
    required this.step,
    required this.topBar,
    required this.onNext,
  });

  final LessonPlaying play;
  final CardStep step;
  final Widget topBar;
  final Future<void> Function() onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final street = step.street;
    final cards = play.run.steps.whereType<CardStep>().length;
    final last = play.run.steps[play.run.index + 1] is! CardStep;
    final type = roadTypeOf(street.parts.first.roadClass);
    final others = ref.watch(cityStreetsProvider).value?.values ?? const [];
    final crossings = _crossings[street] ??= crossingCount(street, {...others});
    final where = l10n.lessonWhere(
      l10n.lessonRoadType(type.name),
      directionFromCentre(street, play.cityCenter)?.name ?? 'centre',
    );
    final facts = l10n.lessonFacts(
      crossings,
      formatSize(street.lengthM, l10n),
      l10n.lessonRoadTypeWord(type.name),
    );
    final name = streetName(street, settings);
    final language = speechLanguage(name);
    final canSpeak = ref.watch(canSpeakProvider(language)).value ?? false;
    return Scaffold(
      body: Stack(
        children: [
          ref.watch(pindoroMapBuilderProvider)(
            PindoroMap(
              area: play.shape,
              truth: street.geometry,
              topInset: MediaQuery.paddingOf(context).top + 180,
              bottomInset: _sheetInset + MediaQuery.paddingOf(context).bottom,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(PindoroSpace.s4),
              child: Column(
                spacing: PindoroSpace.s4,
                children: [
                  topBar,
                  RiseSwitcher(
                    child: StreetPlate(
                      name,
                      key: ValueKey(play.run.index),
                      prompt: l10n.lessonNewStreet(step.number, cards),
                      promptGlyph: PindoroGlyph.signpost,
                      subline: otherScript(street, settings),
                      semanticLabel:
                          '${l10n.lessonNewStreet(step.number, cards)}: $name',
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
              child: RiseIn(
                key: ValueKey(play.run.index),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: c.surfaceRaised,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(PindoroRadius.r2xl),
                    ),
                    border: Border(
                      top: BorderSide(
                        color: c.lineBase,
                        width: PindoroStroke.base,
                      ),
                    ),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    PindoroSpace.s5,
                    PindoroSpace.s5,
                    PindoroSpace.s5,
                    bottomActionGap(context),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: PindoroSpace.s2,
                    children: [
                      Text(
                        l10n.lessonWhereTitle,
                        style: PindoroType.titleSm.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                      Text(
                        where,
                        style: PindoroType.bodyMd.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                      Text(
                        facts,
                        style: PindoroType.labelMd.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                      const SizedBox(height: PindoroSpace.s2),
                      Row(
                        spacing: PindoroSpace.s3,
                        children: [
                          if (canSpeak)
                            PindoroIconButton(
                              glyph: PindoroGlyph.soundOn,
                              semanticLabel: l10n.lessonHearName,
                              size: PindoroSize.buttonLg,
                              onPressed: () {
                                ref.read(feedbackProvider).tap();
                                unawaited(
                                  ref
                                      .read(speechProvider)
                                      .speak(name, language),
                                );
                              },
                            ),
                          Expanded(
                            child: PindoroButton(
                              label: last
                                  ? l10n.lessonStartTest
                                  : l10n.revealGotIt,
                              onPressed: () {
                                ref.read(feedbackProvider).tap();
                                unawaited(onNext());
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
