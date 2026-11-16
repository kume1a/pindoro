import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';

import 'cards.dart';
import 'constants.dart';
import 'planner.dart';
import 'stats.dart';

/// The order new streets are taught in (SPEC §6, §16.5): placement first, then the skeleton and
/// the grid city-wide by ring and bank, and the rest chunk by chunk. Built once per pack; [next]
/// is pure over the cards.
///
/// Streets are [NamedStreet]s and take their longest part's tier, ring, bank and chunk. A pack
/// older than format 4 has none of these: every street is then tier C in one chunk.
class Curriculum {
  Curriculum({
    required Iterable<NamedStreet> streets,
    required Iterable<District> districts,
    required LatLng centre,
    List<FamilyLink> families = const [],
    Map<String, Set<String>> chunkNeighbours = const {},
  }) : _centre = centre,
       _neighbours = chunkNeighbours {
    final all = streets.toSet().toList()..sort(_longestFirst);
    for (final s in all) {
      _byId[s.id] = s;
    }
    final byPart = {
      for (final s in all)
        for (final p in s.parts) p.id: s,
    };
    for (final f in families) {
      final parent = byPart[f.parentId];
      final child = byPart[f.childId];
      if (f.orphan || parent == null || child == null || parent == child) {
        continue;
      }
      _parentOf[child.id] = parent.id;
      _n[child.id] = f.n;
      _kind[child.id] = f.kind;
      _children.putIfAbsent(parent.id, () => []).add(child.id);
    }
    final chunks = [
      for (final d in districts)
        if (d.kind == DistrictKind.neighbourhood) d,
    ];
    for (final c in chunks) {
      _chunkCentre[c.id] = c.center;
      if (c.parentId case final raion?) _raionOf[c.id] = raion;
    }
    _centreChunk = chunks
        .where((c) => boundaryContains(c.boundary, centre))
        .map((c) => c.id)
        .firstOrNull;

    final trunk = [
      ...ringOrder(all.where((s) => _tier(s) == StreetTier.a)),
      ...ringOrder(all.where((s) => _tier(s) == StreetTier.b)),
    ];
    _trunk.addAll(trunk);
    for (final s in all) {
      _chunkStreets.putIfAbsent(chunkOf(s), () => []).add(s);
    }
    final parents = _parentOf.values.toSet();
    for (final MapEntry(:key, :value) in _chunkStreets.entries) {
      final local = value.where((s) => _tier(s) == StreetTier.c);
      _chunkOrder[key] = [
        ...local.where((s) => parents.contains(s.id) && !_isChild(s)),
        ...local.where((s) => !parents.contains(s.id) && !_isChild(s)),
        ...local.where(_isChild).toList()..sort(_byFamily),
      ];
    }
  }

  final LatLng _centre;
  final Map<String, Set<String>> _neighbours;
  final _byId = <String, NamedStreet>{};
  final _parentOf = <String, String>{};
  final _n = <String, int>{};
  final _kind = <String, FamilyKind>{};
  final _children = <String, List<String>>{};
  final _chunkCentre = <String, LatLng>{};
  final _raionOf = <String, String>{};
  late final String? _centreChunk;
  final _trunk = <NamedStreet>[];

  /// Every street of a chunk, any tier; [_chunkOrder] holds its tier C streets in teaching order.
  final _chunkStreets = <String, List<NamedStreet>>{};
  final _chunkOrder = <String, List<NamedStreet>>{};

  /// The chunk of streets without one (packs before format 4, or the bundled Vake pack's edges).
  static const String noChunk = '';

  static StreetTier _tier(NamedStreet s) => s.parts.first.tier ?? StreetTier.c;

  static String chunkOf(NamedStreet s) => s.parts.first.chunkId ?? noChunk;

  static bool isCore(NamedStreet s) =>
      s.lengthM >= LearningConfig.coreMinLengthM;

  bool _isChild(NamedStreet s) => _parentOf.containsKey(s.id);

  StreetTier? tierOf(String id) => switch (_byId[id]) {
    final s? => _tier(s),
    null => null,
  };

  /// The raion of [id]'s chunk; null for a street without one.
  String? raionOf(String id) => switch (_byId[id]) {
    final s? => _raionOf[chunkOf(s)],
    null => null,
  };

  /// Every street of [chunk], any tier.
  List<NamedStreet> streetsIn(String chunk) => _chunkStreets[chunk] ?? const [];

  /// The street [childId] is a numbered lane, dead end or passage of; null for the rest and for
  /// orphans, which are taught as single streets.
  String? parentOf(String childId) => _parentOf[childId];

