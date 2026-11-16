import { distanceBetween, type LatLng } from "./geo.ts";

// Twin of pindoro_core `road_graph.dart` (SPEC §16.7): the directed, turn-restricted,
// edge-expanded road graph. `shared/fixtures/directed_route_vectors.json` proves them equal.

// Which way an edge may be driven: "forward" only from `from` to `to`, "backward" only back.
export type Oneway = "both" | "forward" | "backward";

export interface RoadEdge {
  id: number;
  from: number;
  to: number;
  // The street part it belongs to; null for a connector (an unnamed way or a *_link).
  streetId: string | null;
  lengthM: number;
  oneway: Oneway;
}

// Arriving on `fromEdge` at junction `via`, `toEdge` is forbidden (no_*), or with `only`
// (only_*) the only way on.
export interface TurnRestriction {
  fromEdge: number;
  via: number;
  toEdge: number;
  only: boolean;
}

export const RoutingConfig = {
  // What a U-turn adds to a route's cost: about 30 s at 30 km/h.
  uTurnPenaltyM: 250,
} as const;

export interface Route {
  junctions: number[];
  edges: number[];
  lengthM: number;
  costM: number;
}

export interface RouteOptions {
  allow?: (edge: RoadEdge) => boolean;
  // The edge driven to `from`: restricts the first turn.
  approach?: RoadEdge;
}

// The pack's oneway column: 1 forward, -1 backward, anything else both.
export const onewayOf = (column: number | null | undefined): Oneway =>
  column === 1 ? "forward" : column === -1 ? "backward" : "both";

interface Turn {
  no: Set<number>;
  only: Set<number> | null;
}

// A search state: arrived at `junction` on `edge` (-1 at the start).
interface Entry {
  estimate: number;
  edge: number;
  junction: number;
}

// Ordered by estimate, then edge id (the start's -1 first), then junction: Dart's order.
const before = (a: Entry, b: Entry): boolean =>
  a.estimate !== b.estimate
    ? a.estimate < b.estimate
    : a.edge !== b.edge
      ? a.edge < b.edge
      : a.junction < b.junction;

class Heap {
  private readonly items: Entry[] = [];

  get size(): number {
    return this.items.length;
  }

  push(entry: Entry): void {
    const items = this.items;
    items.push(entry);
    let i = items.length - 1;
    while (i > 0) {
      const parent = (i - 1) >> 1;
      if (!before(items[i] as Entry, items[parent] as Entry)) break;
      [items[i], items[parent]] = [items[parent] as Entry, items[i] as Entry];
      i = parent;
    }
  }

  pop(): Entry {
    const items = this.items;
    const top = items[0] as Entry;
    const last = items.pop() as Entry;
    if (items.length > 0) {
      items[0] = last;
      let i = 0;
      for (;;) {
        const l = 2 * i + 1;
        const r = l + 1;
        let m = i;
        if (l < items.length && before(items[l] as Entry, items[m] as Entry)) m = l;
        if (r < items.length && before(items[r] as Entry, items[m] as Entry)) m = r;
        if (m === i) break;
        [items[i], items[m]] = [items[m] as Entry, items[i] as Entry];
        i = m;
      }
    }
    return top;
  }
}

const turnKey = (edge: number, junction: number): string => `${edge}@${junction}`;

export class RoadGraph {
  readonly junctions: ReadonlyMap<number, LatLng>;
  readonly edges: readonly RoadEdge[];
  private readonly at = new Map<number, RoadEdge[]>();
  private readonly byId = new Map<number, RoadEdge>();
  private readonly turns = new Map<string, Turn>();
  private readonly piece = new Map<number, number>();

  constructor(
    junctions: ReadonlyMap<number, LatLng>,
    edges: readonly RoadEdge[],
    restrictions: readonly TurnRestriction[] = [],
  ) {
    this.junctions = junctions;
    this.edges = edges;
    for (const e of edges) {
      this.byId.set(e.id, e);
      this.edgesAtMut(e.from).push(e);
      if (e.to !== e.from) this.edgesAtMut(e.to).push(e);
    }
    for (const list of this.at.values()) list.sort((a, b) => a.id - b.id);
    for (const r of restrictions) {
      const key = turnKey(r.fromEdge, r.via);
      const turn = this.turns.get(key) ?? { no: new Set<number>(), only: null };
      this.turns.set(key, turn);
      if (!r.only) turn.no.add(r.toEdge);
      else if (turn.only === null) turn.only = new Set([r.toEdge]);
      else turn.only.add(r.toEdge);
    }
    this.findPieces();
  }

  // The edges at `junction`, by id.
  edgesAt(junction: number): readonly RoadEdge[] {
    return this.at.get(junction) ?? [];
  }

  // Whether some drive joins `a` and `b`, one-ways aside.
  connected(a: number, b: number): boolean {
    const piece = this.piece.get(a);
    return a === b || (piece !== undefined && piece === this.piece.get(b));
  }

