import 'package:flutter/widgets.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// Crossings per street: counting walks the city's streets, once is enough.
final _crossings = Expando<int>();

/// A new street's intro lines (Intro sheet): where it lies from the centre,
/// and its length, type and crossings.
({String where, String facts}) streetFacts(
  BuildContext context,
  NamedStreet street,
  Iterable<NamedStreet> others,
  LatLng cityCenter,
) {
  final l10n = context.l10n;
  final type = roadTypeOf(street.parts.first.roadClass);
  final crossings = _crossings[street] ??= crossingCount(street, {...others});
  return (
    where: l10n.lessonWhere(
      l10n.lessonRoadType(type.name),
      directionFromCentre(street, cityCenter)?.name ?? 'centre',
    ),
    facts: l10n.lessonFacts(
      crossings,
      formatSize(street.lengthM, l10n),
      l10n.lessonRoadTypeWord(type.name),
    ),
  );
}
