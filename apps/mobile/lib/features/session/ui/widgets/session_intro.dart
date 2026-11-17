import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/google_maps.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/core/speech.dart';
import 'package:pindoro/features/map/ui/map_layout.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/map/ui/widgets/question_plate.dart';
import 'package:pindoro/features/map/ui/widgets/street_facts.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/session/ui/session_controller.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// A new street (SessionScreen `intro`): the map paints it and names the
/// streets around it and the places in view, the plate says "New street · 1
/// of 10" and the
/// Intro sheet says where it is. A leech comes back the same way, beside the
/// street it is mixed up with ([contrast], cobalt) and with a note field
/// (SPEC §4).
class SessionIntro extends ConsumerStatefulWidget {
  const SessionIntro({
    super.key,
    required this.play,
    required this.labels,
    required this.places,
    required this.topBar,
    required this.onGotIt,
    this.contrast,
  });

  final SessionPlaying play;
  final List<MapLabel> labels;
  final List<MapPlace> places;
  final Widget topBar;

  /// Got it, with a leech's note as typed.
  final ValueChanged<String?> onGotIt;
  final MapLabel? contrast;

  @override
  ConsumerState<SessionIntro> createState() => _SessionIntroState();
}

class _SessionIntroState extends ConsumerState<SessionIntro> {
  late final _note = TextEditingController(text: widget.play.note);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final play = widget.play;
    final topBar = widget.topBar;
    final contrast = widget.contrast;
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final street = play.street;
    final others = ref.watch(cityStreetsProvider).value?.values ?? const [];
    final city = ref.watch(packRepositoryProvider).value?.city();
    final intro = streetFacts(
      context,
      street,
      others,
      city?.center ?? street.parts.first.midpoint,
    );
    final name = streetName(street, settings);
    final language = speechLanguage(name);
    final canSpeak = ref.watch(canSpeakProvider(language)).value ?? false;
    final prompt = play.leech
        ? l10n.sessionLeechPrompt
        : l10n.lessonNewStreet(play.newIndex, play.newTotal);
    final mapOf = ref.watch(pindoroMapBuilderProvider);
    return Scaffold(
      body: MapLayout(
        map: (insets) => mapOf(
          PindoroMap(
            area: play.area,
            truth: street.geometry,
            labels: widget.labels,
            places: widget.places,
            hit: contrast,
            topInset: insets.top,
            bottomInset: insets.bottom,
          ),
        ),
        top: Column(
          spacing: PindoroSpace.s2,
          children: [
            topBar,
            RiseSwitcher(
              child: StreetPlate(
                name,
                key: ValueKey(play.index),
                prompt: prompt,
                promptGlyph: PindoroGlyph.signpost,
                subline: otherScript(street, settings),
                semanticLabel: '$prompt: $name',
              ),
            ),
          ],
        ),
        bottom: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: RiseIn(
            key: ValueKey(play.index),
            child: IntroSheet(
              title: l10n.lessonWhereTitle,
              where: intro.where,
              facts: intro.facts,
              etymology: street.parts.first.etymology,
              family: switch (play.family) {
                final f? => l10n.sessionFamily(
                  streetName(f.parent, settings),
                  familyCounts(l10n, f.children),
                ),
                null => null,
              },
              regionLabel: l10n.sessionIntroRegion,
              hearLabel: l10n.lessonHearName,
              onHear: canSpeak
                  ? () {
                      ref.read(feedbackProvider).tap();
                      unawaited(ref.read(speechProvider).speak(name, language));
                    }
                  : null,
              streetViewLabel: l10n.streetView,
              onStreetView: () {
                ref.read(feedbackProvider).tap();
                final spot = streetSpot(street, street.parts.first.midpoint);
                unawaited(GoogleMaps.open(GoogleMaps.streetView(spot)));
              },
              extra: [
                if (contrast != null)
                  StatChip(
                    label: l10n.sessionLeechContrast(contrast.label),
                    glyph: PindoroGlyph.reroute,
                  ),
                if (play.leech)
                  SearchField(
                    controller: _note,
                    placeholder: l10n.sessionLeechNoteHint,
                    clearLabel: l10n.commonClear,
                    glyph: PindoroGlyph.edit,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.sentences,
                  ),
              ],
              gotItLabel: l10n.revealGotIt,
              onGotIt: () {
                ref.read(feedbackProvider).tap();
                widget.onGotIt(play.leech ? _note.text : null);
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// "9 lanes, 6 dead ends": a family's children by kind, the kinds it has.
String familyCounts(AppLocalizations l10n, Map<FamilyKind, int> children) => [
  for (final MapEntry(key: kind, value: count)
      in children.entries.toList()
        ..sort((a, b) => a.key.index.compareTo(b.key.index)))
    switch (kind) {
      FamilyKind.lane => l10n.familyLanes(count),
      FamilyKind.deadEnd => l10n.familyDeadEnds(count),
      FamilyKind.passage => l10n.familyPassages(count),
    },
].join(', ');
