# TODO after Milestone 1

## Placeholders to replace

- **App-only tokens** — `packages/pindoro_design/tokens/app.json` values were picked in the repo,
  not designed: basemap building / railway / boundary colours, the area mask, the pin dot size and
  camera framing. Design them on claude.ai and move them into the design system.
- **Sound kit** — the design's 14 sounds don't exist yet; the Sound toggle and `GameFeedback`
  are in place, so add an audio player there once the files are designed.
- **Georgian copy** — `apps/mobile/lib/l10n/app_ka.arb` is the copy deck's draft plus a few strings
  written in the repo; it needs a native review.
- **Design-system components** — only `PindoroButton` (primary / secondary / tertiary),
  `StreetPlate` and `FeedbackBadge` exist; the pin marker, reveal sheet, progress bars and the
  rest of the components on claude.ai are not built. The player's pin is a dot until then.
- **App identity** — launcher icon, splash screen, final bundle id (`app.pindoro.pindoro`).
- **Code licence** — not chosen yet (data is ODbL, font is OFL).

## Gameplay

- Offline maps: rounds work offline, but tiles need the server or MapLibre's cache.
- The dark map style is generated but has not been checked on a device.
- Districts such as Vake include large forested areas, so streets in one round can be kilometres
  apart; consider neighbourhood-sized areas.

## Data / pipeline

- `data/cities/tbilisi/curation/neighbourhoods.geojson` is empty; curate neighbourhoods.
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
- Real server setup per `docs/deploy.md`: Cloudflare Tunnel token, public hostnames, systemd timers
  for pack refresh and the second-disk backup copy.
- iOS has not been built or run (no macOS in the bootstrap environment).
