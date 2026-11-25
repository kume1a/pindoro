import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/google_maps.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/core/toast.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/map/ui/question_scaffold.dart';
import 'package:pindoro/features/map/ui/widgets/question_plate.dart';
import 'package:pindoro/features/map/ui/widgets/tier_reveal.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Where a confirmed pin landed: its distance to the street and the street's nearest point
/// (the measure line).
typedef PinAnswer = ({double distanceM, LatLng pin, LatLng nearest});

/// A revealed question: its tier, the pin's [answer] (null for "I don't know"), the
/// sheet's [chips] and the [action] label (Next, Got it, See results).
typedef PinReveal = ({
  Object key,
  Tier tier,
  PinAnswer? answer,
  List<Widget> chips,
  String action,
});

/// One pin drop, shared by Explore rounds and learning sessions: the map framed on
/// [area], the [topBar] and the street plate, Confirm until [reveal], then
/// the measure and the reveal sheet. A tap drops (or moves) the pin; outside
/// the area a toast says the street is inside it.
class PinDropView extends ConsumerWidget {
  const PinDropView({
    super.key,
    required this.area,
    required this.questionKey,
    required this.street,
    required this.pin,
    required this.reveal,
    required this.topBar,
    required this.onPin,
    required this.onConfirm,
    required this.onNext,
    this.retryDistance,
    this.celebration,
    this.frame,
    this.mixUp,
    this.headerChip,
    this.guess,
    this.prompt,
    this.skip,
  });

  final AreaShape area;

  /// Changes per question, so the plate rises in anew.
  final Object questionKey;
  final NamedStreet street;
  final LatLng? pin;
  final PinReveal? reveal;
  final Widget topBar;
  final ValueChanged<LatLng> onPin;
  final VoidCallback onConfirm;
  final Future<void> Function() onNext;

  /// The "Try again" plate's last distance.
  final double? retryDistance;

  final CelebrationSize? celebration;

  /// What the camera frames while asking, instead of the whole area (a v3
  /// retrieval 1 frames the street's district).
  final List<LatLng>? frame;

  /// The reveal is a Mix-up: the pin hit this confusable street (v3).
  final NamedStreet? mixUp;

  /// The reveal's header chip instead of XP: the next-review chip (v3).
  final Widget? headerChip;

  /// Guess first: the plate's sub-line and the note above Confirm guess.
  final ({String subline, String note})? guess;

  /// The plate's ask row instead of "Drop a pin on".
  final String? prompt;

  /// A tertiary button under Confirm for no answer ("I don't know").
  final ({String label, VoidCallback onSkip})? skip;

