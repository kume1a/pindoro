import 'package:pindoro_core/pindoro_core.dart';

import 'cards.dart';
import 'constants.dart';
import 'curriculum.dart';
import 'fsrs.dart';
import 'stats.dart';

/// Which way a turn goes, seen arriving on the approach (a J card's exit buttons).
enum Turn { left, straight, right, uTurn }

/// The turn from heading [approachDeg] (driving in) onto heading [exitDeg] (driving away),
/// degrees from north: within [LearningConfig.turnStraightDeg] straight on, past
/// [LearningConfig.turnUTurnDeg] a U-turn.
Turn turnOf(double approachDeg, double exitDeg) {
  final d = ((exitDeg - approachDeg) % 360 + 540) % 360 - 180;
  if (d.abs() <= LearningConfig.turnStraightDeg) return Turn.straight;
  if (d.abs() >= LearningConfig.turnUTurnDeg) return Turn.uTurn;
  return d > 0 ? Turn.right : Turn.left;
}

/// Route item ids (SPEC §3, §16.14). Every part survives a pack rebuild: junctions and
/// approaches are OSM node ids (`n123`), bridges and landmarks OSM ids, chunks district ids.
abstract final class RouteIds {
  /// A turn: arriving at [node] from [approachNode], leaving towards [exitNode].
  static String junction(int node, int approachNode, int exitNode) =>
      CardType.j.item('n$node:n$approachNode:n$exitNode');

  static String gateway(String chunk, int node, {required bool out}) =>
      CardType.g.item('$chunk:n$node:${out ? 'out' : 'in'}');

  /// Onto [bridge] from [bank] (`L`/`R`), turning at [node].
  static String bridge(String bridge, String bank, int node) =>
      CardType.b.item('$bridge:$bank:n$node');

  static String connection(String streetId) => CardType.c.item(streetId);

  /// L1 (landmark → pin), L2 (landmark → junction) or L3 (junction and turn → landmark).
  static String landmark(String landmarkId, int n) =>
      CardType.l.item('$landmarkId:$n');
}

/// The route layers in teaching order (SPEC §6.5): bridges right after the skeleton streets,
/// skeleton turns, gateways with each chunk, then district turns; connections and landmarks
/// once their streets are Known.
enum RouteLayer { bridge, skeleton, gateway, district, connection, landmark }

/// A route item the pack offers, with what opens it (SPEC §3, §16.14).
typedef RouteCandidate = ({
  String itemId,
  RouteLayer layer,

  /// Coverage order within the layer (1 first).
  int rank,

  /// Street ids whose P cards must be Known.
  Set<String> known,

  /// District turns: the raion whose grid must be [LearningConfig.districtJunctionUnlockSolid]
  /// Solid.
  String? raion,

  /// Gateways: the chunk whose main streets must be [LearningConfig.gatewayUnlockKnown] Known.
  String? chunk,

  /// Phase 2 (gateways in, SPEC §6.5).
  bool phase2,

  /// The player's own landmark: open at once.
  bool personal,
});

extension RouteUnlocks on Curriculum {
  /// Route items open for their first review (SPEC §3, §16.14), in teaching order, then rank:
  /// bridges once every core tier A street is introduced; skeleton turns, connections and OSM
  /// landmarks once their streets are Known; district turns also need their raion's grid
  /// Solid; gateways their chunk's main streets Known, and phase 2 for the way in; personal
  /// landmarks at once. [cards] are P cards by street id; [carded] holds every carded item id.
  List<String> openRoutes(
    List<RouteCandidate> candidates, {
    required Map<String, CardState> cards,
    required Set<String> carded,
    required DateTime now,
    bool phase2Open = false,
  }) {
    bool known(String street) => switch (cards[street]) {
      final c? => isKnown(c, now),
      null => false,
    };
    final skeletonIntroduced = streetsWhere(
      (s) => tierOf(s.id) == StreetTier.a && Curriculum.isCore(s),
    ).every((s) => cards.containsKey(s.id));
    final gridSolid = <String, bool>{};
    bool raionReady(String raion) => gridSolid.putIfAbsent(raion, () {
      final grid = streetsWhere(
        (s) =>
            raionOf(s.id) == raion &&
            tierOf(s.id) == StreetTier.b &&
            Curriculum.isCore(s),
      );
      return grid.isNotEmpty &&
          grid.where((s) => cards[s.id]?.isSolid ?? false).length /
                  grid.length >=
              LearningConfig.districtJunctionUnlockSolid;
    });
    final chunkKnown = <String, bool>{};
    bool chunkReady(String chunk) => chunkKnown.putIfAbsent(chunk, () {
      final main = streetsIn(
        chunk,
      ).where((s) => Curriculum.isCore(s) && parentOf(s.id) == null).toList();
      return main.isNotEmpty &&
          main.where((s) => known(s.id)).length / main.length >=
              LearningConfig.gatewayUnlockKnown;
    });
    bool open(RouteCandidate c) =>
        !carded.contains(c.itemId) &&
        (c.personal ||
            (c.known.every(known) &&
                switch (c.layer) {
                  RouteLayer.bridge => skeletonIntroduced,
                  RouteLayer.district =>
                    c.raion != null && raionReady(c.raion!),
                  RouteLayer.gateway =>
                    (!c.phase2 || phase2Open) &&
                        c.chunk != null &&
                        chunkReady(c.chunk!),
                  _ => true,
                }));
    return [
      for (final c
          in candidates.where(open).toList()..sort(
            (a, b) => a.layer != b.layer
                ? a.layer.index.compareTo(b.layer.index)
                : a.rank != b.rank
                ? a.rank.compareTo(b.rank)
                : a.itemId.compareTo(b.itemId),
          ))
        c.itemId,
    ];
  }
}

/// Grading of the route cards (SPEC §5.2).
abstract final class RouteGrader {
  /// A J or B decision: the right exit and, when typed, the right street is Good; the right exit
  /// with the street wrong, or left out when [streetAsked], Hard; a wrong exit Again.
  static Rating turn({
    required bool exitRight,
    bool? streetRight,
    bool streetAsked = false,
  }) => !exitRight
      ? Rating.again
      : switch (streetRight) {
          true => Rating.good,
          false => Rating.hard,
          null => streetAsked ? Rating.hard : Rating.good,
        };

  /// A gateway: the pin within [LearningConfig.landmarkRadiusM] of the gateway junction and the
  /// street joined; both Good, one Hard, neither Again.
  static Rating gateway({
    required double distanceM,
    required bool streetRight,
  }) => switch ((distanceM <= LearningConfig.landmarkRadiusM, streetRight)) {
    (true, true) => Rating.good,
    (false, false) => Rating.again,
    _ => Rating.hard,
  };

  /// A pin for a point (L1): Great within [LearningConfig.pinGoodMaxM] (Perfect within the
  /// Perfect margin) is Good; farther Again.
  static ({Tier tier, Rating rating}) point(double distanceM) {
    final tier = TierThresholds.forStreet(
      'residential',
      Difficulty.medium,
    ).tierFor(distanceM);
    return (
      tier: tier,
      rating: distanceM <= LearningConfig.pinGoodMaxM
          ? Rating.good
          : Rating.again,
    );
  }

  /// The display tier of a route rating: Good Great, Hard Close, Again Miss.
  static Tier tierOf(Rating rating) => switch (rating) {
    Rating.easy || Rating.good => Tier.great,
    Rating.hard => Tier.close,
    Rating.again => Tier.miss,
  };
}
