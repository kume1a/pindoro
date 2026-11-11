import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/badges/data/badge_data.dart';
import 'package:pindoro/features/course/data/course_data.dart';
import 'package:pindoro/features/league/data/league_data.dart';
import 'package:pindoro/features/pitstop/data/pit_stop_data.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The bottom navigation around the tabs (canvas R4-14, R5-03): the Path,
/// Free play, the Pit stop with its due count, Leagues, Me. Back on another
/// tab goes to the Path first; tapping the open tab scrolls it to the top
/// (the Path: to its current stop). Opening Leagues syncs this week's XP;
/// opening Me takes its New badges for the visit.
class TabShell extends ConsumerWidget {
  const TabShell({super.key, required this.shell, required this.scroll});

  static const int path = 0;
  static const int freePlay = 1;
  static const int pitStop = 2;
  static const int league = 3;
  static const int me = 4;
  static const int tabs = 5;

  final StatefulNavigationShell shell;

  /// Each tab page's primary scroll controller.
  final List<ScrollController> scroll;

  void _select(BuildContext context, WidgetRef ref, int index) {
    ref.read(feedbackProvider).tap();
    if (index != shell.currentIndex) {
      if (index == league) ref.invalidate(standingProvider);
      if (index == me) ref.invalidate(newBadgesProvider);
      shell.goBranch(index);
    } else if (index == path) {
      ref.read(pathRetapProvider.notifier).tap();
    } else if (scroll[index].hasClients) {
      _toTop(context, scroll[index]);
    }
  }

  void _toTop(BuildContext context, ScrollController controller) {
    if (MediaQuery.disableAnimationsOf(context)) return controller.jumpTo(0);
    unawaited(
      controller.animateTo(
        0,
        duration: PindoroMotion.durationBase,
        curve: PindoroMotion.easeDecelerate,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final due = ref.watch(pitStopProvider).value?.due.length ?? 0;
    return PopScope(
      canPop: shell.currentIndex == path,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) shell.goBranch(path);
      },
      child: Scaffold(
        body: shell,
        bottomNavigationBar: PindoroNavBar(
          current: shell.currentIndex,
          onSelect: (index) => _select(context, ref, index),
          items: [
            (
              glyph: PindoroGlyph.road,
              label: l10n.tabPath,
              badge: null,
              semanticLabel: null,
            ),
            (
              glyph: PindoroGlyph.map,
              label: l10n.tabFreePlay,
              badge: null,
              semanticLabel: null,
            ),
            (
              glyph: PindoroGlyph.wrench,
              label: l10n.pitStopTitle,
              badge: due,
              semanticLabel: due == 0 ? null : l10n.a11yPitStopTab(due),
            ),
            (
              glyph: PindoroGlyph.flag,
              label: l10n.tabLeagues,
              badge: null,
              semanticLabel: null,
            ),
            (
              glyph: PindoroGlyph.user,
              label: l10n.meTitle,
              badge: null,
              semanticLabel: null,
            ),
          ],
        ),
      ),
    );
  }
}
