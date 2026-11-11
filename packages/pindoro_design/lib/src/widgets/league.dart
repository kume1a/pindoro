import 'package:flutter/material.dart';

import 'package:pindoro_design/src/generated/pindoro_tokens.dart';
import 'package:pindoro_design/src/theme.dart';
import 'package:pindoro_design/src/widgets/graphics.dart';
import 'package:pindoro_design/src/widgets/surfaces.dart';

/// The league's street-plate header (`.pd-league-head`): the yellow flag,
/// [title] and [subtitle], and a ladder of [tiers] steps with [tier] (from 0)
/// raised. One heading node read as [semanticLabel].
class LeagueHeader extends StatelessWidget {
  const LeagueHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.tier,
    required this.tiers,
    required this.semanticLabel,
  });

  final String title;
  final String subtitle;
  final int tier;
  final int tiers;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Semantics(
      header: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: LipBox(
        face: c.streetCardBg,
        lip: c.streetCardLip,
        lipHeight: PindoroElevation.e2,
        padding: const EdgeInsets.all(PindoroSpace.s1 + PindoroStroke.base),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: c.streetCardRule,
              width: PindoroStroke.thick,
            ),
            borderRadius: BorderRadius.circular(PindoroRadius.lg),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: PindoroSpace.s4,
              vertical: PindoroSpace.s3,
            ),
            child: Row(
              spacing: PindoroSpace.s3,
              children: [
                PindoroIcon(
                  PindoroGlyph.flag,
                  size: PindoroSize.iconLg,
                  color: c.leagueGold,
                  cut: c.streetCardBg,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: PindoroType.headlineSm.copyWith(
                          color: c.streetCardText,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: PindoroType.labelMd.copyWith(
                          color: c.streetCardSubtext,
                        ),
                      ),
                    ],
                  ),
                ),
                _Ladder(tier: tier, tiers: tiers),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Ladder extends StatelessWidget {
  const _Ladder({required this.tier, required this.tiers});

  final int tier;
  final int tiers;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: PindoroSpace.s1,
      children: [
        for (var i = 0; i < tiers; i++)
          Container(
            key: ValueKey('ladder-$i'),
            width: 12,
            height: i == tier ? 28 : 20,
            decoration: BoxDecoration(
              color: i == tier ? c.leagueGold : c.leagueLadder,
              borderRadius: BorderRadius.circular(PindoroRadius.xs),
            ),
          ),
      ],
    );
  }
}

/// One player in a league (`.pd-li` with `.pd-rank` and `.pd-avatar`): the
/// rank (a medal for 1–3), [initials] on avatar colour [avatar] (0–3), the
/// [name] and [xp]; on `color.primary.soft` when it is [you].
class LeagueRow extends StatelessWidget {
  const LeagueRow({
    super.key,
    required this.rank,
    required this.name,
    required this.xp,
    required this.initials,
    required this.avatar,
    required this.semanticLabel,
    this.you = false,
  });

  final int rank;
  final String name;
  final String xp;
  final String initials;
  final int avatar;
  final bool you;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final back = you ? c.primarySoft : c.surfaceRaised;
    final medal = switch (rank) {
      1 => c.leagueGold,
      2 => c.leagueSilver,
      3 => c.leagueBronze,
      _ => null,
    };
    return ColoredBox(
      color: back,
      child: ListRow(
        title: name,
        semanticsLabel: semanticLabel,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: PindoroSpace.s3,
          children: [
            SizedBox(
              width: 30,
              child: Center(
                child: medal == null
                    ? Text(
                        '$rank',
                        style: PindoroType.titleLg.copyWith(
                          color: c.textPrimary,
                        ),
                      )
                    : PindoroIcon(PindoroGlyph.medal, color: medal, cut: back),
              ),
            ),
            _Avatar(initials, color: _avatarColors(c)[avatar % 4]),
          ],
        ),
        trailing: Text(
          xp,
          style: PindoroType.labelLg.copyWith(color: c.textSecondary),
        ),
      ),
    );
  }

  static List<Color> _avatarColors(PindoroColors c) => [
    c.avatar1,
    c.avatar2,
    c.avatar3,
    c.avatar4,
  ];
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.initials, {required this.color});

  final String initials;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: Text(
      initials,
      style: PindoroType.labelLg.copyWith(
        color: PindoroTheme.of(context).colors.avatarText,
      ),
    ),
  );
}

/// A league's promotion or demotion line (`.pd-zone`): a chevron up or down
/// and [label], in `color.league.promote` / `color.league.demote`.
class ZoneDivider extends StatelessWidget {
  const ZoneDivider({super.key, required this.label, required this.up});

  final String label;
  final bool up;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final ink = up ? c.leaguePromote : c.leagueDemote;
    // Its own node, read between the rows it separates.
    return Semantics(
      container: true,
      child: ColoredBox(
        color: c.surfaceRaised,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PindoroSpace.s4,
            vertical: PindoroSpace.s2,
          ),
          child: Row(
            spacing: PindoroSpace.s2,
            children: [
              RotatedBox(
                quarterTurns: up ? 2 : 0,
                child: PindoroIcon(
                  PindoroGlyph.chevronDown,
                  size: 16,
                  color: ink,
                ),
              ),
              Expanded(
                child: Text(
                  label,
                  style: PindoroType.labelMd.copyWith(color: ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
