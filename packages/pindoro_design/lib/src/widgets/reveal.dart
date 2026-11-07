import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';
import 'motion.dart';
import 'round_hud.dart';
import 'surfaces.dart';

/// The answer-reveal sheet in tier colours: badge, label, XP chip, distance
/// sentence, optional chips, and the tier-coloured action pinned at the
/// bottom. Its content scrolls when text is large.
class RevealSheet extends StatelessWidget {
  const RevealSheet({
    super.key,
    required this.tier,
    required this.label,
    required this.sentence,
    required this.action,
    this.xpLabel,
    this.chips = const [],
    this.mascot,
  });

  final Tier tier;

  /// "Perfect!", "Not this time".
  final String label;
  final String sentence;

  /// "+74 XP"; null for a Miss.
  final String? xpLabel;

  /// Usually [Pill]s ("3 in a row", "Added to your Pit stop").
  final List<Widget> chips;

  /// The tier-coloured Next / Got it button.
  final Widget action;
  final Widget? mascot;

  @override
  Widget build(BuildContext context) {
    final style = PindoroTheme.of(context).tier(tier);
    final c = PindoroTheme.of(context).colors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: style.bg,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(PindoroRadius.r2xl),
            ),
            border: Border(
              top: BorderSide(color: style.fill, width: PindoroElevation.e2),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            PindoroSpace.s4,
            PindoroSpace.s5,
            PindoroSpace.s4,
            PindoroSpace.s4 + bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: PindoroSpace.s3,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: PindoroSpace.s2,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: PindoroSpace.s3,
                        runSpacing: PindoroSpace.s2,
                        children: [
                          PopIn(
                            delay: const Duration(milliseconds: 80),
                            child: tier == Tier.close
                                ? Wiggle(child: TierBadge(tier, size: 44))
                                : TierBadge(tier, size: 44),
                          ),
                          Text(
                            label,
                            style: PindoroType.headlineMd.copyWith(
                              color: style.ink,
                            ),
                          ),
                          if (xpLabel != null) XpChip(xpLabel!),
                        ],
                      ),
                      Text(
                        sentence,
                        style: PindoroType.bodyMd.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                      if (chips.isNotEmpty)
                        Wrap(
                          spacing: PindoroSpace.s2,
                          runSpacing: PindoroSpace.s2,
                          children: [...chips],
                        ),
                    ],
                  ),
                ),
              ),
              action,
            ],
          ),
        ),
        if (mascot != null)
          Positioned(right: PindoroSpace.s4, top: -56, child: mascot!),
      ],
    );
  }
}

/// A tier's icon on its fill and lip (badge, result-row tile, tally tile).
class TierBadge extends StatelessWidget {
  const TierBadge(this.tier, {super.key, this.size = 40});

  final Tier tier;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = PindoroTheme.of(context).tier(tier);
    return LipBox(
      face: style.fill,
      lip: style.lip,
      radius: PindoroRadius.md,
      child: SizedBox.square(
        dimension: size - PindoroElevation.e1,
        child: Center(
          child: PindoroIcon(
            style.icon,
            size: size * 0.55,
            color: style.on,
            cut: style.fill,
          ),
        ),
      ),
    );
  }
}

/// "+74 XP" on the reward face.
class XpChip extends StatelessWidget {
  const XpChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return LipBox(
      face: c.rewardBase,
      lip: c.rewardLip,
      radius: PindoroRadius.full,
      padding: const EdgeInsets.symmetric(
        horizontal: PindoroSpace.s3,
        vertical: PindoroSpace.s1,
      ),
      child: Text(
        label,
        style: PindoroType.numericSm.copyWith(color: c.rewardOn),
      ),
    );
  }
}
