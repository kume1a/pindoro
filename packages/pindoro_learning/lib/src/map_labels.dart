import 'package:pindoro_core/pindoro_core.dart';

import 'constants.dart';
import 'names.dart';

/// A street named on a map, and where its name goes.
typedef StreetLabel = ({NamedStreet street, LatLng at});

/// The streets an intro or a reveal names around [target] (SPEC §16.18): its [family] first,
/// then the streets crossing it nearest its middle first, then the nearest others, at most
/// [LearningConfig.streetLabelMax]. A crossing street's name sits on its own line
/// [LearningConfig.streetLabelOffsetM] from the junction; any other at its point nearest the
/// target's middle.
List<StreetLabel> labelStreets(
  NamedStreet target,
  Iterable<NamedStreet> others, {
  Set<String> family = const {},
}) {
  final middle = target.parts.first.midpoint;
  final crossings = {
    for (final c in crossingsAlong(target, others)) c.street.id: c.at,
  };
  (int, double) rank(NamedStreet s) => switch (crossings[s.id]) {
    _ when family.contains(s.id) => (
      0,
      distanceBetween(middle, s.parts.first.midpoint),
    ),
    final junction? => (1, distanceBetween(middle, junction)),
    null => (2, distanceBetween(middle, s.parts.first.midpoint)),
  };
  final ranked =
      [
        for (final s in others)
          if (s.id != target.id && s.name != target.name)
            (street: s, rank: rank(s)),
      ]..sort((a, b) {
        final byGroup = a.rank.$1.compareTo(b.rank.$1);
        return byGroup != 0 ? byGroup : a.rank.$2.compareTo(b.rank.$2);
      });
  return [
    for (final r in ranked.take(LearningConfig.streetLabelMax))
      (
        street: r.street,
        at: switch (crossings[r.street.id]) {
          final junction? => _offJunction(r.street, junction),
          null => r.street.nearest(middle).nearestPoint,
        },
      ),
  ];
}

/// The point of [street] about [LearningConfig.streetLabelOffsetM] from [junction] along it.
LatLng _offJunction(NamedStreet street, LatLng junction) {
  final ends = [
    for (final piece in clipToCircle(
      street.geometry,
      junction,
      LearningConfig.streetLabelOffsetM,
    )) ...[piece.first, piece.last],
  ];
  return ends.fold(
    junction,
    (far, p) =>
        distanceBetween(junction, p) > distanceBetween(junction, far) ? p : far,
  );
}

/// Whether a place called [placeName] gives [street]'s name away: they share a word stem of
/// [_stemLength] letters, in either script (a metro station named after its avenue).
bool namesStreet(String placeName, NamedStreet street) {
  final place = nameBase(placeName);
  final placeStems = _stems({place, transliterate(place)});
  return placeStems.isNotEmpty &&
      _stems(nameForms(street)).any(placeStems.contains);
}

/// Long enough to skip short words ("შოთა"), short enough that "რუსთაველი" and "რუსთაველის"
/// meet.
const int _stemLength = 5;

Set<String> _stems(Iterable<String> names) => {
  for (final name in names)
    for (final word in name.split(' '))
      if (word.length >= _stemLength) word.substring(0, _stemLength),
};
