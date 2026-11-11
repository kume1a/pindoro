import 'package:flutter/widgets.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/features/badges/data/badge_data.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

PindoroGlyph badgeGlyph(BadgeId id) => switch (id) {
  BadgeId.firstPin => PindoroGlyph.pinDrop,
  BadgeId.bullseye => PindoroGlyph.star,
  BadgeId.onFire => PindoroGlyph.flame,
  BadgeId.navigator => PindoroGlyph.district,
  BadgeId.roadTrip => PindoroGlyph.car,
  BadgeId.nightOwl => PindoroGlyph.moon,
  BadgeId.explorer => PindoroGlyph.globe,
  BadgeId.pitCrew => PindoroGlyph.wrench,
};

Color badgeField(PindoroColors c, BadgeId id) => switch (id) {
  BadgeId.firstPin => c.badgeFirstPin,
  BadgeId.bullseye => c.badgeBullseye,
  BadgeId.onFire => c.badgeOnFire,
  BadgeId.navigator => c.badgeNavigator,
  BadgeId.roadTrip => c.badgeRoadTrip,
  BadgeId.nightOwl => c.badgeNightOwl,
  BadgeId.explorer => c.badgeExplorer,
  BadgeId.pitCrew => c.badgePitCrew,
};

/// A badge on Me's shelf, with its progress while locked and countable.
class BadgeShelfTile extends StatelessWidget {
  const BadgeShelfTile(this.badge, {super.key, this.isNew = false});

  final BadgeView badge;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (:id, progress: (:value, :target), :earned) = badge;
    final name = l10n.badgeName(id.name);
    final countable = !earned && target > 1;
    return BadgeTile(
      glyph: badgeGlyph(id),
      field: badgeField(PindoroTheme.of(context).colors, id),
      name: name,
      condition: l10n.badgeCondition(id.name),
      locked: !earned,
      progress: countable ? value / target : null,
      newLabel: isNew && earned ? l10n.badgeNew : null,
      semanticLabel: earned
          ? l10n.a11yBadgeEarned(name)
          : countable
          ? l10n.a11yBadgeProgress(name, value, target)
          : l10n.a11yBadgeLocked(name),
    );
  }
}
