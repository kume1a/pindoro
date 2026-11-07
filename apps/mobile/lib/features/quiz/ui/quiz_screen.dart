import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/online.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/core/toast.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro/features/quiz/ui/round_controller.dart';
import 'package:pindoro/features/quiz/ui/setup_states.dart';
import 'package:pindoro/features/quiz/ui/widgets/question_plate.dart';
import 'package:pindoro/features/quiz/ui/widgets/reticle.dart';
import 'package:pindoro/features/quiz/ui/widgets/round_reveal.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Plays a round: resumes [roundId], retries [retryOf]'s missed streets, or
/// starts one from the saved area and difficulty. Setup states, the
/// question and the reveal are one route.
class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({super.key, this.roundId, this.retryOf});

  final String? roundId;
  final String? retryOf;

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  bool _offlineToastShown = false;

  /// Says once per round that the map may have gaps; the round itself only
  /// needs what it loaded at the start.
  Future<void> _checkOnline() async {
    if (_offlineToastShown || await isOnline() || !mounted) return;
    _offlineToastShown = true;
    showToast(
      context,
      context.l10n.toastOffline,
      above: _RoundView._confirmInset(context),
    );
  }

  @override
  void initState() {
    super.initState();
    // Providers can't change while the tree builds; begin right after.
    Future.microtask(_begin);
  }

  Future<void> _begin() async {
    final controller = ref.read(roundControllerProvider.notifier);
    final roundId = widget.roundId;
    if (roundId != null) {
      await controller.resume(roundId);
      if (!mounted) return;
      if (ref.read(roundControllerProvider) case RoundAsking(
        :final round,
      ) when round.index > 0) {
        showToast(
          context,
          context.l10n.toastRoundResumed(round.number),
          above: _RoundView._confirmInset(context),
        );
      }
      return;
    }
    final retryOf = widget.retryOf;
    if (retryOf != null) return controller.startRetry(retryOf);
    final settings = await ref.read(settingsDaoProvider).read();
    await controller.start(
      settings.area,
      settings.lastDifficulty ?? Difficulty.easy,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(roundControllerProvider, (previous, next) {
      switch (next) {
        case RoundFinished(:final roundId):
          context.go(Routes.resultsOf(roundId));
        case RoundRevealed(:final round, :final answer)
            when previous is! RoundRevealed:
          _announce(context, round, answer);
        case RoundAsking() when previous is! RoundAsking:
          unawaited(_checkOnline());
        default:
      }
    });
    return switch (ref.watch(roundControllerProvider)) {
      final RoundInPlay play => _RoundView(play),
      final RoundState setup => SetupStates(state: setup, onRetry: _begin),
    };
  }

  void _announce(BuildContext context, RoundContext round, Answer answer) {
    final l10n = context.l10n;
    ref.read(feedbackProvider).tier(answer.tier);
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        l10n.a11yReveal(
          tierLabel(l10n, answer.tier),
          formatDistance(answer.distanceM, l10n),
          formatNumber(answer.xp),
        ),
        Directionality.of(context),
      ),
    );
  }
}

/// Whether this is the very first question the player sees (coach mark).
final _firstQuestionEverProvider = FutureProvider.autoDispose<bool>(
  (ref) async => !await ref.watch(progressDaoProvider).hasAnswered(),
);

class _RoundView extends ConsumerWidget {
  const _RoundView(this.play);

  final RoundInPlay play;

  /// Space the Confirm button takes at the bottom of the map.
  static double _confirmInset(BuildContext context) =>
      PindoroSize.buttonLg + PindoroElevation.e2 + bottomActionGap(context);

