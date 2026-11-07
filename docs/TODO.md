# TODO after Milestone 1

## Placeholders to replace

- **App-only tokens** — `packages/pindoro_design/tokens/app.json` values were picked in the repo,
  not designed: basemap building / railway / boundary colours, the area mask, the measure-line dots,
  camera framing and the zoom where the area picker switches to neighbourhoods. Design them on
  claude.ai and move them into the design system.
- **Sound kit** — the design's 14 sounds don't exist yet; the Sound toggle and `GameFeedback`
  are in place, so add an audio player there once the files are designed.
- **Georgian copy** — `apps/mobile/lib/l10n/app_ka.arb` is the copy deck's draft plus a few strings
  written in the repo; it needs a native review.
- **Built without a design yet** (prompt for claude.ai given 2026-11-07): the first pack download's
  progress and failure states, the area picker at 104 presets (which level shows at which zoom,
  the "All" sheet grouped by district, the word for a mix of districts and neighbourhoods) and the
  Miss sentence's compass form. Align them when the design lands.
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
