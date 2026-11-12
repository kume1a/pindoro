import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/play_bar.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/lesson/ui/lesson_controller.dart';
import 'package:pindoro/features/lesson/ui/widgets/fixes_intro.dart';
import 'package:pindoro/features/lesson/ui/widgets/name_question.dart';
import 'package:pindoro/features/lesson/ui/widgets/new_street_card.dart';
import 'package:pindoro/features/map/ui/pin_drop_view.dart';
import 'package:pindoro/features/map/ui/route_view.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// A lesson, its practice or a unit's Pit stop (canvas R4-20 to R4-23): one
/// screen driven by the step list. ✕ or back asks before leaving, and
/// leaving writes nothing; the last step saves it and opens Lesson complete.
class LessonScreen extends ConsumerStatefulWidget {
  const LessonScreen({super.key, required this.args});

  final LessonArgs args;

  @override
  ConsumerState<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends ConsumerState<LessonScreen> {
  @override
  void initState() {
    super.initState();
    // Providers can't change while the tree builds; begin right after.
    Future.microtask(
      () => ref.read(lessonControllerProvider.notifier).start(widget.args),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(lessonControllerProvider, (previous, next) {
      switch (next) {
        case LessonSaved(:final resultId):
          context.go(Routes.lessonDoneOf(resultId));
        case LessonMissing():
          context.go(Routes.path);
        case LessonPlaying(:final run)
            when run.answered &&
                !(previous is LessonPlaying && previous.run.answered):
          _answered(run.answers.last);
        default:
      }
    });
    const loader = Scaffold(body: Center(child: LaneLoader()));
    return switch (ref.watch(lessonControllerProvider)) {
      final LessonPlaying p when !p.run.finished => _LessonView(p),
      // Saving the finished lesson: back would skip Lesson complete.
      LessonPlaying() => const PopScope(canPop: false, child: loader),
      _ => loader,
    };
  }

  /// The tier's haptic, and a name's result read out.
  void _answered(StepAnswer answer) {
    ref.read(feedbackProvider).tier(answer.tier);
    if (answer.step case NameStep(:final street)) {
      final l10n = context.l10n;
      final settings = ref.read(settingsProvider).value;
      final name = streetName(street, settings);
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          isKnownTier(answer.tier)
              ? l10n.a11yNameRight(name, formatNumber(answer.xp))
              : l10n.a11yNameWrong(name),
          Directionality.of(context),
        ),
      );
    }
  }
}

class _LessonView extends ConsumerWidget {
  const _LessonView(this.play);

