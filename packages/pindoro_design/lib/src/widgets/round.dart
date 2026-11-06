import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';
import 'surfaces.dart';

/// The quiz top bar's progress: one segment per question. Answered segments
/// are lane yellow (a Miss is red), the current one cobalt, the rest outlined.
class QuestionBar extends StatelessWidget {
  const QuestionBar({
    super.key,
    required this.tiers,
    required this.total,
    required this.semanticLabel,
  });

  /// Answers so far, in order.
  final List<Tier> tiers;
  final int total;

  /// "Question 5 of 10".
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Row(
        spacing: PindoroSpace.s1,
        children: [
          for (var i = 0; i < total; i++)
            Expanded(
              child: AnimatedContainer(
                duration: PindoroMotion.durationFast,
                curve: PindoroMotion.easeStandard,
                height: 12,
                decoration: BoxDecoration(
                  color: i < tiers.length
                      ? (tiers[i] == Tier.miss
                            ? c.feedbackMissFill
                            : c.progressDone)
                      : i == tiers.length
                      ? c.progressCurrent
                      : c.progressTodo,
                  borderRadius: BorderRadius.circular(PindoroRadius.xs),
                  border: i > tiers.length
                      ? Border.all(
                          color: c.progressTodoBorder,
                          width: PindoroStroke.base,
                        )
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A raised pill (XP, city, area size); floats over the map with a shadow.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.icon,
    this.iconColor,
    this.floating = false,
    this.semanticLabel,
  });

  final String label;
  final PindoroGlyph? icon;
  final Color? iconColor;
  final bool floating;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: LipBox(
        radius: PindoroRadius.full,
        shadow: floating,
        padding: const EdgeInsets.symmetric(
          horizontal: PindoroSpace.s3,
          vertical: PindoroSpace.s2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: PindoroSpace.s1,
          children: [
            if (icon != null)
              PindoroIcon(
                icon!,
                size: PindoroSize.iconSm,
                color: iconColor ?? c.textPrimary,
              ),
            Text(
              label,
              style: PindoroType.numericSm.copyWith(color: c.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// A 48 dp map control (raised, 2 dp lip, `shadow.float`).
class MapControl extends StatelessWidget {
  const MapControl({
    super.key,
    required this.glyph,
    required this.semanticLabel,
    required this.onPressed,
  });

  final PindoroGlyph glyph;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onPressed,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: LipBox(
          radius: PindoroRadius.md,
          shadow: true,
          child: SizedBox.square(
            dimension: PindoroSize.tapMin - PindoroElevation.e1,
            child: Center(child: PindoroIcon(glyph)),
          ),
        ),
      ),
    ),
  );
}

/// The brand pin: a round head on a short point, on a lip. [halo] adds the
/// player pin's white outline. The tip, at the bottom centre, is the point.
class PinMark extends StatelessWidget {
  const PinMark({
    super.key,
    required this.face,
    required this.lip,
    required this.dot,
    this.halo,
    this.width = PindoroSize.pinPlayer,
  });

  final Color face;
  final Color lip;
  final Color dot;
  final Color? halo;
  final double width;

  /// The pin's 40 × 48 design grid.
  static const double gridWidth = 40;
  static const double gridHeight = 48;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, width * gridHeight / gridWidth),
    painter: _PinPainter(face: face, lip: lip, dot: dot, halo: halo),
  );
}

class _PinPainter extends CustomPainter {
  _PinPainter({
    required this.face,
    required this.lip,
    required this.dot,
    this.halo,
  });

  final Color face;
  final Color lip;
  final Color dot;
  final Color? halo;

  /// Head radius 16 centred at (20, 18), tip 26 below the centre (grid units).
  static Path _shape(double dy) {
    const cx = 20.0, r = 16.0, tipDrop = 26.0;
    final cy = 18.0 + dy;
    final tip = Offset(cx, cy + tipDrop);
    final angle = math.acos(r / tipDrop);
    final left = Offset(cx - r * math.sin(angle), cy + r * math.cos(angle));
    return Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..arcTo(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        math.pi / 2 + angle,
        2 * math.pi - 2 * angle,
        false,
      )
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / PinMark.gridWidth);
    final lipPath = _shape(PindoroElevation.e2 - 4);
    final facePath = _shape(-4);
    if (halo != null) {
      canvas.drawPath(
        lipPath,
        Paint()
          ..color = halo!
          ..style = PaintingStyle.stroke
          ..strokeWidth = PindoroStroke.base * 2
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas
      ..drawPath(lipPath, Paint()..color = lip)
      ..drawPath(facePath, Paint()..color = face)
      ..drawCircle(const Offset(20, 14), 6, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_PinPainter old) =>
      old.face != face || old.lip != lip || old.dot != dot || old.halo != halo;
}

/// A hint bubble over the map on the inverse surface; passes taps through.
class CoachBubble extends StatelessWidget {
  const CoachBubble({super.key, required this.title, this.body});

  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: LipBox(
            face: c.coachBg,
            lip: c.coachLip,
            lipHeight: PindoroElevation.e2,
            radius: PindoroRadius.lg,
            shadow: true,
            padding: const EdgeInsets.symmetric(
              horizontal: PindoroSpace.s4,
              vertical: PindoroSpace.s3,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: PindoroType.titleSm.copyWith(color: c.coachText),
                ),
                if (body != null)
                  Text(
                    body!,
                    style: PindoroType.bodySm.copyWith(color: c.coachText),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
  final List<String> chips;

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
                          TierBadge(tier, size: 44),
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
                          children: [
                            for (final chip in chips) Pill(label: chip),
                          ],
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

/// One round answer on the results list: tier tile, street name, tier word
/// and distance, XP. Tapping opens it on the map.
class ResultRow extends StatelessWidget {
  const ResultRow({
    super.key,
    required this.tier,
    required this.street,
    required this.detail,
    required this.xp,
    required this.semanticLabel,
    this.onTap,
    this.selected = false,
  });

  final Tier tier;
  final String street;

  /// "Great · 84 m"; the tier word is drawn in the tier ink.
  final ({String tierWord, String rest}) detail;
  final int xp;
  final String semanticLabel;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = PindoroTheme.of(context);
    final c = theme.colors;
    final style = theme.tier(tier);
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: selected ? c.primarySoft : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: c.surfaceSunken,
          mouseCursor: onTap == null ? null : SystemMouseCursors.click,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: PindoroSpace.s4,
                vertical: PindoroSpace.s2,
              ),
              child: Row(
                spacing: PindoroSpace.s3,
                children: [
                  TierBadge(tier),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          street,
                          style: PindoroType.titleMd.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: detail.tierWord,
                                style: TextStyle(
                                  color: style.ink,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              TextSpan(text: detail.rest),
                            ],
                          ),
                          style: PindoroType.bodySm.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    xp > 0 ? '+$xp' : '0',
                    style: PindoroType.numericSm.copyWith(
                      color: xp > 0 ? c.rewardText : c.textSecondary,
                    ),
                  ),
                  if (onTap != null)
                    PindoroIcon(
                      PindoroGlyph.chevronRight,
                      size: PindoroSize.iconSm,
                      color: c.textSecondary,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The round's XP total on the lane-yellow reward plate.
class RewardTotal extends StatelessWidget {
  const RewardTotal({
    super.key,
    required this.value,
    required this.semanticLabel,
  });

  /// "+695 XP".
  final String value;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: LipBox(
        face: c.rewardBase,
        lip: c.rewardLip,
        lipHeight: PindoroElevation.e3,
        padding: const EdgeInsets.symmetric(
          horizontal: PindoroSpace.s6,
          vertical: PindoroSpace.s3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: PindoroSpace.s2,
          children: [
            PindoroIcon(
              PindoroGlyph.xp,
              size: PindoroSize.iconLg,
              color: c.rewardOn,
              cut: c.rewardBase,
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: PindoroType.numericXl.copyWith(color: c.rewardOn),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Four tiles counting the round's answers by tier.
class TierTally extends StatelessWidget {
  const TierTally({
    super.key,
    required this.counts,
    required this.labels,
    required this.semanticLabel,
  });

  final Map<Tier, int> counts;
  final Map<Tier, String> labels;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = PindoroTheme.of(context);
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Row(
        spacing: PindoroSpace.s2,
        children: [
          for (final tier in Tier.values)
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: PindoroSpace.s1,
                  vertical: PindoroSpace.s2,
                ),
                decoration: BoxDecoration(
                  color: theme.tier(tier).bg,
                  borderRadius: BorderRadius.circular(PindoroRadius.lg),
                ),
                child: Column(
                  spacing: PindoroSpace.s1,
                  children: [
                    TierBadge(tier, size: PindoroSize.iconLg),
                    Text(
                      '${counts[tier] ?? 0}',
                      style: PindoroType.numericMd.copyWith(
                        color: theme.colors.textPrimary,
                      ),
                    ),
                    Text(
                      labels[tier]!,
                      textAlign: TextAlign.center,
                      style: PindoroType.labelMd.copyWith(
                        color: theme.tier(tier).ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
