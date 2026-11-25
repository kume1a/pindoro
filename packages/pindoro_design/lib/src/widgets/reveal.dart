import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';
import 'motion.dart';
import 'round_hud.dart';
import 'surfaces.dart';

/// The answer-reveal sheet in tier colours, kept short so the map keeps its
/// room: badge, label, an optional header chip, the distance sentence,
/// optional chips, and the tier-coloured action pinned at the bottom with an
/// optional [secondary] icon button beside it. Its content scrolls when text
/// is large.
class RevealSheet extends StatelessWidget {
  const RevealSheet({
    super.key,
    required this.tier,
    required this.label,
    required this.sentence,
    required this.action,
    this.headerChip,
    this.chips = const [],
    this.mascot,
    this.secondary,
  });

  final Tier tier;

  /// "Perfect!", "Not this time".
  final String label;
  final String sentence;

  /// Ends the header row: the next-review chip.
  final Widget? headerChip;

  /// Usually [Pill]s ("3 in a row").
  final List<Widget> chips;

  /// The tier-coloured Next / Got it button.
  final Widget action;

  /// Left of [action]: an icon button such as Street View.
  final Widget? secondary;
  final Widget? mascot;

  /// How far [mascot] stands up out of the sheet.
  static const double mascotRise = 40;

  @override
  Widget build(BuildContext context) {
    final style = PindoroTheme.of(context).tier(tier);
    final c = PindoroTheme.of(context).colors;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        TierSheetFrame(
          tier: tier,
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
                        spacing: PindoroSpace.s2,
                        runSpacing: PindoroSpace.s2,
                        children: [
                          PopIn(
                            delay: PindoroMotion.durationInstant,
                            child: tier == Tier.close
                                ? Wiggle(
                                    child: TierBadge(
                                      tier,
                                      size: PindoroSize.iconLg,
                                    ),
                                  )
                                : TierBadge(tier, size: PindoroSize.iconLg),
                          ),
                          Text(
                            label,
                            style: PindoroType.titleLg.copyWith(
                              color: style.ink,
                            ),
                          ),
                          ?headerChip,
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
              Row(
                spacing: PindoroSpace.s3,
                children: [
                  ?secondary,
                  Expanded(child: action),
                ],
              ),
            ],
          ),
        ),
        if (mascot != null)
          Positioned(right: PindoroSpace.s4, top: -mascotRise, child: mascot!),
      ],
    );
  }
}

/// The bottom sheet of [RevealSheet] in [tier] colours: full width on the
/// tier background, its top rounded with a tier-fill edge, padded
/// [PindoroSpace.s3] around [child], which stays clear of the system bottom
/// inset.
class TierSheetFrame extends StatelessWidget {
  const TierSheetFrame({super.key, required this.tier, required this.child});

  final Tier tier;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = PindoroTheme.of(context).tier(tier);
    return SheetFrame(
      color: style.bg,
      topBorder: BorderSide(color: style.fill, width: PindoroElevation.e2),
      child: child,
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
