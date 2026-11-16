# @pindoro/geo

TypeScript twin of `packages/pindoro_core` (Dart): local equirectangular projection,
`distanceBetween`, point-to-polyline distance (to segments, with bbox prefilter), polyline6,
scoring (the tier of a pin by road class and difficulty) and routing (`routing.ts`: the directed,
turn-restricted, edge-expanded `RoadGraph` with the U-turn penalty, twin of `road_graph.dart`).
Used by the pipeline (polyline6, and routing for the junction-item sampling).

- Runs from source (`exports: ./src/index.ts`); no build step.
- `pnpm --filter @pindoro/geo test` runs the golden vectors in `shared/fixtures/*.json`.
- **Must stay in sync with pindoro_core.** Any change to an algorithm or a `ScoringConfig` constant
  is made in both languages and in the shared vectors in the same change; both test suites must
  pass the same vectors.
- Rounding: polyline6 rounds half away from zero (matches Dart `num.round()`).
- Routing must pick the same route as Dart: same search order (estimate, then edge id with the
  start's -1 first, then junction reached), exits by edge id, strict improvement only.
  `shared/fixtures/directed_route_vectors.json` proves it. About 8 ms a route on a 28k-edge grid.