  final LessonPlaying play;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(lessonControllerProvider.notifier);
    final run = play.run;
    final topBar = LessonTopBar(run, onLeave: () => _leave(context, ref));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave(context, ref));
      },
      child: switch (run.step) {
        _ when run.startsFixes && !play.fixesOpen => FixesIntro(
          run: run,
          topBar: topBar,
          onFix: controller.openFixes,
        ),
        final CardStep card => NewStreetCard(
          play: play,
          step: card,
          topBar: topBar,
          onNext: controller.next,
        ),
        final NameStep name => NameQuestion(
          play: play,
          step: name,
          topBar: topBar,
          onChoose: controller.choose,
          onCheck: controller.check,
          onNext: controller.next,
        ),
        final PinStep pin => _pinDrop(context, ref, pin, topBar),
        final TripStep trip => _roadTrip(context, ref, trip, topBar),
      },
    );
  }

  Widget _pinDrop(
    BuildContext context,
    WidgetRef ref,
    PinStep step,
    Widget topBar,
  ) {
    final l10n = context.l10n;
    final controller = ref.read(lessonControllerProvider.notifier);
    final feedback = ref.read(feedbackProvider);
    final run = play.run;
    final answer = run.answered ? run.answers.last : null;
    final wrong = answer != null && isRetryTier(answer.tier);
    final perfects = run.answers.where((a) => a.tier == Tier.perfect).length;
    return PinDropView(
      area: play.shape,
      questionKey: run.index,
      street: step.street,
      retryDistance: step.lastDistanceM,
      pin: play.pin,
      topBar: topBar,
      reveal: answer == null
          ? null
          : (
              key: run.index,
              tier: answer.tier,
              xp: answer.xp,
              distanceM: answer.distanceM!,
              pin: play.pin!,
              nearest: play.nearest!,
              chips: [
                // A lesson's first try comes back; anything else wrong goes
                // to the Pit stop.
                if (wrong && run.kind == LessonKind.lesson && !step.fix)
                  Pill(label: l10n.lessonComesBack, icon: PindoroGlyph.reroute)
                else if (wrong)
                  PitStopChip(l10n.revealToPitStop),
              ],
              action: answer.tier == Tier.miss
                  ? l10n.revealGotIt
                  : l10n.commonNext,
            ),
      celebration: answer == null
          ? null
          : celebrationFor(answer.tier, perfectsThisRound: perfects, inARow: 0),
      onPin: (at) {
        feedback.pinDrop();
        controller.placePin(at);
      },
      onConfirm: () {
        feedback.confirm();
        controller.confirm();
      },
      onNext: controller.next,
    );
  }

  Widget _roadTrip(
    BuildContext context,
    WidgetRef ref,
    TripStep step,
    Widget topBar,
  ) {
    final l10n = context.l10n;
    final controller = ref.read(lessonControllerProvider.notifier);
    final feedback = ref.read(feedbackProvider);
    final run = play.run;
    final answer = run.answered ? run.answers.last : null;
    final comesBack = run.kind == LessonKind.lesson && !step.fix;
    final perfects = run.answers.where((a) => a.tier == Tier.perfect).length;
    return RouteView(
      area: play.shape,
      questionKey: run.index,
      ask: l10n.routeAsk,
      trip: step.trip,
      draft: play.route!,
      reveal: answer == null
          ? null
          : (
              key: run.index,
              score: (tier: answer.tier, xp: answer.xp),
              chips: [
                if (answer.tier == Tier.miss && comesBack)
                  Pill(label: l10n.lessonComesBack, icon: PindoroGlyph.reroute),
              ],
              action: answer.tier == Tier.miss
                  ? l10n.revealGotIt
                  : l10n.commonNext,
              celebration: celebrationFor(
                answer.tier,
                perfectsThisRound: perfects,
                inARow: 0,
              ),
            ),
      topBar: topBar,
      showBody: comesBack ? l10n.routeShowLessonBody : l10n.routeShowDriveBody,
      ghost: play.firstTrip,
      onDraft: controller.drawTo,
      onCheck: () {
        feedback.confirm();
        controller.checkRoute();
      },
      onShow: controller.showRoute,
      onNext: controller.next,
    );
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final leave = await confirmLeave(
      context,
      title: l10n.lessonLeaveTitle,
      body: l10n.lessonLeaveBody,
      stay: l10n.lessonKeepLearning,
      leave: l10n.lessonLeave,
    );
    if (!leave || !context.mounted) return;
    await ref.read(lessonControllerProvider.notifier).leave();
    if (context.mounted) context.go(Routes.path);
  }
}

/// ✕, the step bar (a segment per step, one more per mistake to fix) and
/// the XP this lesson.
class LessonTopBar extends StatelessWidget {
  const LessonTopBar(this.run, {super.key, required this.onLeave});

  final LessonRun run;
  final VoidCallback onLeave;

  /// Cards and right answers fill in yellow, mistakes in red.
  static List<Tier> segments(LessonRun run) {
    final mistakes = {for (final a in run.answers) a.step: isMistake(a)};
    final through = run.answered ? run.index + 1 : run.index;
    return [
      for (final step in run.steps.take(through))
        switch (step) {
          CardStep() => Tier.great,
          final TestStep t => mistakes[t]! ? Tier.miss : Tier.great,
        },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final step = (run.index + 1).clamp(1, run.total);
    return PlayBar(
      leaveLabel: l10n.a11yLeaveLesson,
      onLeave: onLeave,
      tiers: segments(run),
      total: run.total,
      barLabel: l10n.a11yLessonStep(step, run.total),
      xp: run.stepXp,
      xpLabel: l10n.a11yLessonXp,
    );
  }
}
