import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Before the fixes (canvas R4-23): the lesson's mistakes, listed in the
/// order they happened, and Fix them.
class FixesIntro extends ConsumerWidget {
  const FixesIntro({
    super.key,
    required this.run,
    required this.topBar,
    required this.onFix,
  });

  final LessonRun run;
  final Widget topBar;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final mistakes = run.mistakes;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(PindoroSpace.s4),
              child: topBar,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(PindoroSpace.s4),
                children: [
                  ContentColumn(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: PindoroSpace.s4,
                      children: [
                        const Center(
                          child: Pindo(PindoExpression.encouraging, height: 96),
                        ),
                        Semantics(
                          header: true,
                          child: Text(
                            l10n.lessonFixesTitle(mistakes.length),
                            textAlign: TextAlign.center,
                            style: PindoroType.headlineSm.copyWith(
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          l10n.lessonFixesBody,
                          textAlign: TextAlign.center,
                          style: PindoroType.bodyMd.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                        ListGroup(
                          children: [
                            for (final m in mistakes)
                              ListRow(
                                title: streetName(m.step.street, settings),
                                subtitle: switch (m.step) {
                                  PinStep() => l10n.lessonFixPin(
                                    tierWord(l10n, m.tier),
                                    formatDistance(m.distanceM!, l10n),
                                  ),
                                  NameStep() => l10n.lessonFixName,
                                  TripStep() => l10n.lessonFixTrip,
                                },
                                leading: RowTile(switch (m.step) {
                                  PinStep() => PindoroGlyph.pinDrop,
                                  NameStep() => PindoroGlyph.signpost,
                                  TripStep() => PindoroGlyph.car,
                                }),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            PinnedFooter(
              child: PindoroButton(
                label: l10n.lessonFixThem,
                icon: PindoroGlyph.reroute,
                onPressed: () {
                  ref.read(feedbackProvider).tap();
                  onFix();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
