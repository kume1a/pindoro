# TODO after Milestone 1

## Placeholders to replace

- **Sound kit** — the design's 14 sounds don't exist yet; the Sound toggle and `GameFeedback`
  are in place, so add an audio player there once the files are designed.
- **Georgian translation** — `apps/mobile/lib/l10n/app_ka.arb` is a draft; it needs a native
  review.
- **Designed in text, not drawn** — the 2026-11-07 design pass (map greys, 104-area picker, city
  pack download, Miss directions) lives in `tokens.json` and `docs/design/v1-screens.md`; the
  claude.ai canvas has no boards for it yet (chips at both zoom bands, district names along
  outlines, narrow with Undo, All areas, pack download and failure, offline Vake).
- **Left out of that pass, on purpose:**
  - Download progress in the City row: tapping a city opens the Area picker at once, so the row is
    gone before a bar could show. The wait shows in the Area picker's panel instead.
  - Chips that step aside instead of hiding: MapLibre only shifts text labels
    (`text-variable-anchor`), and the map style has no fonts, so chips are images. It would need
    FiraGO map glyphs generated and served, and every chip redrawn as map text.
  - A city outline on the empty map while the pack downloads: the catalog has only a bbox, so it
    would need the boundary in the manifest, the API and the app, for a wait of 1–2 s.
  - A "Free up space" button and a free-space check before downloading: native code (Android
    `StorageManager.getAllocatableBytes`, `ACTION_MANAGE_STORAGE`) for a 1 MB pack. A full phone
    is caught when saving fails and gets its own copy.
  - The progress bar's finishing touches from the research (red on failure, a check when done):
    the panel goes away as soon as the pack opens.
- Map labels (area names, the distance chip) are images drawn by `MapChip`, because the self-hosted
  map style has no glyphs.

## Gameplay

- Offline maps: the city's tiles (zoom 10–15, about 1 500 tiles for Tbilisi) download in the
  background once a downloaded pack opens, as a MapLibre offline region. The region is never
  refreshed; delete it when `georgia.pmtiles` updates (no tiles version to compare yet).
- The offline toast probes the API's `/health`; there is no live connectivity listener.
- Keyboard and D-pad focus: the design system's custom controls (`Tappable` in pindoro_design)
  take taps and screen-reader taps but can't be focused from a keyboard; `color.focus.ring` is
  unused. Build `Tappable` on `FocusableActionDetector` with a focus-ring outline when needed.
- Streak (R2), left out on purpose:
  - The streak sound ("whoosh + ding") waits for the sound kit.
  - The reminder is fixed at 19:00 (the board has no time picker).
  - The Streak calendar shows the current month only (the board has no month arrows).
  - The pill doesn't turn "at risk" at 18:00 while the app stays open; it updates on the next
    resume or progress change.
  - Days before the R2 update aren't backfilled: streaks start with it.
  - iOS: the reminder has never run on a device; foreground presentation
    (`UNUserNotificationCenter` delegate in `AppDelegate`) isn't set up.
- Pit stop (R3), left out on purpose:
  - Answers from before the R3 update don't enter the Pit stop (it starts empty).
  - The Results chip "n to your Pit stop" isn't tappable; the Pit stop tab is the way in.
  - The Pit stop on the lesson path waits for R4b.
  - Review items of a retired street stay in the table; readers skip them (`dueIn`).
- Tabs and Me (R4a), left out on purpose:
  - Me's Lessons and Road trips tiles read 0 until R4b (lessons) and R4c (road trips) count them.
  - Only Best streak opens something (Streak); the lists behind the other tiles don't exist yet.
  - Me's city rows say "180 / 1 240 streets"; the canvas's "Unit 2 · Vake ·" prefix needs R4b.
  - The Path tab, and tapping it to scroll to the current stop, arrive with R4b.
  - A played city whose pack isn't on the phone is left out of Me's cities.
  - After a Pit stop round, Done still lands on Free play (with the Home intro), not the Pit stop
    tab.

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