  /// [id]'s family without it: its parent and siblings, and its own children.
  Set<String> familyOf(String id) => {
    if (_parentOf[id] case final parent?) ...[parent, ...?_children[parent]],
    ...?_children[id],
  }..remove(id);

  /// The family [id] belongs to (as a child, else as a parent): the parent and
  /// how many children of each kind it has. Null for a street in none.
  ({String parentId, Map<FamilyKind, int> children})? familyChip(String id) {
    final parent = _parentOf[id] ?? (_children.containsKey(id) ? id : null);
    if (parent == null) return null;
    final children = <FamilyKind, int>{};
    for (final child in _children[parent]!) {
      children.update(_kind[child]!, (n) => n + 1, ifAbsent: () => 1);
    }
    return (parentId: parent, children: children);
  }

  static int _longestFirst(NamedStreet a, NamedStreet b) {
    final byLength = b.lengthM.compareTo(a.lengthM);
    return byLength != 0 ? byLength : a.id.compareTo(b.id);
  }

  int _byFamily(NamedStreet a, NamedStreet b) {
    final byParent = _parentOf[a.id]!.compareTo(_parentOf[b.id]!);
    if (byParent != 0) return byParent;
    final byN = _n[a.id]!.compareTo(_n[b.id]!);
    return byN != 0 ? byN : a.id.compareTo(b.id);
  }

  /// Ring by ring outward; within a ring the banks alternate, longest first, starting with the
  /// bank of the ring's longest street.
  static List<NamedStreet> ringOrder(Iterable<NamedStreet> streets) {
    final byRing = <int, List<NamedStreet>>{};
    for (final s in streets) {
      byRing.putIfAbsent(s.parts.first.ring ?? 0, () => []).add(s);
    }
    return [
      for (final ring in byRing.keys.toList()..sort())
        ..._alternateBanks(byRing[ring]!..sort(_longestFirst)),
    ];
  }

  static List<NamedStreet> _alternateBanks(List<NamedStreet> longestFirst) {
    final first = longestFirst.first.parts.first.bank;
    final lead = [
      for (final s in longestFirst)
        if (s.parts.first.bank == first) s,
    ];
    final other = [
      for (final s in longestFirst)
        if (s.parts.first.bank != first) s,
    ];
    return [
      for (var i = 0; i < max(lead.length, other.length); i++) ...[
        if (i < lead.length) lead[i],
        if (i < other.length) other[i],
      ],
    ];
  }

  /// Placement (SPEC §6.2): every core tier A street, then [LearningConfig.placementSamplePerDistrict]
  /// core tier B streets per raion drawn with [seed]. A street's raion is its chunk's.
  List<String> placement(int seed) {
    final random = Random(seed);
    final tierB = _coreTierBByRaion();
    return [
      for (final s in _trunk)
        if (_tier(s) == StreetTier.a && isCore(s)) s.id,
      for (final raion in tierB.keys.toList()..sort())
        ...(tierB[raion]!..shuffle(random))
            .take(LearningConfig.placementSamplePerDistrict)
            .map((s) => s.id),
    ];
  }

  /// The rest of [raion]'s core tier B streets, swept when its placement sample passes.
  List<String> placementSweep(String raion, Iterable<String> sampled) {
    final skip = sampled.toSet();
    return [
      for (final s in ringOrder(_coreTierBByRaion()[raion] ?? const []))
        if (!skip.contains(s.id)) s.id,
    ];
  }

  Map<String, List<NamedStreet>> _coreTierBByRaion() {
    final byRaion = <String, List<NamedStreet>>{};
    for (final s in _trunk) {
      final raion = _raionOf[chunkOf(s)];
      if (_tier(s) == StreetTier.b && isCore(s) && raion != null) {
        byRaion.putIfAbsent(raion, () => []).add(s);
      }
    }
    for (final streets in byRaion.values) {
      streets.sort((a, b) => a.id.compareTo(b.id));
    }
    return byRaion;
  }

