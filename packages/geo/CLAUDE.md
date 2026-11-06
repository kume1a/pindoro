# @pindoro/geo

TypeScript twin of `packages/pindoro_core` (Dart): local equirectangular projection,
point-to-polyline distance (to segments, with bbox prefilter), polyline6, scoring (tiers and XP
by road class and difficulty) and levels. Used by the pipeline (polyline6) and later the API.

- Runs from source (`exports: ./src/index.ts`); no build step.
- `pnpm --filter @pindoro/geo test` runs the golden vectors in `shared/fixtures/*.json`.
- **Must stay in sync with pindoro_core.** Any change to an algorithm or a `ScoringConfig` constant
  is made in both languages and in the shared vectors in the same change; both test suites must
  pass the same vectors.
- Rounding: XP uses `Math.round` on positive numbers; polyline6 rounds half away from zero
  (matches Dart `num.round()`).
