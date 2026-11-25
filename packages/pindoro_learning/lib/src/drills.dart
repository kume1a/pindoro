import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'cards.dart';
import 'constants.dart';
import 'curriculum.dart';
import 'labels.dart';

/// A family sweep (SPEC §7): a parent and the P cards (stored item ids) of its children due
/// within [LearningConfig.familySweepWindowDays], most at risk first.
typedef FamilySweep = ({String parentId, List<String> children});

/// A crossings drill (SPEC §7): drive along [streetId] from [fromId] and name the Known streets
/// it crosses, in order ([crossings], street ids).
typedef CrossingsDrill = ({
  String streetId,
  String fromId,
  List<String> crossings,
});

/// What a session drills besides its cards (SPEC §7, §16.13). The sweep grades its children's
/// P cards; crossings and bearings ([bearings], street ids, asked from the city centre) are only
/// logged.
class Drills {
  const Drills({this.sweep, this.crossings, this.bearings = const []});

  static const none = Drills();

  final FamilySweep? sweep;
  final CrossingsDrill? crossings;
  final List<String> bearings;
}

/// Today's drills (SPEC §7): at most one family sweep, one crossings drill a day (none once
/// [today] holds one) and 1–3 bearings once a raion's grid is half Solid. [cards] are P cards by
/// street id; [streets] every street of the city. Same inputs and [seed], same drills.
Drills planDrills({
  required Curriculum curriculum,
  required Iterable<NamedStreet> streets,
  required Map<String, CardState> cards,
  required Iterable<LogEntry> today,
  required LatLng centre,
  required DateTime now,
  required int seed,
}) {
  final all = streets.toSet();
  final random = Random(seed);
  return Drills(
    sweep: familySweep(curriculum: curriculum, cards: cards, now: now),
    crossings:
        {
              for (final e in today)
                if (e.format == ReviewFormat.crossings) e.sessionId,
            }.length >=
            LearningConfig.crossingsPerDay
        ? null
        : crossingsDrill(
            curriculum: curriculum,
            streets: all,
            cards: cards,
            now: now,
            random: random,
          ),
    bearings: bearingTargets(
      curriculum: curriculum,
      streets: all,
      cards: cards,
      centre: centre,
      random: random,
    ),
  );
}

/// The family with the most children due within [LearningConfig.familySweepWindowDays], when it
/// has [LearningConfig.familySweepMinChildren] or more; up to [LearningConfig.familySweepMax] of
/// them, earliest due first.
FamilySweep? familySweep({
  required Curriculum curriculum,
  required Map<String, CardState> cards,
  required DateTime now,
}) {
  final by = now.add(
    const Duration(days: LearningConfig.familySweepWindowDays),
  );
  final due = <String, List<CardState>>{};
  for (final MapEntry(key: street, value: card) in cards.entries) {
    final parent = curriculum.parentOf(street);
    if (parent != null && isDueBefore(card, by)) {
      due.putIfAbsent(parent, () => []).add(card);
    }
  }
  final best = due.entries
      .where((e) => e.value.length >= LearningConfig.familySweepMinChildren)
      .fold<MapEntry<String, List<CardState>>?>(
        null,
        (best, e) =>
            best == null ||
                e.value.length > best.value.length ||
                (e.value.length == best.value.length &&
                    e.key.compareTo(best.key) < 0)
            ? e
            : best,
      );
  if (best == null) return null;
  final children = best.value
    ..sort((a, b) {
      final byDue = a.dueAt!.compareTo(b.dueAt!);
      return byDue != 0 ? byDue : a.itemId.compareTo(b.itemId);
    });
  return (
    parentId: best.key,
    children: [
      for (final c in children.take(LearningConfig.familySweepMax)) c.itemId,
    ],
  );
}

/// A Solid parent or tier A or B street with two or more Known crossings after its first one,
/// from a seeded end; up to [LearningConfig.crossingsMax] of them.
CrossingsDrill? crossingsDrill({
  required Curriculum curriculum,
  required Set<NamedStreet> streets,
  required Map<String, CardState> cards,
  required DateTime now,
  required Random random,
}) {
  bool known(NamedStreet s) => switch (cards[s.id]) {
    final c? => isKnown(c, now),
    null => false,
  };
  final candidates = [
    for (final s in streets)
      if ((cards[s.id]?.isSolid ?? false) &&
          (curriculum.tierOf(s.id) != StreetTier.c ||
              curriculum.childrenOf(s.id).isNotEmpty))
        s,
  ]..sort((a, b) => a.id.compareTo(b.id));
  candidates.shuffle(random);
  for (final street in candidates.take(LearningConfig.crossingsTries)) {
    final along = crossingsAlong(street, streets);
    final ordered = random.nextBool() ? along : along.reversed.toList();
    if (ordered.isEmpty) continue;
    final asked = ordered
        .skip(1)
        .map((c) => c.street)
        .where(known)
        .take(LearningConfig.crossingsMax)
        .toList();
    if (asked.length >= LearningConfig.crossingsMin) {
      return (
        streetId: street.id,
        fromId: ordered.first.street.id,
        crossings: [for (final s in asked) s.id],
      );
    }
  }
  return null;
}

/// Solid core streets to point at from the city [centre] (SPEC §7): in raions whose core tier B
/// streets are [LearningConfig.bearingUnlockGridSolid] Solid, beyond [centreRadiusM]; 1–3,
/// seeded.
List<String> bearingTargets({
  required Curriculum curriculum,
  required Set<NamedStreet> streets,
  required Map<String, CardState> cards,
  required LatLng centre,
  required Random random,
}) {
  bool solid(NamedStreet s) => cards[s.id]?.isSolid ?? false;
  final grid = <String, List<NamedStreet>>{};
  final byRaion = <String, List<NamedStreet>>{};
  for (final s in streets.where(Curriculum.isCore)) {
    final raion = curriculum.raionOf(s.id);
    if (raion == null) continue;
    byRaion.putIfAbsent(raion, () => []).add(s);
    if (curriculum.tierOf(s.id) == StreetTier.b) {
      grid.putIfAbsent(raion, () => []).add(s);
    }
  }
  final targets = [
    for (final MapEntry(key: raion, value: tierB) in grid.entries)
      if (tierB.where(solid).length / tierB.length >=
          LearningConfig.bearingUnlockGridSolid)
        for (final s in byRaion[raion]!)
          if (solid(s) &&
              distanceBetween(centre, s.parts.first.midpoint) >= centreRadiusM)
            s.id,
  ]..sort();
  if (targets.isEmpty) return const [];
  const spread =
      LearningConfig.bearingsPerSessionMax -
      LearningConfig.bearingsPerSessionMin;
  final count =
      LearningConfig.bearingsPerSessionMin + random.nextInt(spread + 1);
  return (targets..shuffle(random)).take(count).toList();
}
