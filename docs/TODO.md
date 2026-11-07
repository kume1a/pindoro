# TODO after Milestone 1

## Placeholders to replace

- **Sound kit** — the design's 14 sounds don't exist yet; the Sound toggle and `GameFeedback`
  are in place, so add an audio player there once the files are designed.
- **Georgian copy** — `apps/mobile/lib/l10n/app_ka.arb` is the copy deck's draft plus a few strings
  written in the repo; it needs a native review.
- **Designed in text, not drawn** — the 2026-11-07 design pass (map greys, 104-area picker, city
  pack download, Miss directions) lives in `tokens.json` and `docs/design/v1-screens.md`; the
  claude.ai canvas has no boards for it yet (chips at both zoom bands, narrow with Undo, All areas,
  pack download and failure, offline Vake).
- **Left out of that pass:** download progress in the City row (choosing a city opens the Area
  picker at once, so the wait shows there); district names along their outlines from zoom 12 (no
  glyphs); chips that step aside instead of hiding (MapLibre's variable anchors are text-only);
  sticky district rows in All areas; the pack panel's motion and a city outline on the empty map
  while it downloads; a "Free up space" button and a free-space check before downloading; Miss
  distances rounded to 10 m (they would disagree with the map chip). The bundled Vake pack holds
  only the district, not its quarters and neighbourhoods.
- Map labels (area names, the distance chip) are images drawn by `MapChip`, because the self-hosted
  map style has no glyphs.

## Gameplay

- Offline maps: the city's tiles (zoom 10–15, about 1 500 tiles for Tbilisi) download in the
  background once a downloaded pack opens, as a MapLibre offline region. The region is never
  refreshed; delete it when `georgia.pmtiles` updates (no tiles version to compare yet).
- The offline toast probes the API's `/health`; there is no live connectivity listener.

## Data / pipeline

- Neighbourhoods come from OSM `place=quarter|neighbourhood`; `curation/neighbourhoods.geojson` is
  empty and only needed for areas OSM lacks.
- 11 Tbilisi streets fall in gaps between raion polygons and belong to no district.
- A retired street id is never revived; a street that reappears in OSM gets a new id.
- Old pack versions are never pruned from `PACKS_DIR` (the app keeps its 2 newest).
- Pack downloads hold the whole `.gz` in memory; stream to disk if packs grow past a few MB.
- The API's `city`/`district`/`street`/`street_district`/`pack` tables exist but nothing fills
  them yet (`publish` only writes files).
- Decide a refresh cadence for `infra/tiles/georgia.pmtiles` (Protomaps daily builds).

## Infra / CI

- CI runs on GitHub Actions (kume1a/pindoro); `act` reproduces it locally.
- Flutter is pinned to 3.47.9 in CI and `just goldens`; the bootstrap machine ran a 3.41.2 checkout
  (Dart 3.13). Align local Flutter with the pinned version, and bump both together later.
- Production server: once the server, a Cloudflare domain and the tunnel token exist, fill `.env`
  and run `just server-setup` (`docs/deploy.md`).
- Store releases: create the Android upload key and `key.properties`, then
  `just release appbundle <domain>` (`docs/deploy.md` section 9).
- iOS is built unsigned in CI (macOS runner) but has never run on a device or simulator.
- Move `drizzle-kit` to 1.0 once it is stable: it drops `@esbuild-kit`, which brings in the old
  esbuild behind the dismissed Dependabot alert #1.
- Dependabot ignores Node and PostGIS major versions: bump those by hand (PostGIS needs a dump and
  restore).
