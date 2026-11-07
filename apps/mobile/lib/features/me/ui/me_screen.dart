import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/me/data/me_data.dart';
import 'package:pindoro/features/progress/ui/level_card.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Level, four stats and the cities with progress (canvas MeScreen);
/// Settings from the gear.
class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).value;
    final l10n = context.l10n;
    return PageScaffold(
      title: l10n.meTitle,
      showBack: false,
      trailing: PindoroIconButton(
        glyph: PindoroGlyph.settings,
        semanticLabel: l10n.a11ySettings,
        onPressed: () => unawaited(context.push(Routes.settings)),
      ),
      children: me == null ? const [] : _content(context, me),
    );
  }

  List<Widget> _content(BuildContext context, MeData me) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final total = formatNumber(me.totalXp);
    final level = progressWithinLevel(me.totalXp);
    final known = me.cities.fold(0, (sum, city) => sum + city.count.known);
    return [
      LevelCard(
        level: level,
        subtitle: switch (me.since) {
          final since? => l10n.meXpSince(total, _month(context, since)),
          null => l10n.homeXpTotal(total),
        },
        caption: toNextLevelLabel(l10n, level),
      ),
      _TileGrid([
        StatTile(
          glyph: PindoroGlyph.pin,
          label: l10n.meStreetsKnown,
          value: formatNumber(known),
        ),
        // ponytail: lessons arrive in R4b and road trips in R4c.
        StatTile(
          glyph: PindoroGlyph.road,
          label: l10n.meLessons,
          value: formatNumber(0),
        ),
        StatTile(
          glyph: PindoroGlyph.car,
          label: l10n.meRoadTrips,
          value: formatNumber(0),
        ),
        StatTile(
          glyph: PindoroGlyph.flame,
          glyphColor: c.streakFlame,
          label: l10n.meBestStreak,
          value: l10n.meDays(me.bestStreak),
          onTap: () => unawaited(context.push(Routes.streak)),
        ),
      ]),
      SectionTitle(l10n.meCities),
      ListGroup(children: [for (final city in me.cities) _CityRow(city)]),
    ];
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

/// Two tiles a row, 8 dp apart, each row as tall as its taller tile.
class _TileGrid extends StatelessWidget {
  const _TileGrid(this.tiles);

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => Column(
    spacing: PindoroSpace.s2,
    children: [
      for (var i = 0; i < tiles.length; i += 2)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: PindoroSpace.s2,
            children: [
              for (final tile in tiles.skip(i).take(2)) Expanded(child: tile),
            ],
          ),
        ),
    ],
  );
}

/// A city with its known streets; a tap plays there in Free play.
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
      semanticsLabel: l10n.a11yDistrictRow(name, known, total),
      onTap: () async {
        await ref.read(settingsDaoProvider).chooseCity(city.id);
        if (context.mounted) context.go(Routes.home);
      },
    );
  }
}
