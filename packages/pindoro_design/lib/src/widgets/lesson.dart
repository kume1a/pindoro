import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';
import 'motion.dart';
import 'pindoro_button.dart';
import 'reveal.dart';
import 'tappable.dart';

enum PlateChoiceState { idle, selected, right, wrong, dim }

/// The wrong plate's shake: 3 × 6 dp over 300 ms.
const Duration _shakeDuration = Duration(milliseconds: 300);
const double _shakeDp = 6;

/// One answer of "Which street is this?" (`.pd-choice`): a street plate
/// button with the local [name] and its [sub]-line. Selected, it stays down
/// with an accent ring; after Check the right one gets the Great mark, a
/// wrong pick the Miss mark (and shakes once), the others dim. A radio in a
/// group: screen readers hear the name and whether it is picked.
class PlateChoice extends StatelessWidget {
  const PlateChoice({
    super.key,
    required this.name,
    required this.state,
    this.sub,
    this.semanticLabel,
    this.onTap,
  });

  final String name;
  final String? sub;
  final PlateChoiceState state;
  final String? semanticLabel;

  /// Null once the answer is checked.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = PindoroTheme.of(context);
    final c = theme.colors;
    final tier = switch (state) {
      PlateChoiceState.right => theme.tier(Tier.great),
      PlateChoiceState.wrong => theme.tier(Tier.miss),
      _ => null,
    };
    final selected = state == PlateChoiceState.selected;
    final rule = tier?.fill ?? (selected ? c.accentBase : c.streetCardRule);
    final lip = tier?.lip ?? c.streetCardLip;
    final textOpacity = state == PlateChoiceState.dim ? 0.6 : 1.0;

    final plate = Container(
      constraints: const BoxConstraints(minHeight: PindoroSize.tapMin),
      transform: Matrix4.translationValues(
        0,
        selected ? PindoroElevation.e2 : 0,
        0,
      ),
      padding: const EdgeInsets.all(PindoroSpace.s1),
      decoration: BoxDecoration(
        color: c.streetCardBg,
        borderRadius: BorderRadius.circular(PindoroRadius.lg),
        boxShadow: [
          if (selected)
            BoxShadow(color: c.accentBase, spreadRadius: PindoroStroke.thick)
          else
            BoxShadow(color: lip, offset: const Offset(0, PindoroElevation.e2)),
        ],
      ),
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(
          horizontal: PindoroSpace.s3,
          vertical: PindoroSpace.s1,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: rule, width: PindoroStroke.base),
          borderRadius: BorderRadius.circular(PindoroRadius.md),
        ),
        child: Row(
          spacing: PindoroSpace.s3,
          children: [
            Expanded(
              child: Opacity(
                opacity: textOpacity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: PindoroType.titleMd.copyWith(
                        color: c.streetCardText,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (sub != null)
                      Text(
                        sub!,
                        style: PindoroType.labelSm.copyWith(
                          color: c.streetCardSubtext,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (tier != null)
              PopIn(
                child: Container(
                  width: PindoroSize.iconLg,
                  height: PindoroSize.iconLg,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tier.fill,
                    shape: BoxShape.circle,
                  ),
                  child: PindoroIcon(
                    tier.icon,
                    size: PindoroSize.iconSm,
                    color: tier.on,
                    cut: tier.fill,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return Tappable(
      label: semanticLabel ?? [name, ?sub].join(', '),
      button: false,
      checked: selected,
      inMutuallyExclusiveGroup: true,
      onTap: onTap,
      child: state == PlateChoiceState.wrong ? _Shake(child: plate) : plate,
    );
  }
}

class _Shake extends StatelessWidget {
  const _Shake({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery.disableAnimationsOf(context)
      ? child
      : TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: _shakeDuration,
          builder: (_, t, child) => Transform.translate(
            offset: Offset(math.sin(t * 3 * 2 * math.pi) * _shakeDp, 0),
            child: child,
          ),
          child: child,
        );
}

/// What Check said (`.pd-feedback` in a tier sheet): the Great or Miss badge,
/// a [title] ("Correct!", "Not quite"), a [body] line, the [xpLabel] chip,
/// and the tier-coloured [action]. It replaces the Check button, so the
/// options and the map stay in view.
class FeedbackBar extends StatelessWidget {
  const FeedbackBar({
    super.key,
    required this.right,
    required this.title,
    required this.action,
    required this.onAction,
    this.body,
    this.xpLabel,
  });

  final bool right;
  final String title;
  final String? body;
  final String? xpLabel;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final tier = right ? Tier.great : Tier.miss;
    final style = PindoroTheme.of(context).tier(tier);
    return Semantics(
      liveRegion: true,
      child: TierSheetFrame(
        tier: tier,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: PindoroSpace.s3,
          children: [
            Row(
              spacing: PindoroSpace.s3,
              children: [
                PopIn(child: TierBadge(tier)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: PindoroType.titleLg.copyWith(
                          color: style.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (body != null)
                        Text(
                          body!,
                          style: PindoroType.bodySm.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (xpLabel != null) XpChip(xpLabel!),
              ],
            ),
            PindoroButton(tier: tier, label: action, onPressed: onAction),
          ],
        ),
      ),
    );
  }
}
