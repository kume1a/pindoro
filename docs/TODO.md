# TODO after Milestone 0

## Placeholders to replace

- **Design tokens** — every value in `packages/pindoro_design/tokens/tokens.json` is a placeholder
  (colours, map palette, radii, spacing, sizes, motion), including `map.camera.zoom`,
  `opacity.disabled` and the measure-line dash/gap.
- **Design docs** — `docs/design/signpost.md` and `docs/design/v1-screens.md` are placeholders
  written during the bootstrap; the real Signpost spec and v1 screen specs are missing.
- **Screens** — all routes are placeholder layouts; UI copy is English-only placeholder text with
  no localisation (Georgian + English needed).
- **App identity** — launcher icon, splash screen, final bundle id (`app.pindoro.pindoro`).
- **Code licence** — not chosen yet (data is ODbL, font is OFL).

## Gameplay (next milestone)

- Wire the quiz loop: `QuestionSelector` → `/quiz` → scoring → append to the `answer` log →
  `/results` from the real round; XP and level on `/home`.
- Area selection on `/area` with the reserved `area-mask` map source.
- Download packs from `/v1/catalog` (verify sha256 + size, gunzip, swap atomically) instead of the
  bundled fixture; `http` is already a dependency for this.
- Settings: theme, language, about/licences page.
- The dark map style is generated but has not been checked on a device.
- Random debug streets can be kilometres apart: districts such as Vake include large forested
  areas, so area selection and question framing should account for that.

## Data / pipeline

- `data/cities/tbilisi/curation/neighbourhoods.geojson` is empty; curate neighbourhoods.
- 11 Tbilisi streets fall in gaps between raion polygons and belong to no district.
- A retired street id is never revived; a street that reappears in OSM gets a new id.
- Old pack versions are never pruned from `PACKS_DIR`.
- The API's `city`/`district`/`street`/`street_district`/`pack` tables exist but nothing fills
  them yet (`publish` only writes files).
- Decide a refresh cadence for `infra/tiles/georgia.pmtiles` (Protomaps daily builds).

## Infra / CI

- No GitHub remote yet; both workflows were run green locally with `act` (ubuntu-24.04 image),
  not on GitHub Actions itself.
- Flutter is pinned to 3.47.9 in CI and `just goldens`; the bootstrap machine ran a 3.41.2 checkout
  (Dart 3.13). Align local Flutter with the pinned version, and bump both together later.
- Real server setup per `docs/deploy.md`: Cloudflare Tunnel token, public hostnames, systemd timers
  for pack refresh and the second-disk backup copy.
- iOS has not been built or run (no macOS in the bootstrap environment).
