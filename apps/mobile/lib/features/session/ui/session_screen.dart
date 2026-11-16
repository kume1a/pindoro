import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/database/database.dart' show Settings;
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/map/ui/pin_drop_view.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/session/ui/session_controller.dart';
import 'package:pindoro/features/session/ui/widgets/placement_done.dart';
import 'package:pindoro/features/session/ui/widgets/session_done.dart';
import 'package:pindoro/features/session/ui/widgets/session_intro.dart';
import 'package:pindoro/features/session/ui/widgets/session_top_bar.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Today's learning session (SessionScreen): intros, pins and reveals, then
/// Session done. Every answer is saved as it comes, so Leave needs no
/// confirmation.
class SessionScreen extends ConsumerStatefulWidget {
  const SessionScreen({super.key, this.placement = false, this.more = false});

  /// The city's placement instead of today's session (SPEC §6.2).
  final bool placement;

  /// "Learn 5 more" instead of today's session.
  final bool more;

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  /// One label list per known-streets list, so the map syncs only on change.
  final _labels = Expando<List<MapLabel>>();

  @override
  void initState() {
    super.initState();
    // Providers can't change while the tree builds; begin right after.
    Future.microtask(
      () => ref
          .read(sessionControllerProvider.notifier)
          .start(placement: widget.placement, more: widget.more),
    );
  }

  void _leave() => context.canPop() ? context.pop() : context.go(Routes.today);

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionControllerProvider, (previous, next) {
      final shown = previous is SessionPlaying && previous.reveal != null;
      if (next case SessionPlaying(reveal: final reveal?) when !shown) {
        ref
            .read(feedbackProvider)
            .tier(reveal.hit == null ? reveal.grade.tier : Tier.miss);
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
      final SessionPlaying p
          when p.step.kind == StepKind.intro && p.guess == null =>
        SessionIntro(
          play: p,
          known: _known(p, settings),
          topBar: SessionTopBar(p, onLeave: _leave),
          onGotIt: () => unawaited(controller.introDone()),
        ),
      final SessionPlaying p => _pin(p, settings, controller),
      SessionDone(:final summary) => SessionDoneView(
        summary: summary,
        onDone: _leave,
        onLearnMore: summary.cleared
            ? () => context.pushReplacement(Routes.learnMore)
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
      known: _known(p, settings),
      topBar: SessionTopBar(p, onLeave: _leave),
      prompt: placing
          ? l10n.placementPrompt(
              formatNumber(p.index + 1),
              formatNumber(p.steps.length),
            )
          : null,
      skip: placing
          ? (label: l10n.placementSkip, onSkip: controller.skip)
          : null,
      onPin: controller.dropPin,
      onConfirm: () => unawaited(controller.confirm()),
      onNext: () async => controller.next(),
      mixUp: hit == null ? null : _label(hit, settings),
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
          : NextReviewChip(
              label: days == null
                  ? l10n.revealBackThisSession
                  : l10n.revealNextReview(days),
              backThisSession: days == null,
              animate: !MediaQuery.disableAnimationsOf(context),
            ),
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

  List<MapLabel> _known(SessionPlaying p, Settings? settings) =>
      _labels[p.known] ??= [for (final s in p.known) _label(s, settings)];

  MapLabel _label(NamedStreet street, Settings? settings) => (
    geometry: street.geometry,
    at: street.parts.first.midpoint,
    label: streetName(street, settings),
  );
}
