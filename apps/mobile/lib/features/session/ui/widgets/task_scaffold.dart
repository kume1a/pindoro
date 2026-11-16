import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/features/map/ui/widgets/tier_reveal.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// A session task's screen (name, ends, drills): the [map] (none for a
/// bearing) with [overlays] over it, the top bar and [header], the
/// [controls] at the bottom until the [result] sheet replaces them.
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
  final Widget? map;
  final List<Widget> overlays;

  /// Content under the header when there is no map (the bearing dial).
  final Widget? body;
  final Widget? controls;
  final Widget? result;

  @override
  Widget build(BuildContext context) {
    final controls = this.controls;
    return Scaffold(
      body: Stack(
        children: [
          ?map,
          ...overlays,
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(PindoroSpace.s4),
              child: Column(
                spacing: PindoroSpace.s4,
                children: [topBar, header, ?body],
              ),
            ),
          ),
          if (result == null && controls != null)
            Positioned(
              left: PindoroSpace.s4,
              right: PindoroSpace.s4,
              bottom: bottomActionGap(context),
              child: controls,
            ),
          ?result,
        ],
      ),
    );
  }
}

/// A task's result sheet: the [tier] (its label, or [label]), the
/// [sentence], the [chip] (next review) and Next.
class TaskResult extends StatelessWidget {
  const TaskResult({
    super.key,
    required this.resultKey,
    required this.tier,
    required this.sentence,
    required this.onNext,
    this.label,
    this.chip,
  });

  final Object resultKey;
  final Tier tier;
  final String sentence;
  final Future<void> Function() onNext;
  final String? label;
  final Widget? chip;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return RevealDock(
      revealKey: resultKey,
      celebration: celebrationFor(tier),
      sheet: TierRevealSheet(
        tier: tier,
        label: label ?? tierLabel(l10n, tier),
        sentence: sentence,
        headerChip: chip,
        chips: const [],
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