  /// Up to [count] street ids to introduce next (SPEC §6.3), given each street's P card by street
  /// id. Groups of [LearningConfig.groupSize] alternate between the skeleton and grid (while
  /// any core street of theirs is unseen, [LearningConfig.tierBShare] of the slots) and the
  /// chunks. A child waits for its parent's stability to reach
  /// [LearningConfig.childParentMinDays], and one parent gets at most
  /// [LearningConfig.maxSiblingsPerDay] new children a day. Short streets wait for their chunk's
  /// phase 2. [anchors] (home, then work) are taught before the centre's chunk.
  List<String> next({
    required Map<String, CardState> cards,
    required DateTime now,
    required int count,
    List<String> anchors = const [],
  }) {
    final picked = <String>[];
    final pickedSet = <String>{};
    final today = startOfDay(now);
    final siblingsToday = <String, int>{};
    for (final MapEntry(:key, :value) in cards.entries) {
      final parent = _parentOf[key];
      if (parent != null && !(value.introAt?.isBefore(today) ?? true)) {
        siblingsToday[parent] = (siblingsToday[parent] ?? 0) + 1;
      }
    }
    bool seen(NamedStreet s) =>
        cards.containsKey(s.id) || pickedSet.contains(s.id);
    final unlocked = <String, bool>{};
    bool available(NamedStreet s) {
      if (seen(s)) return false;
      if (!isCore(s) &&
          !unlocked.putIfAbsent(chunkOf(s), () => _phase2(chunkOf(s), cards))) {
        return false;
      }
      final parent = _parentOf[s.id];
      if (parent == null) return true;
      final stability = cards[parent]?.memory?.stability ?? 0;
      return stability >= LearningConfig.childParentMinDays &&
          (siblingsToday[parent] ?? 0) < LearningConfig.maxSiblingsPerDay;
    }

    final trunkOpen = _trunk.any((s) => isCore(s) && !cards.containsKey(s.id));
    final trunk = _trunk.iterator;
    final local = chunkSequence(cards, anchors).expand((c) => _chunkOrder[c]!);
    final chunks = local.iterator;
    NamedStreet? draw(Iterator<NamedStreet> from) {
      while (from.moveNext()) {
        if (available(from.current)) return from.current;
      }
      return null;
    }

    var trunkTaken = 0;
    while (picked.length < count) {
      final wantTrunk =
          trunkOpen &&
          (picked.isEmpty ||
              trunkTaken / picked.length < LearningConfig.tierBShare);
      final group = <NamedStreet>[];
      while (group.length < LearningConfig.groupSize &&
          picked.length + group.length < count) {
        final fromTrunk = wantTrunk ? draw(trunk) : null;
        final s = fromTrunk ?? draw(chunks) ?? (wantTrunk ? null : draw(trunk));
        if (s == null) break;
        if (_tier(s) != StreetTier.c) trunkTaken++;
        group.add(s);
        pickedSet.add(s.id);
        if (_parentOf[s.id] case final parent?) {
          siblingsToday[parent] = (siblingsToday[parent] ?? 0) + 1;
        }
      }
      if (group.isEmpty) break;
      picked.addAll(group.map((s) => s.id));
    }
    return picked;
  }

  /// Chunks with tier C streets left to teach, in teaching order: the anchors and the centre's
  /// chunk, then chunks already started, then the chunk bordering the most finished chunks
  /// (ties: nearer the centre).
  List<String> chunkSequence(
    Map<String, CardState> cards,
    List<String> anchors,
  ) {
    bool unseenCore(NamedStreet s) => isCore(s) && !cards.containsKey(s.id);
    final finished = {
      for (final MapEntry(:key, :value) in _chunkOrder.entries)
        if (!value.any(unseenCore)) key,
    };
    final starts = [...anchors, ?_centreChunk];
    int startRank(String c) {
      final i = starts.indexOf(c);
      return i < 0 ? starts.length : i;
    }

    bool started(String c) =>
        _chunkOrder[c]!.any((s) => cards.containsKey(s.id));
    int finishedNeighbours(String c) =>
        (_neighbours[c] ?? const {}).where(finished.contains).length;
    double fromCentre(String c) => switch (_chunkCentre[c]) {
      final at? => distanceBetween(at, _centre),
      null => double.infinity,
    };
    final open = [
      for (final MapEntry(:key, :value) in _chunkOrder.entries)
        if (value.any((s) => !cards.containsKey(s.id))) key,
    ];
    return open..sort((a, b) {
      final byStart = startRank(a).compareTo(startRank(b));
      if (byStart != 0) return byStart;
      final byStarted = (started(a) ? 0 : 1).compareTo(started(b) ? 0 : 1);
      if (byStarted != 0) return byStarted;
      final byNeighbours = finishedNeighbours(
        b,
      ).compareTo(finishedNeighbours(a));
      if (byNeighbours != 0) return byNeighbours;
      final byCentre = fromCentre(a).compareTo(fromCentre(b));
      return byCentre != 0 ? byCentre : a.compareTo(b);
    });
  }

  /// Phase 2 (SPEC §6.1): a chunk's short streets open once [LearningConfig.phase2ChunkSolid] of
  /// its core streets are Solid.
  bool _phase2(String chunk, Map<String, CardState> cards) {
    final core = (_chunkStreets[chunk] ?? const []).where(isCore).toList();
    if (core.isEmpty) return true;
    final solid = core.where((s) => cards[s.id]?.isSolid ?? false).length;
    return solid / core.length >= LearningConfig.phase2ChunkSolid;
  }
}
