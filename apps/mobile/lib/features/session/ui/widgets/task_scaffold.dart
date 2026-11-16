import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/features/map/ui/map_layout.dart';
import 'package:pindoro/features/map/ui/widgets/tier_reveal.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// A session task's screen (name, ends, drills): the [map] (none for a
/// bearing), built with what the top bar, [header] and [body] and the
/// bottom cover, with [overlays] over it; the [controls] at the bottom until
/// the [result] sheet replaces them.
class TaskScaffold extends StatelessWidget {
  const TaskScaffold({
    super.key,
    required this.topBar,
    required this.header,
    this.map,
    this.overlays = const [],
    this.body,
    this.controls,
    this.result,
  });

  final Widget topBar;
  final Widget header;
  final Widget Function(MapInsets insets)? map;
  final List<Widget> overlays;

  /// Content under the header: the bearing dial, a recital's modes.
  final Widget? body;
  final Widget? controls;
  final TaskResult? result;

  @override
  Widget build(BuildContext context) {
    final map = this.map;
    final result = this.result;
    final controls = this.controls;
    final bottom =
        result ??
        switch (controls) {
          final c? => Padding(
            padding: EdgeInsets.fromLTRB(
              PindoroSpace.s4,
              0,
              PindoroSpace.s4,
              bottomActionGap(context),
            ),
            child: c,
          ),
          null => null,
        };
    final celebration = result == null ? null : celebrationFor(result.tier);
    final front = [
      if ((result, celebration) case (final r?, final size?))
        RevealCelebration(revealKey: r.resultKey, size: size),
    ];
    final top = Column(
      spacing: PindoroSpace.s4,
      children: [topBar, header, ?body],
    );
    if (map != null) {
      return Scaffold(
        body: MapLayout(
          map: map,
          behind: overlays,
          top: top,
          bottom: bottom,
          front: front,
        ),
      );
    }
    // No map: the body (a typed recital's list) may fill the screen.
    return Scaffold(
      body: Stack(
        children: [
          ...overlays,
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(PindoroSpace.s4),
              child: top,
            ),
          ),
          if (bottom != null)
            Align(alignment: Alignment.bottomCenter, child: bottom),
          ...front,
        ],
      ),
    );
  }
}

/// A task's result sheet: the [tier] (its label, or [label]), the
/// [sentence], the [chip] (next review), any [chips] and Next.
class TaskResult extends StatelessWidget {
  const TaskResult({
    super.key,
    required this.resultKey,
    required this.tier,
    required this.sentence,
    required this.onNext,
    this.label,
    this.chip,
    this.chips = const [],
  });

  final Object resultKey;
  final Tier tier;
  final String sentence;
  final Future<void> Function() onNext;
  final String? label;
  final Widget? chip;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return RevealDock(
      revealKey: resultKey,
      sheet: TierRevealSheet(
        tier: tier,
        label: label ?? tierLabel(l10n, tier),
        sentence: sentence,
        headerChip: chip,
        chips: chips,
        action: l10n.commonNext,
        onNext: onNext,
      ),
    );
  }
}

/// The Pindo card that asks a question without a street plate (Name it, the
/// bearing): Pindo thinking, the [title] and the [note].
class AskCard extends StatelessWidget {
  const AskCard({super.key, required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Semantics(
      header: true,
      child: LipBox(
        shadow: true,
        padding: const EdgeInsets.fromLTRB(
          PindoroSpace.s1,
          PindoroSpace.s1,
          PindoroSpace.s4,
          PindoroSpace.s1,
        ),
        child: Row(
          spacing: PindoroSpace.s2,
          children: [
            const Pindo(PindoExpression.thinking, height: 44),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: PindoroType.titleMd.copyWith(color: c.textPrimary),
                  ),
                  Text(
                    note,
                    style: PindoroType.bodySm.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
