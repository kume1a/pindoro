import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/core/speech.dart';
import 'package:pindoro/features/lesson/ui/lesson_controller.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/map/ui/widgets/question_plate.dart';
import 'package:pindoro/features/map/ui/widgets/street_facts.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

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
    final settings = ref.watch(settingsProvider).value;
    final street = step.street;
    final cards = play.run.steps.whereType<CardStep>().length;
    final last = play.run.steps[play.run.index + 1] is! CardStep;
    final others = ref.watch(cityStreetsProvider).value?.values ?? const [];
    final intro = streetFacts(context, street, others, play.cityCenter);
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
                child: IntroSheet(
                  title: l10n.lessonWhereTitle,
                  where: intro.where,
                  facts: intro.facts,
                  regionLabel: l10n.sessionIntroRegion,
                  hearLabel: l10n.lessonHearName,
                  onHear: canSpeak
                      ? () {
                          ref.read(feedbackProvider).tap();
                          unawaited(
                            ref.read(speechProvider).speak(name, language),
                          );
                        }
                      : null,
                  gotItLabel: last ? l10n.lessonStartTest : l10n.revealGotIt,
                  onGotIt: () {
                    ref.read(feedbackProvider).tap();
                    unawaited(onNext());
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
