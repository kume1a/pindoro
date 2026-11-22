import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/feedback.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/features/badges/data/badge_data.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The bottom navigation around the tabs (design system Bottom nav): Drive,
/// Today, Explore, Progress, Me. Back on another tab goes to Drive first;
/// tapping the open tab scrolls it to the top. Opening Me takes its New
/// badges for the visit.
class TabShell extends ConsumerWidget {
  const TabShell({super.key, required this.shell, required this.scroll});

  static const int drive = 0;
  static const int today = 1;
  static const int explore = 2;
  static const int progress = 3;
  static const int me = 4;
  static const int tabs = 5;

  final StatefulNavigationShell shell;

  /// Each tab page's primary scroll controller.
  final List<ScrollController> scroll;

  void _select(BuildContext context, WidgetRef ref, int index) {
    ref.read(feedbackProvider).tap();
    if (index != shell.currentIndex) {
      if (index == me) ref.invalidate(newBadgesProvider);
      shell.goBranch(index);
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
    return PopScope(
      canPop: shell.currentIndex == drive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) shell.goBranch(drive);
      },
      child: Scaffold(
        body: shell,
        bottomNavigationBar: PindoroNavBar(
          current: shell.currentIndex,
          onSelect: (index) => _select(context, ref, index),
          items: [
            (
              glyph: PindoroGlyph.car,
              label: l10n.driveTitle,
              semanticLabel: null,
            ),
            (
              glyph: PindoroGlyph.road,
              label: l10n.tabToday,
              semanticLabel: null,
            ),
            (
              glyph: PindoroGlyph.map,
              label: l10n.tabExplore,
              semanticLabel: null,
            ),
            (
              glyph: PindoroGlyph.chart,
              label: l10n.progressTitle,
              semanticLabel: null,
            ),
            (
              glyph: PindoroGlyph.user,
              label: l10n.meTitle,
              semanticLabel: null,
            ),
          ],
        ),
      ),
    );
  }
}
