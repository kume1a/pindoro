import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/feedback.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/google_maps.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/ui/junction_name.dart';
import 'package:pindoro/features/learning/ui/landmark_glyph.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/map/ui/widgets/street_view_button.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/session/ui/session_controller.dart';
import 'package:pindoro/features/session/ui/widgets/cant_find_it_chip.dart';
import 'package:pindoro/features/session/ui/widgets/intro_scaffold.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// A new place (SPEC §16.18), before it is ever asked: the map marks it in
/// yellow with every street and place named, the plate says
/// "New place · 1 of 3", and the Intro sheet says where it is, with Street
/// View to see what it looks like, and "Can't find it?" when it isn't there.
class PlaceIntro extends ConsumerWidget {
  const PlaceIntro({
    super.key,
    required this.play,
    required this.question,
    required this.topBar,
    required this.onGotIt,
    required this.onHide,
  });

  final SessionPlaying play;
  final LandmarkQuestion question;
  final Widget topBar;
  final VoidCallback onGotIt;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final landmark = question.landmark;
    final name = placeName(l10n, question, settings);
    final prompt = l10n.sessionNewPlace(play.newIndex, play.newTotal);
    final street = play.street;
    final graph = ref.watch(packRepositoryProvider).value?.roadGraph();
    final streets = ref.watch(cityStreetsProvider).value ?? const {};
    final junction = switch ((graph, question.junction)) {
      (final g?, final j?) => junctionName(g, j, streets, settings),
      _ => null,
    };
    final mapOf = ref.watch(pindoroMapBuilderProvider);
    return IntroScaffold(
      stepKey: play.index,
      map: (insets) => mapOf(
        PindoroMap(
          area: play.area,
          truthPoint: landmark.at,
          truth: question.outlineLines,
          names: MapNames.all,
          topInset: insets.top,
          bottomInset: insets.bottom,
        ),
      ),
      topBar: topBar,
      plate: StreetPlate(
        name,
        prompt: prompt,
        promptGlyph: landmarkGlyph(landmark.kind),
        subline: landmarkKindName(l10n, landmark.kind),
        semanticLabel: '$prompt: $name',
      ),
      sheet: IntroSheet(
        title: l10n.lessonWhereTitle,
        where: junction == null
            ? l10n.placeOnStreetSentence(streetName(street, settings))
            : l10n.placeAtJunction(junction),
        facts: landmarkKindName(l10n, landmark.kind),
        extra: [CantFindItChip(name: name, onHide: onHide)],
        regionLabel: l10n.placeIntroRegion,
        streetViewLabel: l10n.streetView,
        onStreetView: () =>
            StreetViewButton.open(ref, placeSpot(street, landmark.at)),
        gotItLabel: l10n.revealGotIt,
        onGotIt: () {
          ref.read(feedbackProvider).tap();
          onGotIt();
        },
      ),
    );
  }
}
