import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

import '../../app/database.dart';
import '../../app/format.dart';
import '../../app/page_scaffold.dart';
import '../../app/router.dart';
import '../../app/settings.dart';
import '../../app/toast.dart';
import '../../l10n/app_localizations.dart';
import '../map/pindoro_map.dart';
import 'round_controller.dart';
import 'setup_states.dart';

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
    final settings = await ref.read(databaseProvider).readSettings();
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
          formatDistance(answer.distanceM, Localizations.localeOf(context)),
          formatNumber(answer.xp),
        ),
        Directionality.of(context),
      ),
    );
  }
}

String tierLabel(AppLocalizations l10n, Tier tier) => switch (tier) {
  Tier.perfect => l10n.tierPerfect,
  Tier.great => l10n.tierGreat,
  Tier.close => l10n.tierClose,
  Tier.miss => l10n.tierMiss,
};

/// Whether this is the very first question the player sees (coach mark).
final _firstQuestionEverProvider = FutureProvider.autoDispose<bool>(
  (ref) async => !await ref.watch(databaseProvider).hasAnswered(),
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
        : celebrationFor(revealed.answer.tier);

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
                measure: revealed == null ? null : (pin!, revealed.nearest),
                onTap: revealed == null
                    ? (at) {
                        feedback.pinDrop();
                        controller.placePin(at);
                        final inside = round.shape.boundary.any(
                          (polygon) => polygonContains(polygon, at),
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
              const Center(child: _Reticle()),
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
                      child: _Plate(
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
                    child: _Reveal(revealed: revealed, onNext: controller.next),
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

class _Plate extends StatelessWidget {
  const _Plate({
    super.key,
    required this.street,
    required this.settings,
    required this.compact,
    this.retryDistance,
  });

  final NamedStreet street;
  final Settings? settings;
  final bool compact;
  final double? retryDistance;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final english = settings?.streetNames == StreetNameMode.english;
    final name = settings?.streetName(street) ?? street.name;
    // The other script on the sub-line: English under a local name, the local
    // name under an English one.
    final other = english
        ? (name == street.name ? null : street.name)
        : street.nameEn;
    final distance = retryDistance == null
        ? null
        : l10n.quizRetryPreviousDistance(
            formatDistance(retryDistance!, Localizations.localeOf(context)),
          );
    return StreetPlate(
      name,
      compact: compact,
      prompt: retryDistance == null ? l10n.quizPrompt : l10n.quizRetryPrompt,
      promptGlyph: retryDistance == null
          ? PindoroGlyph.pin
          : PindoroGlyph.reroute,
      subline: [?other, ?distance].join(' · ').nullIfEmpty,
      semanticLabel: other == null
          ? l10n.a11yFindStreetName(name)
          : l10n.a11yFindStreet(name, other),
    );
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

class _Reveal extends StatelessWidget {
  const _Reveal({required this.revealed, required this.onNext});

  final RoundRevealed revealed;
  final Future<void> Function() onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final answer = revealed.answer;
    final distance = formatDistance(
      answer.distanceM,
      Localizations.localeOf(context),
    );
    final sentence = switch (answer.tier) {
      Tier.perfect => l10n.tierPerfectSentence,
      Tier.great => l10n.tierGreatSentence(distance),
      Tier.close => l10n.tierCloseSentence(distance),
      Tier.miss => l10n.tierMissSentence(
        distance,
        l10n.revealMissDirection(
          compassPoint(revealed.pin!, revealed.nearest).name,
        ),
      ),
    };
    return CountUp(
      value: answer.xp,
      builder: (context, xp) => _sheet(l10n, sentence, xp),
    );
  }

  Widget _sheet(AppLocalizations l10n, String sentence, int xp) {
    final answer = revealed.answer;
    final round = revealed.round;
    return RevealSheet(
      tier: answer.tier,
      label: tierLabel(l10n, answer.tier),
      sentence: sentence,
      xpLabel: answer.tier == Tier.miss
          ? null
          : l10n.commonXp(formatNumber(xp)),
      chips: [if (round.streak >= 2) l10n.revealStreak(round.streak)],
      mascot: Pindo(switch (answer.tier) {
        Tier.perfect || Tier.great => PindoExpression.cheering,
        Tier.close => PindoExpression.happy,
        Tier.miss => PindoExpression.encouraging,
      }, height: 80),
      action: PindoroButton(
        tier: answer.tier,
        label: answer.tier == Tier.miss
            ? l10n.revealGotIt
            : round.isLast
            ? l10n.revealSeeResults
            : l10n.commonNext,
        onPressed: () => unawaited(onNext()),
      ),
    );
  }
}

/// Dashed cobalt ring at the map centre: where a first tap would land.
class _Reticle extends StatelessWidget {
  const _Reticle();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      size: const Size.square(48),
      painter: _ReticlePainter(PindoroTheme.of(context).colors),
    ),
  );
}

class _ReticlePainter extends CustomPainter {
  _ReticlePainter(this.colors);

  final PindoroColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final ring = Paint()
      ..color = colors.mapReticle
      ..style = PaintingStyle.stroke
      ..strokeWidth = PindoroStroke.thick
      ..strokeCap = StrokeCap.round;
    const dashes = 12;
    final rect = Rect.fromCircle(center: center, radius: size.width / 2 - 2);
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(
        rect,
        i * 2 * 3.14159 / dashes,
        3.14159 / dashes,
        false,
        ring,
      );
    }
    canvas
      ..drawCircle(center, 6, Paint()..color = colors.mapPlayerHalo)
      ..drawCircle(center, 4, Paint()..color = colors.mapReticle);
  }

  @override
  bool shouldRepaint(_ReticlePainter old) => old.colors != colors;
}