  /// The reveal sheet's rough height (it keeps half the map visible).
  static double _sheetInset(BuildContext context) =>
      240 + MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(roundControllerProvider.notifier);
    final feedback = ref.read(feedbackProvider);
    final settings = ref.watch(settingsProvider).value;
    final round = play.round;
    final pin = play.pin;
    final revealed = switch (play) {
      final RoundRevealed r => r,
      RoundAsking() => null,
    };
    final street = round.current;
    final coach =
        revealed == null &&
        pin == null &&
        round.index == 0 &&
        (ref.watch(_firstQuestionEverProvider).value ?? false);
    final topInset = MediaQuery.paddingOf(context).top + 180;
    final celebration = revealed == null
        ? null
        : celebrationFor(
            revealed.answer.tier,
            perfectsThisRound: round.perfects,
            inARow: round.streak,
          );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmLeave(context, round));
      },
      child: Scaffold(
        body: Stack(
          children: [
            ref.watch(pindoroMapBuilderProvider)(
              PindoroMap(
                area: round.shape,
                pin: pin,
                truth: revealed?.round.current.geometry,
                measure: revealed == null
                    ? null
                    : (
                        from: pin!,
                        to: revealed.nearest,
                        label: formatDistance(revealed.answer.distanceM, l10n),
                      ),
                onTap: revealed == null
                    ? (at) {
                        feedback.pinDrop();
                        controller.placePin(at);
                        final inside = boundaryContains(
                          round.shape.boundary,
                          at,
                        );
                        if (!inside) {
                          showToast(
                            context,
                            l10n.toastPinOutsideArea,
                            above: _confirmInset(context),
                          );
                        }
                      }
                    : null,
                topInset: topInset,
                bottomInset: revealed == null
                    ? _confirmInset(context)
                    : _sheetInset(context),
                showControls: revealed == null,
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
                    Row(
                      spacing: PindoroSpace.s3,
                      children: [
                        PindoroIconButton(
                          glyph: PindoroGlyph.close,
                          semanticLabel: l10n.a11yLeaveRound,
                          onPressed: () => _confirmLeave(context, round),
                        ),
                        Expanded(
                          child: QuestionBar(
                            tiers: [for (final a in round.answers) a.tier],
                            total: round.total,
                            semanticLabel: l10n.commonQuestionProgress(
                              round.number,
                              round.total,
                            ),
                          ),
                        ),
                        Pill(
                          label: formatNumber(round.xp),
                          icon: PindoroGlyph.xp,
                          iconColor: PindoroTheme.of(context).colors.xpFill,
                          floating: true,
                          semanticLabel: l10n.a11yRoundXp(
                            formatNumber(round.xp),
                          ),
                        ),
                      ],
                    ),
                    AnimatedSwitcher(
                      duration: PindoroMotion.durationBase,
                      reverseDuration: PindoroMotion.durationFast,
                      switchInCurve: PindoroMotion.easeDecelerate,
                      switchOutCurve: PindoroMotion.easeAccelerate,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: animation.drive(
                            Tween(
                              begin: const Offset(0, 0.15),
                              end: Offset.zero,
                            ),
                          ),
                          child: child,
                        ),
                      ),
                      child: QuestionPlate(
                        key: ValueKey(round.currentId),
                        street: street,
                        settings: settings,
                        compact: revealed != null,
                        retryDistance: round.previousDistanceM[round.currentId],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (revealed == null)
              Positioned(
                left: PindoroSpace.s4,
                right: PindoroSpace.s4,
                bottom: bottomActionGap(context),
                child: Semantics(
                  label: pin == null ? l10n.a11yConfirmDisabled : null,
                  child: PindoroButton(
                    label: l10n.commonConfirm,
                    onPressed: pin == null
                        ? null
                        : () {
                            feedback.confirm();
                            unawaited(controller.confirm());
                          },
                  ),
                ),
              )
            else
              Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: RiseIn(
                    key: ValueKey(revealed.answer.id),
                    child: RoundReveal(
                      revealed: revealed,
                      onNext: controller.next,
                    ),
                  ),
                ),
              ),
            if (celebration != null)
              Positioned.fill(
                child: Celebration(
                  key: ValueKey(revealed!.answer.id),
                  size: celebration,
                  burstCenter: const Alignment(-0.78, 0.5),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLeave(BuildContext context, RoundContext round) async {
    final l10n = context.l10n;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => PindoroDialog(
        title: l10n.quizLeaveTitle,
        body: l10n.quizLeaveBody(
          round.answers.length + 1,
          round.total,
          formatNumber(round.xp),
        ),
        primary: l10n.quizLeaveKeepPlaying,
        secondary: l10n.quizLeaveConfirm,
      ),
    );
    if ((leave ?? false) && context.mounted) context.go(Routes.home);
  }
}