  // Whether `e` may be driven away from `fromJunction`.
  canDrive(e: RoadEdge, fromJunction: number): boolean {
    return (
      e.oneway === "both" ||
      (e.oneway === "forward" ? fromJunction === e.from : fromJunction === e.to)
    );
  }

  // The edges one may drive away from `junction` having arrived on `approach` (none: starting
  // there), by id: those canDrive allows and the turn restrictions keep; the approach itself
  // (a U-turn) only when it is two-way.
  legalExits(junction: number, approach?: RoadEdge): RoadEdge[] {
    const turn =
      approach === undefined ? undefined : this.turns.get(turnKey(approach.id, junction));
    return this.edgesAt(junction).filter(
      (e) =>
        this.canDrive(e, junction) &&
        (e.id !== approach?.id || e.oneway === "both") &&
        (turn === undefined || (!turn.no.has(e.id) && (turn.only === null || turn.only.has(e.id)))),
    );
  }

  // The cheapest legal drive from `from` to the nearest of `goals`: A* over (edge driven,
  // junction reached), each U-turn costing RoutingConfig.uTurnPenaltyM more, the straight line
  // to the nearest goal as the heuristic. Ties as in Dart. Null when no goal is reached.
  shortestRoute(
    from: number,
    goals: ReadonlySet<number>,
    options: RouteOptions = {},
  ): Route | null {
    const { allow, approach } = options;
    if (![...goals].some((g) => this.connected(from, g))) return null;
    const goalPoints = [...goals].map((g) => this.point(g));
    const toGoal = new Map<number, number>();
    const h = (j: number): number => {
      let d = toGoal.get(j);
      if (d === undefined) {
        const p = this.point(j);
        d = Math.min(...goalPoints.map((g) => distanceBetween(p, g)));
        toGoal.set(j, d);
      }
      return d;
    };
    const startEdge = approach?.id ?? -1;
    const startKey = this.stateKey(startEdge, from);
    const cost = new Map<number, number>([[startKey, 0]]);
    const back = new Map<number, { edge: number; junction: number }>();
    const closed = new Set<number>();
    const open = new Heap();
    open.push({ estimate: 0 + h(from), edge: startEdge, junction: from });
    while (open.size > 0) {
      const { edge, junction } = open.pop();
      const key = this.stateKey(edge, junction);
      if (closed.has(key)) continue;
      closed.add(key);
      const c = cost.get(key) as number;
      if (goals.has(junction)) return this.route(edge, junction, back, startKey, c);
      const arrivedOn = this.byId.get(edge);
      for (const e of this.legalExits(junction, arrivedOn)) {
        if (allow !== undefined && !allow(e)) continue;
        const nextJunction = e.from === junction ? e.to : e.from;
        const nextKey = this.stateKey(e.id, nextJunction);
        if (closed.has(nextKey)) continue;
        const nc = c + e.lengthM + (e.id === edge ? RoutingConfig.uTurnPenaltyM : 0);
        if (nc >= (cost.get(nextKey) ?? Infinity)) continue;
        cost.set(nextKey, nc);
        back.set(nextKey, { edge, junction });
        open.push({ estimate: nc + h(nextJunction), edge: e.id, junction: nextJunction });
      }
    }
    return null;
  }

  private route(
    edge: number,
    junction: number,
    back: ReadonlyMap<number, { edge: number; junction: number }>,
    startKey: number,
    costM: number,
  ): Route {
    const junctions = [junction];
    const edges: number[] = [];
    let state = { edge, junction };
    for (
      let key = this.stateKey(edge, junction);
      key !== startKey;
      key = this.stateKey(state.edge, state.junction)
    ) {
      edges.push(state.edge);
      state = back.get(key) as { edge: number; junction: number };
      junctions.push(state.junction);
    }
    junctions.reverse();
    edges.reverse();
    // Summed in driving order, as Dart's fold.
    let lengthM = 0;
    for (const id of edges) lengthM += (this.byId.get(id) as RoadEdge).lengthM;
    return { junctions, edges, lengthM, costM };
  }

  // A search state as a number: arrived at an end of an edge (its far end odd), or -1 - the
  // junction for a start with no edge.
  private stateKey(edge: number, junction: number): number {
    if (edge < 0) return -1 - junction;
    return edge * 2 + ((this.byId.get(edge) as RoadEdge).to === junction ? 1 : 0);
  }

  private point(junction: number): LatLng {
    const p = this.junctions.get(junction);
    if (p === undefined) throw new RangeError(`no junction ${junction}`);
    return p;
  }

  private edgesAtMut(junction: number): RoadEdge[] {
    let list = this.at.get(junction);
    if (list === undefined) {
      list = [];
      this.at.set(junction, list);
    }
    return list;
  }

  private findPieces(): void {
    for (const start of this.at.keys()) {
      if (this.piece.has(start)) continue;
      this.piece.set(start, start);
      const stack = [start];
      while (stack.length > 0) {
        const j = stack.pop() as number;
        for (const e of this.edgesAt(j)) {
          const next = e.from === j ? e.to : e.from;
          if (this.piece.has(next)) continue;
          this.piece.set(next, start);
          stack.push(next);
        }
      }
    }
  }
}
