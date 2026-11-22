import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/database/database.dart' show Settings;
import 'package:pindoro/core/feedback.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/progress.dart';
import 'package:pindoro/features/map/ui/pin_drop_view.dart';
import 'package:pindoro/features/session/ui/session_controller.dart';
import 'package:pindoro/features/session/ui/widgets/bearing_view.dart';
import 'package:pindoro/features/session/ui/widgets/crossings_view.dart';
import 'package:pindoro/features/session/ui/widgets/ends_view.dart';
import 'package:pindoro/features/session/ui/widgets/name_it_view.dart';
import 'package:pindoro/features/session/ui/widgets/place_intro.dart';
import 'package:pindoro/features/session/ui/widgets/placement_done.dart';
import 'package:pindoro/features/session/ui/widgets/recital_view.dart';
import 'package:pindoro/features/session/ui/widgets/route_view.dart';
import 'package:pindoro/features/session/ui/widgets/session_done.dart';
import 'package:pindoro/features/session/ui/widgets/session_intro.dart';
import 'package:pindoro/features/session/ui/widgets/session_top_bar.dart';
import 'package:pindoro/features/session/ui/widgets/sweep_view.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Today's learning session (SessionScreen): intros, pins and reveals, then
/// Session done. Every answer is saved as it comes, so Leave needs no
/// confirmation.
class SessionScreen extends ConsumerStatefulWidget {
  const SessionScreen({
    super.key,
    this.placement = false,
    this.more = false,
    this.drill,
  });

  /// The city's placement instead of today's session (SPEC §6.2).
  final bool placement;

  /// "Learn 10 more" instead of today's session.
  final bool more;

  /// These cards as relearns instead (a drive's missed turns).
  final List<String>? drill;

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  @override
  void initState() {
    super.initState();
    // Providers can't change while the tree builds; begin right after.
    Future.microtask(
      () => ref
          .read(sessionControllerProvider.notifier)
          .start(
            placement: widget.placement,
            more: widget.more,
            drill: widget.drill,
          ),
    );
  }

  void _leave() => context.canPop() ? context.pop() : context.go(Routes.today);

  void _dropPin(LatLng at) {
    ref.read(feedbackProvider).pinDrop();
    ref.read(sessionControllerProvider.notifier).dropPin(at);
  }

