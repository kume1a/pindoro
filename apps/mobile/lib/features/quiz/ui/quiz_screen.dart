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
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/core/toast.dart';
import 'package:pindoro/features/map/ui/pin_drop_view.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro/features/quiz/ui/round_controller.dart';
import 'package:pindoro/features/quiz/ui/setup_states.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Plays a round: resumes [roundId], retries [retryOf]'s missed streets,
/// plays the [pitStop], or starts one from the saved area and difficulty.
/// Setup states, the question and the reveal are one route.
class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({
    super.key,
    this.roundId,
    this.retryOf,
    this.pitStop = false,
  });

  final String? roundId;
  final String? retryOf;
  final bool pitStop;

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
      above: PinDropView.confirmInset(context),
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
          above: PinDropView.confirmInset(context),
        );
      }
      return;
    }
    final retryOf = widget.retryOf;
    if (retryOf != null) return controller.startRetry(retryOf);
    final settings = await ref.read(settingsDaoProvider).read();
    if (widget.pitStop) return controller.startPitStop(settings.difficulty);
    await controller.start(settings.area, settings.difficulty);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(roundControllerProvider, (previous, next) {
      switch (next) {
        case RoundFinished(:final roundId):
          context.go(Routes.resultsOf(roundId));
        case RoundNothingDue():
          context.go(Routes.pitStop);
        case RoundRevealed(:final answer) when previous is! RoundRevealed:
          _announce(context, answer);
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

  void _announce(BuildContext context, Answer answer) {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(roundControllerProvider.notifier);
    final feedback = ref.read(feedbackProvider);
    final round = play.round;
    final revealed = switch (play) {
      final RoundRevealed r => r,
      RoundAsking() => null,
    };
    final coach =
        revealed == null &&
        play.pin == null &&
        round.index == 0 &&
        (ref.watch(_firstQuestionEverProvider).value ?? false);
    final answer = revealed?.answer;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave(context, ref));
      },
      child: PinDropView(
        area: round.shape,
        questionKey: round.currentId,
        street: round.current,
        retryDistance: round.previousDistanceM[round.currentId],
        pin: play.pin,
        coach: coach,
        topBar: _TopBar(round, onLeave: () => _leave(context, ref)),
        reveal: revealed == null || answer == null
            ? null
            : (
                key: answer.id,
                tier: answer.tier,
                xp: answer.xp,
                distanceM: answer.distanceM,
                pin: revealed.pin,
                nearest: revealed.nearest,
                chips: [
                  if (answer.tier == Tier.perfect && round.perfects > 1)
                    Pill(label: l10n.revealPerfectRepeat(round.perfects)),
                  if (round.streak >= 2)
                    Pill(label: l10n.revealStreak(round.streak)),
                  if (isRetryTier(answer.tier))
                    PitStopChip(l10n.revealToPitStop),
                ],
                action: answer.tier == Tier.miss
                    ? l10n.revealGotIt
                    : round.isLast
                    ? l10n.revealSeeResults
                    : l10n.commonNext,
              ),
        celebration: answer == null
            ? null
            : celebrationFor(
                answer.tier,
                perfectsThisRound: round.perfects,
                inARow: round.streak,
              ),
        onPin: (at) {
          feedback.pinDrop();
          controller.placePin(at);
        },
        onConfirm: () {
          feedback.confirm();
          unawaited(controller.confirm());
        },
        onNext: controller.next,
      ),
    );
  }

  /// Asks before leaving; the round stays saved at the next unanswered
  /// question. After the last answer the round is already finished, so
  /// leaving goes to its results.
  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final round = play.round;
    final controller = ref.read(roundControllerProvider.notifier);
    if (play is RoundRevealed && round.isLast) return controller.next();
    final l10n = context.l10n;
    final resumesAt = play is RoundRevealed ? round.number + 1 : round.number;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => PindoroDialog(
        title: l10n.quizLeaveTitle,
        body: l10n.quizLeaveBody(
          resumesAt,
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

/// Leave, the question bar and the round's XP.
class _TopBar extends StatelessWidget {
  const _TopBar(this.round, {required this.onLeave});

  final RoundContext round;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final xp = formatNumber(round.xp);
    return Row(
      spacing: PindoroSpace.s3,
      children: [
        PindoroIconButton(
          glyph: PindoroGlyph.close,
          semanticLabel: l10n.a11yLeaveRound,
          onPressed: onLeave,
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
          label: xp,
          icon: PindoroGlyph.xp,
          iconColor: PindoroTheme.of(context).colors.xpFill,
          floating: true,
          semanticLabel: l10n.a11yRoundXp(xp),
        ),
      ],
    );
  }
}
