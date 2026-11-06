import 'package:flutter/widgets.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../l10n/app_localizations.dart';
import 'database.dart';
import 'format.dart';

/// A district's name per the street-name setting.
String districtName(District d, Settings? settings) =>
    settings?.streetNames == StreetNameMode.english
    ? d.nameEn ?? d.nameKa
    : d.nameKa;

/// "Vake and Vere", "Vake + 2 more", "2 km circle", "2.6 × 3 km rectangle".
String areaLabel(
  BuildContext context,
  Area area,
  PackRepository pack,
  Settings? settings,
) {
  final l10n = AppLocalizations.of(context);
  final locale = Localizations.localeOf(context);
  return switch (area) {
    DistrictsArea(:final ids) => districtNames(l10n, [
      for (final d in pack.districts())
        if (ids.contains(d.id)) districtName(d, settings),
    ]),
    CircleArea(:final radiusM) => l10n.areaCircleName(
      formatSize(radiusM, locale),
    ),
    RectArea(:final bounds) => l10n.areaRectangleName(
      formatSides(
        distanceBetween(
          LatLng(bounds.minLat, bounds.minLon),
          LatLng(bounds.minLat, bounds.maxLon),
        ),
        distanceBetween(
          LatLng(bounds.minLat, bounds.minLon),
          LatLng(bounds.maxLat, bounds.minLon),
        ),
        locale,
      ),
    ),
  };
}

/// One, two, or "first + n more" district names.
String districtNames(AppLocalizations l10n, List<String> names) =>
    switch (names) {
      [] => '',
      [final one] => one,
      [final a, final b] => l10n.areaNamesTwo(a, b),
      [final first, ...final rest] => l10n.areaNamesMore(first, rest.length),
    };