  void _confirm(Future<void> Function() answer) {
    ref.read(feedbackProvider).confirm();
    unawaited(answer());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionControllerProvider, (previous, next) {
      final shown = previous is SessionPlaying && previous.answered;
      if (next case SessionPlaying(resultTier: final tier?) when !shown) {
        ref.read(feedbackProvider).tier(tier);
      }
    });
    final settings = ref.watch(settingsProvider).value;
    final controller = ref.read(sessionControllerProvider.notifier);
    return switch (ref.watch(sessionControllerProvider)) {
      SessionLoading() => const Scaffold(body: Center(child: LaneLoader())),
      SessionEmpty() => PageScaffold(
        title: context.l10n.todayDoneTitle,
        children: const [],
      ),
      final SessionPlaying p &&
              SessionPlaying(
                task: RouteTask(question: final LandmarkQuestion q),
              )
          when p.step.kind == StepKind.intro =>
        PlaceIntro(
          play: p,
          question: q,
          topBar: _topBar(p, controller),
          onGotIt: () => unawaited(controller.introDone()),
          onHide: () => unawaited(controller.hidePlace()),
        ),
      final SessionPlaying p
          when p.step.kind == StepKind.intro && p.guess == null =>
        SessionIntro(
          // Intros come in a row: each step gets its own note field.
          key: ValueKey(p.index),
          play: p,
          contrast: p.contrast,
          topBar: _topBar(p, controller),
          onGotIt: (note) => unawaited(controller.introDone(note: note)),
        ),
      final SessionPlaying p => switch (p.task) {
        NameTask() => NameItView(
          play: p,
          topBar: _topBar(p, controller),
          onPick: (s) => unawaited(controller.pickName(s)),
          onNext: () async => controller.next(),
          chip: _nextReviewChip(p, (p.task as NameTask).nextReviewDays),
        ),
        ExtentTask(:final nextReviewDays) => EndsView(
          play: p,
          topBar: _topBar(p, controller),
          onPin: _dropPin,
          onConfirm: () => _confirm(controller.confirm),
          onNext: () async => controller.next(),
          chip: _nextReviewChip(p, nextReviewDays),
        ),
        SweepTask() => SweepView(
          play: p,
          topBar: _topBar(p, controller),
          onPlace: controller.placeLane,
          onCheck: () => _confirm(controller.checkSweep),
          onNext: () async => controller.next(),
        ),
        CrossingsTask() => CrossingsView(
          play: p,
          topBar: _topBar(p, controller),
          onName: controller.nameCrossing,
          onNext: () async => controller.next(),
        ),
        BearingTask() => BearingView(
          play: p,
          topBar: _topBar(p, controller),
          onTurn: controller.turn,
          onCheck: () => _confirm(controller.checkBearing),
          onNext: () async => controller.next(),
        ),
        RouteTask(:final nextReviewDays) => RouteView(
          play: p,
          topBar: _topBar(p, controller),
          onChoose: controller.choose,
          onPin: _dropPin,
          onAnswer: (typed) =>
              _confirm(() => controller.answerRoute(typed: typed)),
          onNext: () async => controller.next(),
          onHidePlace: () => unawaited(controller.hidePlace()),
          chip: _nextReviewChip(p, nextReviewDays),
        ),
        RecitalTask(:final nextReviewDays) => RecitalView(
          play: p,
          topBar: _topBar(p, controller),
          onMode: controller.recitalMode,
          onTurn: controller.recitalTurn,
          onAdd: controller.recitalAdd,
          onUndo: controller.recitalUndo,
          onDraw: controller.recitalDraw,
          onCheck: () => _confirm(controller.checkRecital),
          onReport: () => unawaited(controller.reportMove()),
          onNext: () async => controller.next(),
          chip: _nextReviewChip(p, nextReviewDays),
        ),
        PinTask() => _pin(p, settings, controller),
      },
      SessionDone(:final summary) => SessionDoneView(
        summary: summary,
        onDone: _leave,
        onNextRound: summary.round < summary.rounds
            ? controller.nextRound
            : null,
        // In place: Today's plans read the cards again, and Today's push
        // still ends when this screen goes.
        onLearnMore: summary.cleared && summary.round == summary.rounds
            ? () {
                refreshLearning(ref);
                unawaited(controller.start(more: true));
              }
            : null,
      ),
      SessionPlaced(:final summary) => PlacementDoneView(
        summary: summary,
        onStart: _leave,
      ),
    };
  }

  Widget _pin(
    SessionPlaying p,
    Settings? settings,
    SessionController controller,
  ) {
    final l10n = context.l10n;
    final r = p.reveal;
    final hit = r?.hit;
    final days = r?.nextReviewDays;
    final forgotten = r?.grade.rating == Rating.again;
    final placing = p.step.kind == StepKind.placement;
    return PinDropView(
      area: p.area,
      questionKey: p.index,
      street: p.street,
      pin: p.pin,
      frame: p.frame,
      topBar: _topBar(p, controller),
      prompt: placing
          ? l10n.placementPrompt(
              formatNumber(p.index + 1),
              formatNumber(p.steps.length),
            )
          : null,
      skip: placing
          ? (label: l10n.placementSkip, onSkip: controller.skip)
          : null,
      onPin: _dropPin,
      onConfirm: () => _confirm(controller.confirm),
      onNext: () async => controller.next(),
      mixUp: hit,
      guess: switch (p.guess) {
        final g? => (
          subline: g.knownSiblings == 0
              ? l10n.sessionGuessKnowParent(streetName(g.parent, settings))
              : l10n.sessionGuessKnowFamily(
                  streetName(g.parent, settings),
                  g.knownSiblings,
                ),
          note: l10n.sessionGuessNote,
        ),
        null => null,
      },
      headerChip: r == null || (placing && days == null)
          ? null
          : _nextReviewChip(p, days),
      celebration: r == null || hit != null
          ? null
          : celebrationFor(r.grade.tier),
      reveal: r == null
          ? null
          : (
              key: p.index,
              tier: r.grade.tier,
              distanceM: r.grade.distanceM,
              pin: r.pin,
              nearest: r.nearest,
              chips: [
                if (hit != null)
                  StatChip(
                    label: l10n.revealPairSaved(
                      '${streetName(p.street, settings)} ↔ '
                      '${streetName(hit, settings)}',
                    ),
                    glyph: PindoroGlyph.reroute,
                  ),
              ],
              action:
                  !placing &&
                      forgotten &&
                      (hit != null || r.grade.tier == Tier.miss)
                  ? l10n.revealGotIt
                  : l10n.commonNext,
            ),
    );
  }

  Widget _topBar(SessionPlaying p, SessionController controller) =>
      SessionTopBar(p, round: controller.round, onLeave: _leave);

  /// "Next review in 12 days", "Back in this session", or for a new leech
  /// "Back tomorrow for a closer look".
  Widget _nextReviewChip(SessionPlaying p, int? days) {
    final l10n = context.l10n;
    return NextReviewChip(
      label: p.suspended
          ? l10n.revealLeech
          : days == null
          ? l10n.revealBackThisSession
          : l10n.revealNextReview(days),
      backThisSession: days == null && !p.suspended,
      animate: !MediaQuery.disableAnimationsOf(context),
    );
  }
}
