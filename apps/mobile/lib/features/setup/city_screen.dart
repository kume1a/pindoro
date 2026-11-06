import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

import '../../app/database.dart';
import '../../app/format.dart';
import '../../app/location.dart';
import '../../app/page_scaffold.dart';
import '../../app/router.dart';
import '../../app/settings.dart';
import '../../app/toast.dart';
import '../pack/cities.dart';
import '../pack/pack_store.dart';
import '../pack/sqlite_pack_repository.dart';

enum _Locating { idle, busy, denied }

/// Pick a city the app has a pack for: search, "Use my location", recents.
class CityScreen extends ConsumerStatefulWidget {
  const CityScreen({super.key});

  @override
  ConsumerState<CityScreen> createState() => _CityScreenState();
}

class _CityScreenState extends ConsumerState<CityScreen> {
  final _query = TextEditingController();
  _Locating _locating = _Locating.idle;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _pick(String cityId) async {
    ref.read(feedbackProvider).tap();
    final db = ref.read(databaseProvider);
    final settings = await db.readSettings();
    await db.updateSettings(
      UserSettingsCompanion(
        lastCity: Value(cityId),
        // Another city's area doesn't apply here.
        lastAreaJson: cityId == settings.lastCity
            ? const Value.absent()
            : const Value(null),
      ),
    );
    if (mounted) await context.push(Routes.area);
  }

  Future<void> _useLocation() async {
    final location = ref.read(locationServiceProvider);
    if (_locating == _Locating.denied) {
      await location.openSettings();
      return;
    }
    setState(() => _locating = _Locating.busy);
    final result = await location.locate();
    if (!mounted) return;
    switch (result) {
      case LocationDenied():
        setState(() => _locating = _Locating.denied);
      case Located(:final position):
        setState(() => _locating = _Locating.idle);
        final pack = await ref.read(packRepositoryProvider.future);
        final city = pack.city();
        final here = city.boundary.any((p) => polygonContains(p, position));
        if (!mounted) return;
        if (here) {
          await _pick(city.id);
        } else {
          showToast(context, context.l10n.cityNoneNearby);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final cities = ref.watch(cityListProvider).value ?? const [];
    final recentIds = ref.watch(recentCityIdsProvider).value ?? const [];
    final georgian = Localizations.localeOf(context).languageCode == 'ka';
    String name(CatalogCity city) => georgian ? city.nameKa : city.nameEn;
    String other(CatalogCity city) => georgian ? city.nameEn : city.nameKa;
    Widget row(CatalogCity city) => ListRow(
      title: name(city),
      subtitle: other(city),
      leading: const RowTile(child: PindoroIcon(PindoroGlyph.city)),
      trailing: const PindoroIcon(PindoroGlyph.chevronRight),
      onTap: () => unawaited(_pick(city.id)),
    );

    final query = _query.text.trim().toLowerCase();
    final results = [
      for (final city in cities)
        if (city.nameKa.toLowerCase().contains(query) ||
            city.nameEn.toLowerCase().contains(query))
          city,
    ];
    final recents = [
      for (final id in recentIds) ...cities.where((city) => city.id == id),
    ];
    final others = [
      for (final city in cities)
        if (!recentIds.contains(city.id)) city,
    ];

    return PageScaffold(
      title: l10n.commonChooseCity,
      children: [
        SearchField(
          controller: _query,
          placeholder: l10n.citySearchHint,
          clearLabel: l10n.cityClearSearch,
          onChanged: (_) => setState(() {}),
        ),
        if (query.isNotEmpty) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.cityResultCount(results.length),
              style: PindoroType.labelLg.copyWith(color: c.textSecondary),
            ),
          ),
          if (results.isEmpty)
            Column(
              spacing: PindoroSpace.s2,
              children: [
                Text(
                  l10n.cityNoResultsTitle(_query.text.trim()),
                  textAlign: TextAlign.center,
                  style: PindoroType.titleMd.copyWith(color: c.textPrimary),
                ),
                Text(
                  l10n.cityNoResultsBody,
                  textAlign: TextAlign.center,
                  style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
                ),
              ],
            )
          else
            ListGroup(children: [for (final city in results) row(city)]),
        ] else ...[
          ListGroup(
            children: [
              ListRow(
                title: l10n.cityUseLocation,
                subtitle: switch (_locating) {
                  _Locating.idle => l10n.cityUseLocationSubtitle,
                  _Locating.busy => l10n.cityLocationLocating,
                  _Locating.denied => l10n.cityLocationDenied,
                },
                leading: const RowTile(child: PindoroIcon(PindoroGlyph.locate)),
                trailing: _locating == _Locating.busy
                    ? const LaneLoader()
                    : null,
                onTap: _locating == _Locating.busy
                    ? null
                    : () => unawaited(_useLocation()),
              ),
            ],
          ),
          if (recents.isNotEmpty) ...[
            SectionTitle(l10n.cityRecent),
            ListGroup(children: [for (final city in recents) row(city)]),
          ],
          if (others.isNotEmpty) ...[
            SectionTitle(l10n.cityAll),
            ListGroup(children: [for (final city in others) row(city)]),
          ],
        ],
      ],
    );
  }
}
