import 'package:flutter/widgets.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// A district's name per the street-name setting.
String districtName(District d, Settings? settings) =>
    _byNameSetting(d.nameKa, d.nameEn, settings);

/// A street's name per the street-name setting.
String streetName(NamedStreet s, Settings? settings) =>
    _byNameSetting(s.name, s.nameEn, settings);

String _byNameSetting(String local, String? english, Settings? settings) =>
    settings?.streetNames == StreetNameMode.english ? english ?? local : local;

/// "Vake and Vere", "Vake + 2 more", "2 km circle", "2.6 × 3 km rectangle";
/// districts in the order the area picker lists them (by shown name).
String areaLabel(
  BuildContext context,
  Area area,
  PackRepository pack,
  Settings? settings,
) {
  final l10n = AppLocalizations.of(context);
  return switch (area) {
    DistrictsArea(:final ids) => districtNames(
      l10n,
      [
        for (final d in pack.districts())
          if (ids.contains(d.id)) districtName(d, settings),
      ]..sort(),
    ),
    CircleArea(:final radiusM) => l10n.areaCircleName(
      formatSize(radiusM, l10n),
    ),
    RectArea(:final bounds) => l10n.areaRectangleName(
      formatSides(bounds.widthM, bounds.heightM, l10n),
    ),
  };
}

/// "Tbilisi · Vake and Vere · Medium": what Play starts or resumes.
String resumeLabel(
  BuildContext context,
  PackRepository pack,
  Area area,
  Difficulty difficulty,
  Settings? settings,
) {
  final city = pack.city();
  return [
    context.localName(ka: city.nameKa, en: city.nameEn),
    areaLabel(context, area, pack, settings),
    difficultyName(AppLocalizations.of(context), difficulty),
  ].join(' · ');
}

/// One, two, or "first + n more" district names.
String districtNames(AppLocalizations l10n, List<String> names) =>
    switch (names) {
      [] => '',
      [final one] => one,
      [final a, final b] => l10n.areaNamesTwo(a, b),
      [final first, ...final rest] => l10n.areaNamesMore(first, rest.length),
    };

/// A difficulty level's localised name.
String difficultyName(AppLocalizations l10n, Difficulty d) => switch (d) {
  Difficulty.easy => l10n.difficultyEasy,
  Difficulty.medium => l10n.difficultyMedium,
  Difficulty.hard => l10n.difficultyHard,
  Difficulty.expert => l10n.difficultyExpert,
};

/// A tier's localised label.
String tierLabel(AppLocalizations l10n, Tier tier) => switch (tier) {
  Tier.perfect => l10n.tierPerfect,
  Tier.great => l10n.tierGreat,
  Tier.close => l10n.tierClose,
  Tier.miss => l10n.tierMiss,
};

/// A tier as one word, for result rows.
String tierWord(AppLocalizations l10n, Tier tier) => switch (tier) {
  Tier.perfect => l10n.tierPerfectWord,
  Tier.great => l10n.tierGreatWord,
  Tier.close => l10n.tierClose,
  Tier.miss => l10n.tierMissWord,
};
