import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/pitstop/data/pit_stop_data.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The bottom navigation around the tabs (canvas R4-14): Free play, the Pit
/// stop with its due count, Me. Back on another tab goes to Free play first;
/// tapping the open tab scrolls it to the top.
class TabShell extends ConsumerWidget {
  const TabShell({super.key, required this.shell, required this.scroll});

  static const int tabs = 3;

  final StatefulNavigationShell shell;

  /// Each tab page's primary scroll controller.
  final List<ScrollController> scroll;

  void _select(BuildContext context, WidgetRef ref, int index) {
    ref.read(feedbackProvider).tap();
    if (index != shell.currentIndex) {
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
    final due = ref.watch(pitStopProvider).value?.due.length ?? 0;
    return PopScope(
      canPop: shell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) shell.goBranch(0);
      },
      child: Scaffold(
        body: shell,
        bottomNavigationBar: PindoroNavBar(
          current: shell.currentIndex,
          onSelect: (index) => _select(context, ref, index),
          items: [
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