  /// Space Confirm and the [skip] under it take at the bottom of the map (for toasts).
  static double confirmInset(BuildContext context) =>
      2 * (PindoroButton.height + PindoroElevation.e2) +
      PindoroSpace.s1 +
      mapActionGap(context);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final mapOf = ref.watch(pindoroMapBuilderProvider);
    final reveal = this.reveal;
    return QuestionScaffold(
      map: (insets) => mapOf(
        PindoroMap(
          area: area,
          pin: pin,
          truth: reveal == null ? null : street.geometry,
          measure: switch (reveal?.answer) {
            final a? when mixUp == null => (
              from: a.pin,
              to: a.nearest,
              label: formatDistance(a.distanceM, l10n),
            ),
            _ => null,
          },
          onTap: reveal == null
              ? (at) {
                  onPin(at);
                  if (!boundaryContains(area.boundary, at)) {
                    showToast(
                      context,
                      l10n.toastPinOutsideArea,
                      above: insets.bottom,
                    );
                  }
                }
              : null,
          topInset: insets.top,
          bottomInset: insets.bottom,
          showControls: reveal == null,
          frame: reveal == null ? frame : null,
          // Asking: places, but none named after the street.
          names: reveal == null ? MapNames.asking(street) : MapNames.all,
          hit: reveal == null ? null : mixUp?.geometry,
        ),
      ),
      topBar: topBar,
      header: RiseSwitcher(
        child: QuestionPlate(
          key: ValueKey((questionKey, guess != null)),
          street: street,
          settings: settings,
          compact: reveal != null,
          retryDistance: retryDistance,
          guess: guess?.subline,
          prompt: prompt,
        ),
      ),
      controls: reveal == null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              spacing: skip == null ? PindoroSpace.s3 : PindoroSpace.s1,
              children: [
                if (guess case (:final note, subline: _))
                  Text(
                    note,
                    textAlign: TextAlign.center,
                    style: PindoroType.bodySm.copyWith(
                      color: PindoroTheme.of(context).colors.textSecondary,
                    ),
                  ),
                Semantics(
                  label: pin == null ? l10n.a11yConfirmDisabled : null,
                  child: PindoroButton(
                    label: guess == null
                        ? l10n.commonConfirm
                        : l10n.sessionConfirmGuess,
                    onPressed: pin == null ? null : onConfirm,
                  ),
                ),
                if (skip case (:final label, :final onSkip))
                  PindoroButton(
                    label: label,
                    variant: PindoroButtonVariant.tertiary,
                    onPressed: onSkip,
                  ),
              ],
            )
          : null,
      result: reveal == null
          ? null
          : _PinResult(
              resultKey: reveal.key,
              celebration: celebration,
              sheet: PinRevealSheet(
                reveal: reveal,
                onNext: onNext,
                mixUp: switch (mixUp) {
                  final m? => streetName(m, settings),
                  null => null,
                },
                headerChip: headerChip,
                streetView: streetSpot(
                  street,
                  reveal.answer?.nearest ?? street.parts.first.midpoint,
                ),
              ),
            ),
    );
  }
}

/// A checked pin's reveal sheet, rising in anew per [resultKey], and its [celebration].
class _PinResult extends QuestionResult {
  const _PinResult({
    required this.resultKey,
    required this.celebration,
    required this.sheet,
  });

  @override
  final Object resultKey;
  @override
  final CelebrationSize? celebration;
  final PinRevealSheet sheet;

  @override
  Widget build(BuildContext context) =>
      RevealDock(revealKey: resultKey, sheet: sheet);
}

/// The reveal sheet: the tier, the distance sentence (a Miss says which way
/// the street lies), the chips, Street View at the answer and the action.
class PinRevealSheet extends StatelessWidget {
  const PinRevealSheet({
    super.key,
    required this.reveal,
    required this.onNext,
    required this.streetView,
    this.mixUp,
    this.headerChip,
  });

  final PinReveal reveal;
  final Future<void> Function() onNext;
  final StreetViewSpot streetView;

  /// A Mix-up: Miss colours, "Mix-up" and the name of the street the pin
  /// hit.
  final String? mixUp;
  final Widget? headerChip;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final answer = reveal.answer;
    if (answer == null) {
      return TierRevealSheet(
        tier: Tier.miss,
        headerChip: headerChip,
        label: l10n.answerDidntKnow,
        sentence: l10n.revealDidntKnowSentence,
        chips: reveal.chips,
        action: reveal.action,
        onNext: onNext,
        streetView: streetView,
      );
    }
    final distance = formatDistance(answer.distanceM, l10n);
    final direction = l10n.revealMissDirection(
      compassPoint(answer.pin, answer.nearest).name,
    );
    final mixUp = this.mixUp;
    final sentence = switch (reveal.tier) {
      _ when mixUp != null => l10n.revealMixUpSentence(mixUp, direction),
      Tier.perfect => l10n.tierPerfectSentence,
      Tier.great => l10n.tierGreatSentence(distance),
      Tier.close => l10n.tierCloseSentence(distance),
      Tier.miss => l10n.tierMissSentence(distance, direction),
    };
    return TierRevealSheet(
      tier: mixUp == null ? reveal.tier : Tier.miss,
      headerChip: headerChip,
      label: mixUp == null ? tierLabel(l10n, reveal.tier) : l10n.revealMixUp,
      sentence: sentence,
      chips: reveal.chips,
      action: reveal.action,
      onNext: onNext,
      streetView: streetView,
    );
  }
}
