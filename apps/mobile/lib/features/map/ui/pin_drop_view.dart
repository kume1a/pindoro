import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/core/toast.dart';
import 'package:pindoro/features/map/ui/map_layout.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/map/ui/widgets/question_plate.dart';
import 'package:pindoro/features/map/ui/widgets/reticle.dart';
import 'package:pindoro/features/map/ui/widgets/tier_reveal.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// A confirmed pin: its tier and distance, where it was and the nearest
/// point of the street (the measure line), the sheet's [chips] and the
/// [action] label (Next, Got it, See results).
typedef PinReveal = ({
  Object key,
  Tier tier,
  double distanceM,
  LatLng pin,
  LatLng nearest,
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
    this.coach = false,
    this.celebration,
    this.frame,
    this.known = const [],
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

  /// The first question ever: the reticle and the coach bubble.
  final bool coach;
  final CelebrationSize? celebration;

  /// What the camera frames while asking, instead of the whole area (a v3
  /// retrieval 1 frames the street's district).
  final List<LatLng>? frame;

  /// Known streets named on the reveal (v3).
  final List<MapLabel> known;

  /// The reveal is a Mix-up: the pin hit this confusable street (v3).
  final MapLabel? mixUp;

  /// The reveal's header chip instead of XP: the next-review chip (v3).
  final Widget? headerChip;

  /// Guess first: the plate's sub-line and the note above Confirm guess.
  final ({String subline, String note})? guess;

  /// The plate's ask row instead of "Drop a pin on".
  final String? prompt;

  /// A tertiary button under Confirm that moves on without an answer
  /// ("I don't know this one").
  final ({String label, VoidCallback onSkip})? skip;

  /// Space the Confirm button takes at the bottom of the map (for toasts).
  static double confirmInset(BuildContext context) =>
      PindoroButton.height + PindoroElevation.e2 + bottomActionGap(context);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final mapOf = ref.watch(pindoroMapBuilderProvider);
    final reveal = this.reveal;
    final celebration = this.celebration;
    return Scaffold(
      body: MapLayout(
        map: (insets) => mapOf(
          PindoroMap(
            area: area,
            pin: pin,
            truth: reveal == null ? null : street.geometry,
            measure: reveal == null || mixUp != null
                ? null
                : (
                    from: reveal.pin,
                    to: reveal.nearest,
                    label: formatDistance(reveal.distanceM, l10n),
                  ),
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
            known: reveal == null ? const [] : known,
            hit: reveal == null ? null : mixUp,
          ),
        ),
        behind: [
          if (coach) ...[
            const Center(child: Reticle()),
            Align(
              alignment: const Alignment(0, -0.25),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: PindoroSpace.s4,
                ),
                child: CoachBubble(
                  title: l10n.quizCoachTitle,
                  body: l10n.quizCoachBody,
                ),
              ),
            ),
          ],
        ],
        top: Column(
          spacing: PindoroSpace.s4,
          children: [
            topBar,
            RiseSwitcher(
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
          ],
        ),
        bottom: reveal == null
            ? Padding(
                padding: EdgeInsets.fromLTRB(
                  PindoroSpace.s4,
                  0,
                  PindoroSpace.s4,
                  bottomActionGap(context),
                ),
                child: Column(
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
                ),
              )
            : RevealDock(
                revealKey: reveal.key,
                sheet: PinRevealSheet(
                  reveal: reveal,
                  onNext: onNext,
                  mixUp: mixUp,
                  headerChip: headerChip,
                ),
              ),
        front: [
          if ((reveal, celebration) case (final r?, final size?))
            RevealCelebration(revealKey: r.key, size: size),
        ],
      ),
    );
  }
}

/// The reveal sheet: the tier, the XP counting up, the distance sentence
/// (a Miss says which way the street lies), the chips and the action.
class PinRevealSheet extends StatelessWidget {
  const PinRevealSheet({
    super.key,
    required this.reveal,
    required this.onNext,
    this.mixUp,
    this.headerChip,
  });

  final PinReveal reveal;
  final Future<void> Function() onNext;

  /// A Mix-up: Miss colours, "Mix-up" and the street the pin hit.
  final MapLabel? mixUp;
  final Widget? headerChip;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final distance = formatDistance(reveal.distanceM, l10n);
    final direction = l10n.revealMissDirection(
      compassPoint(reveal.pin, reveal.nearest).name,
    );
    final mixUp = this.mixUp;
    final sentence = switch (reveal.tier) {
      _ when mixUp != null => l10n.revealMixUpSentence(mixUp.label, direction),
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
    );
  }
}
