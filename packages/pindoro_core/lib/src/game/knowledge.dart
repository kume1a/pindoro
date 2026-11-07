import '../scoring/scoring.dart';
import 'named_street.dart';

/// What the player has shown about a street (a [NamedStreet], by its id).
enum StreetKnowledge { unknown, missed, known }

/// Great or Perfect: the street is known; it never reverts in the MVP.
bool isKnownTier(Tier tier) => tier == Tier.perfect || tier == Tier.great;

/// Close or Miss: the street comes back in a retry round.
bool isRetryTier(Tier tier) => !isKnownTier(tier);

StreetKnowledge knowledgeFrom(Tier? bestTier) => switch (bestTier) {
  null => StreetKnowledge.unknown,
  final tier when isKnownTier(tier) => StreetKnowledge.known,
  _ => StreetKnowledge.missed,
};

/// The best tier per id among [answers].
Map<String, Tier> bestTiers(Iterable<(String id, Tier tier)> answers) {
  final best = <String, Tier>{};
  for (final (id, tier) in answers) {
    final current = best[id];
    if (current == null || tier.index < current.index) best[id] = tier;
  }
  return best;
}

/// Best tier per street id, from best tiers per answered part id; parts no
/// longer in [streets] are skipped.
Map<String, Tier> bestTierPerStreet(
  Map<String, Tier> bestByPart,
  Map<String, NamedStreet> streets,
) => bestTiers([
  for (final MapEntry(key: partId, value: tier) in bestByPart.entries)
    if (streets[partId] case final street?) (street.id, tier),
]);

/// Street ids with a Great or Perfect, from best tiers per answered part id.
Set<String> knownStreetIds(
  Map<String, Tier> bestByPart,
  Map<String, NamedStreet> streets,
) => {
  for (final MapEntry(key: id, value: tier) in bestTierPerStreet(
    bestByPart,
    streets,
  ).entries)
    if (isKnownTier(tier)) id,
};

/// Streets with a Great or Perfect in a round that weren't known before it.
Set<String> newlyKnown({
  required Set<String> knownBefore,
  required Iterable<({String street, Tier tier})> roundAnswers,
}) => {
  for (final a in roundAnswers)
    if (isKnownTier(a.tier) && !knownBefore.contains(a.street)) a.street,
};

typedef KnownCount = ({int known, int total});

extension KnownShare on KnownCount {
  /// Known streets as a share of all, 0 when there are none.
  double get fraction => total == 0 ? 0 : known / total;
}

typedef KnownCounts = ({KnownCount city, Map<String, KnownCount> byDistrict});

/// Known / total streets for the city and each district.
KnownCounts knownCounts({
  required Map<String, NamedStreet> streets,
  required Map<String, Set<String>> partsByDistrict,
  required Set<String> known,
}) {
  KnownCount count(Set<String> ids) =>
      (known: ids.where(known.contains).length, total: ids.length);
  return (
    city: count({for (final s in streets.values) s.id}),
    byDistrict: {
      for (final MapEntry(key: id, value: parts) in partsByDistrict.entries)
        id: count({for (final p in parts) ?streets[p]?.id}),
    },
  );
}
