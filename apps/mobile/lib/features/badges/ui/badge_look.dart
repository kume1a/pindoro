import 'package:flutter/widgets.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/features/badges/data/badge_data.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// How a stored badge id looks: its glyph, field colour, name and condition.
typedef BadgeLook = ({
  PindoroGlyph glyph,
  Color field,
  String name,
  String condition,
});

BadgeLook badgeLook(BuildContext context, String id) {
  final l10n = context.l10n;
  final c = PindoroTheme.of(context).colors;
  if (cityMemoryBadgeTarget(id) case final milestone?) {
    final n = formatNumber(milestone);
    return (
      glyph: PindoroGlyph.chart,
      field: c.badgeCityMemory,
      name: l10n.badgeCityMemory(n),
      condition: l10n.badgeCityMemoryCondition(n),
    );
  }
  final badge = BadgeId.values.byName(id);
  return (
    glyph: switch (badge) {
      BadgeId.firstPin => PindoroGlyph.pinDrop,
      BadgeId.bullseye => PindoroGlyph.star,
      BadgeId.onFire => PindoroGlyph.flame,
      BadgeId.navigator => PindoroGlyph.district,
      BadgeId.local => PindoroGlyph.neighbourhood,
      BadgeId.keeper => PindoroGlyph.calendar,
      BadgeId.clearRoad => PindoroGlyph.road,
      BadgeId.nightOwl => PindoroGlyph.moon,
      BadgeId.explorer => PindoroGlyph.globe,
      BadgeId.roadTrip => PindoroGlyph.car,
      BadgeId.pitCrew => PindoroGlyph.wrench,
    },
    field: switch (badge) {
      BadgeId.firstPin => c.badgeFirstPin,
      BadgeId.bullseye => c.badgeBullseye,
      BadgeId.onFire => c.badgeOnFire,
      BadgeId.navigator => c.badgeNavigator,
      BadgeId.local => c.badgeLocal,
      BadgeId.keeper => c.badgeKeeper,
      BadgeId.clearRoad => c.badgeClearRoad,
      BadgeId.nightOwl => c.badgeNightOwl,
      BadgeId.explorer => c.badgeExplorer,
      BadgeId.roadTrip => c.badgeRoadTrip,
      BadgeId.pitCrew => c.badgePitCrew,
    },
    name: l10n.badgeName(badge.name),
    condition: l10n.badgeCondition(badge.name),
  );
}

/// A badge on Me's shelf, with its progress while locked and countable.
class BadgeShelfTile extends StatelessWidget {
  const BadgeShelfTile(this.badge, {super.key, this.isNew = false});

  final BadgeView badge;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (:id, progress: (:value, :target), :earned, :retired) = badge;
    final look = badgeLook(context, id);
    final countable = !earned && target > 1;
    return BadgeTile(
      glyph: look.glyph,
      field: look.field,
      name: look.name,
      condition: look.condition,
      locked: !earned,
      progress: countable ? value / target : null,
      newLabel: isNew && earned ? l10n.badgeNew : null,
      retiredLabel: retired ? l10n.badgeRetired : null,
      semanticLabel: retired
          ? l10n.a11yBadgeRetired(look.name)
          : earned
          ? l10n.a11yBadgeEarned(look.name)
          : countable
          ? l10n.a11yBadgeProgress(
              look.name,
              formatNumber(value),
              formatNumber(target),
            )
          : l10n.a11yBadgeLocked(look.name),
    );
  }
}
