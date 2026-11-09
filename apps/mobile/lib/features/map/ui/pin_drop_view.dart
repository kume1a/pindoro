import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/core/toast.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/map/ui/widgets/question_plate.dart';
import 'package:pindoro/features/map/ui/widgets/reticle.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// A confirmed pin: its tier, XP and distance, where it was and the nearest
/// point of the street (the measure line), the sheet's [chips] and the
/// [action] label (Next, Got it, See results).
typedef PinReveal = ({
  Object key,
  Tier tier,
  int xp,
  double distanceM,
  LatLng pin,
  LatLng nearest,
  List<Widget> chips,
  String action,
});

/// One pin drop, shared by Free play rounds and lessons: the map framed on
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

  /// Space the Confirm button takes at the bottom of the map.
  static double confirmInset(BuildContext context) =>
      PindoroSize.buttonLg + PindoroElevation.e2 + bottomActionGap(context);

  /// The reveal sheet's rough height (it keeps half the map visible).
  static double _sheetInset(BuildContext context) =>
      240 + MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final reveal = this.reveal;
    final topInset = MediaQuery.paddingOf(context).top + 180;
    return Scaffold(
      body: Stack(
        children: [
          ref.watch(pindoroMapBuilderProvider)(
            PindoroMap(
              area: area,
              pin: pin,
              truth: reveal == null ? null : street.geometry,
              measure: reveal == null
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
                          above: confirmInset(context),
                        );
                      }
                    }
                  : null,
              topInset: topInset,
              bottomInset: reveal == null
                  ? confirmInset(context)
                  : _sheetInset(context),
              showControls: reveal == null,
            ),
          ),
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
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(PindoroSpace.s4),
              child: Column(
                spacing: PindoroSpace.s4,
                children: [
                  topBar,
                  RiseSwitcher(
                    child: QuestionPlate(
                      key: ValueKey(questionKey),
                      street: street,
                      settings: settings,
                      compact: reveal != null,
                      retryDistance: retryDistance,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (reveal == null)
            Positioned(
              left: PindoroSpace.s4,
              right: PindoroSpace.s4,
              bottom: bottomActionGap(context),
              child: Semantics(
                label: pin == null ? l10n.a11yConfirmDisabled : null,
                child: PindoroButton(
                  label: l10n.commonConfirm,
                  onPressed: pin == null ? null : onConfirm,
                ),
              ),
            )
          else
            Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: RiseIn(
                  key: ValueKey(reveal.key),
                  child: PinRevealSheet(reveal: reveal, onNext: onNext),
                ),
              ),
            ),
          if (celebration != null && reveal != null)
            Positioned.fill(
              child: Celebration(
                key: ValueKey(reveal.key),
                size: celebration!,
                burstCenter: const Alignment(-0.78, 0.5),
              ),
            ),
        ],
      ),
    );
  }
}

/// The reveal sheet: the tier, the XP counting up, the distance sentence
/// (a Miss says which way the street lies), the chips and the action.
class PinRevealSheet extends StatelessWidget {
  const PinRevealSheet({super.key, required this.reveal, required this.onNext});

  final PinReveal reveal;
  final Future<void> Function() onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final distance = formatDistance(reveal.distanceM, l10n);
    final sentence = switch (reveal.tier) {
      Tier.perfect => l10n.tierPerfectSentence,
      Tier.great => l10n.tierGreatSentence(distance),
      Tier.close => l10n.tierCloseSentence(distance),
      Tier.miss => l10n.tierMissSentence(
        distance,
        l10n.revealMissDirection(compassPoint(reveal.pin, reveal.nearest).name),
      ),
    };
    return CountUp(
      value: reveal.xp,
      builder: (context, xp) => RevealSheet(
        tier: reveal.tier,
        label: tierLabel(l10n, reveal.tier),
        sentence: sentence,
        xpLabel: reveal.tier == Tier.miss
            ? null
            : l10n.commonXp(formatNumber(xp)),
        chips: reveal.chips,
        mascot: Pindo(switch (reveal.tier) {
          Tier.perfect || Tier.great => PindoExpression.cheering,
          Tier.close => PindoExpression.happy,
          Tier.miss => PindoExpression.encouraging,
        }, height: 80),
        action: PindoroButton(
          tier: reveal.tier,
          label: reveal.action,
          onPressed: () => unawaited(onNext()),
        ),
      ),
    );
  }
}
