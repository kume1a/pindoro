import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/badges/data/badge_data.dart';
import 'package:pindoro/features/badges/ui/badge_look.dart';
import 'package:pindoro/features/learning/data/drive_log.dart';
import 'package:pindoro/features/me/data/me_data.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Four stats, the badges and the cities with their City memory (design
/// system Bottom nav, Me); Settings from the gear.
class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).value;
    final badges = ref.watch(badgesProvider).value;
    final fresh = ref.watch(newBadgesProvider).value ?? const {};
    final l10n = context.l10n;
    return PageScaffold(
      title: l10n.meTitle,
      showBack: false,
      trailing: PindoroIconButton(
        glyph: PindoroGlyph.settings,
        semanticLabel: l10n.a11ySettings,
        onPressed: () => unawaited(context.push(Routes.settings)),
      ),
      children: me == null ? const [] : _content(context, me, badges, fresh),
    );
  }

  List<Widget> _content(
    BuildContext context,
    MeData me,
    List<BadgeView>? badges,
    Set<String> fresh,
  ) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    return [
      if (me.since case final since?)
        Text(
          l10n.mePlayingSince(_month(context, since)),
          style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
        ),
      TileGrid([
        StatTile(
          glyph: PindoroGlyph.checkCircle,
          label: l10n.meStreetsInMemory,
          value: formatNumber(
            me.cities.fold(0, (sum, city) => sum + city.count.known),
          ),
        ),
        StatTile(
          glyph: PindoroGlyph.pin,
          label: l10n.mePins,
          value: formatNumber(me.pins),
        ),
        StatTile(
          glyph: PindoroGlyph.calendar,
          label: l10n.meCountedDays,
          value: formatNumber(me.countedDays),
        ),
        StatTile(
          glyph: PindoroGlyph.flame,
          glyphColor: c.streakFlame,
          label: l10n.meBestStreak,
          value: l10n.meDays(me.bestStreak),
          onTap: () => unawaited(context.push(Routes.streak)),
        ),
      ]),
      if (badges != null) ...[
        SectionTitle(
          l10n.meBadges(badges.where((b) => b.earned).length, badges.length),
        ),
        TileGrid(columns: 3, [
          for (final b in badges)
            BadgeShelfTile(b, isNew: fresh.contains(b.id)),
        ]),
      ],
      SectionTitle(l10n.meCities),
      ListGroup(children: [for (final city in me.cities) _CityRow(city)]),
      SectionTitle(l10n.meDrives),
      ListGroup(
        children: [
          ListRow(
            title: l10n.driveTitle,
            subtitle: l10n.driveRuleMap,
            leading: const RowTile(PindoroGlyph.route),
            trailing: const PindoroIcon(PindoroGlyph.chevronRight),
            onTap: () => unawaited(context.push(Routes.drive)),
          ),
          const _DrivesRow(),
        ],
      ),
    ];
  }
}

/// Past drives, with how many there are.
class _DrivesRow extends ConsumerWidget {
  const _DrivesRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final count = ref.watch(pastDrivesProvider).value?.length ?? 0;
    return ListRow(
      title: l10n.pastDrivesTitle,
      subtitle: l10n.meDrivesCount(count),
      leading: const RowTile(PindoroGlyph.car),
      trailing: const PindoroIcon(PindoroGlyph.chevronRight),
      onTap: () => unawaited(context.push(Routes.pastDrives)),
    );
  }
}

/// "November", or "November 2025" when it isn't this year.
String _month(BuildContext context, DateTime day) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  final format = day.year == DateTime.now().year
      ? DateFormat.LLLL(locale)
      : DateFormat.yMMMM(locale);
  return format.format(day);
}

/// A city with its City memory; a tap makes it the city and opens Today.
class _CityRow extends ConsumerWidget {
  const _CityRow(this.city);

  final MeCity city;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final name = context.localName(ka: city.nameKa, en: city.nameEn);
    final known = formatNumber(city.count.known);
    final total = formatNumber(city.count.total);
    return ListRow(
      title: name,
      subtitle: l10n.meCityStreets(known, total),
      below: Minibar(value: city.count.fraction),
      leading: const RowTile(PindoroGlyph.pin),
      trailing: const PindoroIcon(PindoroGlyph.chevronRight),
      semanticsLabel: l10n.a11yCityMemoryRow(name, known, total),
      onTap: () async {
        await ref.read(settingsDaoProvider).chooseCity(city.id);
        if (context.mounted) context.go(Routes.today);
      },
    );
  }
}
