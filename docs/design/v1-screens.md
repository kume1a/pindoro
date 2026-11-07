# MVP screens (v1.0) and releases

Flutter notes for the MVP, "quick play and progress": Home shows your level, XP and the streets you know per city and district; pick a city and an area, choose a difficulty, play 10-question rounds, then retry the streets you missed. The screens are drawn on the "Pindoro v1 screens" Design canvas: page **Roadmap** (all five releases), page **MVP · v1.0** (the whole first app, drawn in the light theme at 390 × 844, with a four-screen dark check at the end), **MVP stress tests** (360 × 800, 200 % text, map legibility) and one page per later release with only its New and Changed screens. Releases after the MVP are at the end of this file. Everything below uses only this system's tokens and components; names are token names (`color.surface.base`) and their Dart forms come from `handoff/pindoro_tokens.dart` (`PindoroColors.surfaceBase`).

**Flow:** first run: Welcome → City picker → Area picker → Difficulty → (loading) → Quiz question ⇄ Answer reveal × 10 → Round results. Returning: Home → **Play** (resumes the last city, area and difficulty) → round → Round results → **Play again** (same settings), **Retry 3 missed** (a short round of the Close and Miss streets), **Change settings** (area picker) or **Done** (Home). Settings opens from Home.

## Shared rules

### Frames, safe areas, gutters

- Every screen is a `Scaffold(backgroundColor: c.surfaceBase)`; map screens put `FlutterMap` edge to edge under the system bars (`extendBodyBehindAppBar`, `SystemUiOverlayStyle` matching the theme).
- Side gutters `space.4` (16 dp). Top bars sit at `MediaQuery.padding.top`; their row is 48 dp (`size.tap.min`).
- Primary actions: full-width `PindoroButton`, 56 dp (`size.button.lg`) + 4 dp lip, with its lip ending **26 dp above** `MediaQuery.padding.bottom` (iOS 34 → 60 dp from the edge; Android gesture nav 24 → 50 dp). The canvas draws exactly these values.
- Content column max width 600 dp on tablets (sheets and lists centred).
- No status-bar mockups: the real system bars draw over the reserved space.

### Navigation

`go_router` routes: `/` Home (redirects to `/welcome` until the first round is played) · `/welcome` · `/city` · `/area` · `/difficulty` · `/round` (setup states, quiz and reveal are one route with a state machine; `?retry=<roundId>` plays the retry set) · `/results` · `/results/street/:index` · `/settings`. Back or ✕ in `/round` opens "Leave for now?" (**Keep playing** primary and the default for back and scrim, **Leave for now** tertiary). The round is saved after every answer, so leaving or the app being killed keeps it; Home then shows a "Round in progress" card and the hero becomes **Continue round** (canvas boards M-33, M-34). Transitions: push with `motion.duration.base` + `motion.ease.decelerate` (slide 24 dp + fade), pop with `motion.duration.fast` + `motion.ease.accelerate`; reduce motion: 150 ms fade.

### The map (area picker, quiz, reveal, results street view)

- `flutter_map` with CARTO `light_nolabels` / `dark_nolabels` raster tiles, chosen by the resolved theme; tiles never show labels, so the quiz never shows a street name.
- Overlays follow the colour rule: **yellow paint is the truth** (`color.map.answer.line` 8 dp over `color.map.answer.casing` 12 dp, `PolylineLayer`), **cobalt is you** (pin, play-area circle/rectangle/districts), **ink is measurement** (`color.map.measure.line`, 3 dp, dash 0.1/6 round caps, a 5.5 dp ring at the street end, and the `.pd-distchip` label). The answer street is never drawn before Confirm.
- **MapAttribution** on every map: "© OpenStreetMap contributors, © CARTO", `label.sm`, 16 dp from the left, 8 dp above whatever covers the bottom of the map (button, sheet). It moves with the sheet.
- Map controls: 48 dp `mapctl` buttons (raised + 2 dp lip + `shadow.float`), right gutter, 16 dp above the bottom UI: Recentre / Go to my location, Zoom in, Zoom out.
- Legibility (canvas "Map overlays" board): on light tiles the yellow alone is 1.1–1.6:1, so the ink casing carries the street (11.3:1 or better); on dark tiles the yellow carries it (6.8:1 or better). Pin lowest pair: cobalt 400 on a dark road, 3.9:1; the white halo keeps it clear everywhere. Re-sample the basemap colours from production tiles before release.
- Vector basemaps (the app's self-hosted tiles) draw buildings, railways (under the roads) and boundaries in `color.map.basemap.building` / `.railway` / `.boundary`: neutral greys a step apart, so yellow and cobalt stay the only hues on the map. Yellow on light buildings is about 1.3:1, so the answer street always keeps its casing (it also separates the street from a railway it crosses); cobalt on dark buildings is about 2.4:1, so the pin keeps its white ring. Outside the play area a veil of `color.map.mask` at `opacity.mask` keeps outside streets readable as context.
- Camera: `camera.zoom` (13.5, about 2 km across 390 dp) before the camera fits the area; fits keep `camera.fit-padding-x` (32 dp, more than half the pin head) at the sides, while top and bottom clear the street plate and the sheet.

### Text and numbers

FiraGO everywhere, `PindoroType.*`; numbers (XP, distances, counts, sizes) with `FontFeature.tabularFigures()`. Never `toUpperCase()`. Distances: whole metres below 100 m ("84 m"), then rounded up to the next 10 m ("850 m": every tier limit is a multiple of 10 m, so a Miss never reads as a Close's distance), one decimal from 1 km ("1.2 km"), localised separators (a decimal comma where the locale uses one). The reveal's sentence, its map chip and Results show the same figure. Street names as the city writes them, with the transliteration (or the local name, in English mode) on the plate's sub-line.

### Scoring, XP and levels

Every point is **XP**; the UI never says "points". Medium radii; Easy ×1.5, Hard ×0.7, Expert ×0.5 on every threshold. Perfect = inside the street's drawn width + 20 m → **100**. Great ≤ 100 m → `round(90 − 0.25 × (d − 20))` (90 → 70). Close ≤ 300 m → `round(60 − 0.15 × (d − 100))` (60 → 30). Miss → 0. Distance is the geodesic distance from the pin tip to the nearest point of any way that carries the street's name. The canvas numbers follow this (84 m → 74, 240 m → 39; round total 695 XP).

- **Levels:** level n needs 1 000 + 250 × (n − 1) XP to reach level n + 1, so level 2 starts at 1 000 XP, level 3 at 2 250, level 4 at 3 750. The canvas player has 3 555 XP: level 3, 1 305 / 1 500, 195 XP to level 4. Store total XP only; derive the level.
- **Known streets:** a street is known after a Great or Perfect answer (per city, by OSM way name). Home shows known / total named streets for the city ("62 / 1 240") and per district ("Vake 24 / 180"); totals come from the same Overpass query as round setup, cached per city.
- **Retry set:** the round's Close and Miss streets (3 on the canvas). Retry rounds score XP as normal but never add a second "known" for a street already known.

## 1 · Home

- **Components:** **CitySwitcher** (new: pin icon, city name `title.md`, chevron, 48 dp), XP pill (`.pd-pill`, `xp` icon, total XP), icon Button (`settings`); level card (shield badge with the level number, "Level 3", "195 XP to level 4", Progress XP bar at 87 %, "3 555 XP in total", "1 305 / 1 500 XP"); city card ("Streets you know", "62 / 1 240", **DistrictMap** mini map 120 dp tall with MapAttribution, legend swatches In progress · Complete · Not started, district rows with a minibar and count, tertiary "All 104 areas"); pinned footer with the resume caption and hero **Play**.
- **Layout:** top row 48 dp at the top safe area; the gap between the city switcher and the XP pill is **reserved for the streak pill** (Release 2). Cards stack with 16 dp gaps from `top + 64`; the page scrolls under the pinned footer (2 dp top rule). District rows: the two most recently played districts, then "All 104 areas" opens the area picker in Areas mode.
- **States:** returning player (canvas) · new city ("Lisbon", "0 / 860", empty line "No streets known yet. Play a round in Lisbon and the map starts filling in.", Play becomes **Choose an area**) · a longer translation (the legend wraps to two lines) · 360 dp.
- **Navigation:** Play → `/round` with the saved city, area and difficulty; when the open pack lacks the saved areas (offline Vake), Play becomes **Choose an area**. City switcher → `/city`. A district row → `/area` with that district picked. Settings → `/settings`. XP pill → nothing in the MVP (Release 2+ opens the Streak screen from its pill).
- **Motion, sound, haptics:** after a round the XP bar fills from the old value (`motion.count-up`); a level-up plays the big celebration on Results, not here. Districts that changed state fade in over `motion.duration.quick`. Reduce motion: final values.
- **Screen reader:** Play is labelled with what it resumes ("Play Tbilisi, Vake and Vere, Medium"); the XP bar reads "Level 3, 1 305 of 1 500 XP"; the mini map is decorative (the rows carry the same data).

## 1a · Welcome (first run)

- **Components:** Pindo (`happy`, 104 dp), Wordmark (`pindoro-wordmark` / `-dark`; 52 dp high), ListRow group (recent cities), tertiary Button ("Find another city", `search` icon), caption `label.md` `color.text.secondary`, hero `PindoroButton` with `play` icon and an `elevation.3` lip, icon Button (`settings`).
- **Layout:** top row 48 dp with the settings button on the right. The hero (Pindo, wordmark, tagline "Learn any town, street by street.") centres in the free space. Bottom-up: Play, caption with what Play resumes ("Tbilisi · Vake and Vere · Medium"), the tertiary button, the recent-cities list (up to 3 rows: city, country · area · difficulty).
- **States:** first run only (a raised card "No recent cities yet / Cities you play will show up here, ready to resume." and the primary **Choose a city**). Once a round is finished, `/` shows Home instead.
- **Navigation:** Choose a city → `/city`. Settings → `/settings`.
- **Motion, sound, haptics:** Pindo waves in on cold start only (`motion.spring.bouncy`, reduce motion: none). Button press as the system's 3D button (tap sound on Play, `selectionClick()`).
- **Screen reader:** Play is labelled with what it resumes: "Play Tbilisi, Vake and Vere, Medium".

## 2 · City picker

- **Components:** back icon Button, title `headline.sm`, **SearchField** (new), ListRow ("Use my location", `locate` tile), section title `title.md`, ListRow group (recents or results, `city` tile), Pindo (`happy`, 96 dp) for the empty state.
- **Layout:** stack with 16 dp gaps under the top row. While typing, "Use my location" and the recents hide; results replace them, with "4 places" (`label.lg`, live region) above and "Place search © OpenStreetMap contributors" (`body.sm`) below.
- **States:** recents · searching (field focused, matched part in `.pd-hl`: 900 weight, `color.primary.text`) · loading results (lane loader in the field) · no results ("No places called “Xyz”. Check the spelling or try a nearby town.") · no recents (Pindo + "No recent cities yet / Search for any town or city, or start from where you are.") · location permission denied (the row's subtitle says "Allow location in Settings", row opens the OS settings).
- **Data:** place search via Nominatim (or Photon) with a 300 ms debounce, `featuretype=city|town|village`, localised names. Respect the usage policy (own User-Agent, caching).
- **Navigation:** a city → `/area`. Back → Start.
- **Motion:** results fade in with `motion.stagger`. No sound; `selectionClick()` on row tap.
- **Keyboard:** no drawn keyboard on the canvas; the real one pushes the list up (`resizeToAvoidBottomInset: true`).

## 2a · City pack download

Streets and areas come from an offline city pack (SQLite; Tbilisi about 1 MB gzipped, bigger cities a few MB), downloaded the first time a city is chosen. It has no step of its own: choosing a city opens the Area picker, and any wait shows there.

- **Getting ready:** the map area stays empty and a panel at the bottom says "Getting Tbilisi ready", "Streets and areas download once, then work offline.", with a Minibar following the real bytes and "0.4 MB of 1.1 MB" (tabular figures). A pack already on the phone opens without it. The panel rises 8 dp and fades in as it appears and again when the download fails (`motion.duration.base`, decelerate; reduce motion: a 150 ms fade).
- **Failed:** "Couldn't download this city", "Check your connection and try again.", primary **Try again** (`retry` icon). Tbilisi adds "Available without internet: Vake." and a secondary **Play Vake** (the Vake-only pack bundled in the app); other cities get a secondary **Choose another city**. Error haptic once; the panel is a live region.
- **Not enough space:** the same panel, "Not enough space", "Free up a little space on your phone and try again.", shown when saving the pack fails because the phone is full.
- **Offline Vake:** the Area picker offers only Vake and the quarters and neighbourhoods inside it, the help line says "Offline: only Vake is available" and a **Try again** next to the count tries the real download again.
- **Updates:** newer packs download silently in the background and replace the current one; a round in play keeps the streets it already loaded. No UI, even when an update fails.
- **Copy (translations):** the place name stands alone after a colon ("Available without internet: Vake."), so a language that inflects nouns never changes a place name.

## 3 · Area picker

- **Components:** full-screen map, back `mapctl`, city pill (`.pd-pill--float` with `city` icon), map controls, MapAttribution, BottomSheet (`color.surface.overlay`, top `radius.2xl`) with a **SegmentedControl** "Areas · Circle · Rectangle" and **AreaSelector** (updated).
- **Areas (default when the city has them):** the city's districts (raions) and the smaller areas inside them: quarters (`place=quarter`, about 2–3 km, tiling most of the city) and neighbourhoods (`place=neighbourhood`, smaller, may overlap quarters). Tbilisi has 10 + 26 + 68 = 104. Each smaller area belongs to the district holding its centre; any mix can be picked, and the round draws from all of them, each street once.
- **Map by zoom:** below `camera.area-detail-zoom` (12, about 5.6 km across 390 dp) district chips and 1.5 dp district outlines; from 12, quarter and neighbourhood chips, district outlines at 2 dp as the frame, 1 dp quarter outlines and no neighbourhood outlines unless picked (they overlap the quarters). Outlines are `color.map.region.outline`. From 12 each district's name also sits along its outline as small grey text (`label.sm`, `color.text.secondary` on a 3 dp `color.map.basemap.land` halo): upright, parallel to the line, 12 dp to the district's side, about every kilometre where the line runs straight; chips win collisions. The player always knows which district a quarter is in. Picked areas: `color.map.area.fill` + 3 dp `color.map.area.stroke` and a cobalt chip with a check (`.pd-region-label`), at every zoom and never hidden by a collision. Other chips collide by sort key: the area touched last, then the larger area. Each chip sits at its area's pole of inaccessibility. A tap picks the smallest area of the zoom's level under the finger.
- **Picking rules:** picking a district takes in its smaller areas (shown as included); some picked areas make the district partial, and tapping it picks the whole district; tapping an area inside a picked district narrows the pick to that area, with a toast "Only Sololaki now" and **Undo** (5 s).
- **Sheet:** picked names as the title ("Vake and Vere"; "Vake + 2 more" past two; none: "Pick your areas"), the count ("0 of 104 areas", then "2 areas · 312 streets") with an "All 104" chip, help line ("Tap areas on the map or here. Pick one or more."; under 30 streets "Few streets: some may repeat"), Chips (picked first, then the nearest of the zoom's level), **Next** (disabled until one is picked: "Pick an area first").
- **All areas (90 % sheet):** "All areas", the count with **Clear** (tertiary, once something is picked), the few-streets line, a search field, then a checkbox row per district ("District · 312 streets"; checked, partial or empty; a chevron icon button opens its areas, and districts with a pick start open; the row stays pinned at the top while its areas scroll under it) with its areas indented 16 dp ("312 streets"; under a picked district "In Vake" and a soft check). Search matches the English and local names and a Latin spelling of a local name in another script ("vake" finds Vake); a matching district shows all its areas, otherwise only the matching ones under their district; no match: "No areas called “…”". **Done** at the bottom ("Pick an area first" while empty). Toasts show inside the sheet.
- **Circle:** fixed in the middle of the map; the map pans under it. Centre dot, radius pill, a resize handle at the circle's lower right (48 dp target). Slider 0.5–5 km in 0.5 km steps mirrors the handle. **Next**.
- **Rectangle:** fixed in the middle; four corner handles; size pill ("2.6 × 3 km"); min 0.5 km a side, max 10 km. **Next**.
- **Data:** presets come with the city pack: districts are the city's administrative subareas, quarters and neighbourhoods are OSM `place=quarter|neighbourhood` areas clipped to the city (same-name pairs keep the smaller; under 10 streets dropped), names per the street-name setting. A city without them opens in Circle and hides the Areas segment. Seeding between modes: circle → rectangle around it; districts → circle around their bounds.
- **Navigation:** Next → `/difficulty`. Back → City picker (or Start when opened from a recent row).
- **Motion, haptics:** mode change cross-fades the overlay (`motion.duration.fast`) and the sheet height animates (`motion.duration.base`, decelerate). Handles and the slider: `selectionClick()` per 0.5 km step. Toggling a district: chip press + `selectionClick()`; the polygon fill fades in over `motion.duration.quick`. Map recentre/zoom-to-fit: `motion.spring.gentle`. Reduce motion: no fades, the map jumps.
- **Screen reader:** see AreaSelector (chips and the All areas rows are checkboxes, a partial district reads as mixed; handles are buttons that also respond to arrow keys in 50 m steps).
- **Copy (translations):** "Areas" takes the everyday word for a city's districts and their parts; counts follow the language's own plural rules (ICU plurals), and place names never inflect: they stand after a colon ("Now only: Sololaki", "In: Vake").

## 4 · Difficulty picker

- **Components:** back icon Button, title, four **DifficultyCards** in a 2 × 2 radio group (art 120 dp, `title.lg` name, four-bar gauge, description), a raised card "How close counts at Medium" with three TierTally-style badges (Perfect on the street · Great within 100 m · Close within 300 m; values follow the selected level), primary **Start**.
- **Levels:** Easy "Major roads only" (`motorway`, `trunk`, `primary`), Medium "Adds secondary roads", Hard "Adds tertiary roads", Expert "Adds residential and small streets". Each includes the ones above it.
- **Layout:** grid gap 12 dp; card heights equalise per row; the scoring card sits 16 dp under the grid; Start pinned at the bottom.
- **Navigation:** Start → `/round` (loading state). Back → Area picker.
- **Motion, haptics:** selecting a card: press (lip removed) then the selected state with `motion.duration.quick`; `selectionClick()`. The scoring card's numbers cross-fade when the level changes.

## 4a · Loading, network error, not enough streets

These are the `/round` setup states, shown before question 1.

- **Loading streets:** map with the play area, sheet with Pindo `thinking` (88 dp), "Finding streets…", the level and area ("Medium · 2 km circle in Tbilisi"), lane loader, tertiary **Cancel**. Shown only after 300 ms (States rule); the Overpass query asks for named `highway=*` ways of the chosen classes inside the area and picks 10 distinct names, spread across the area. Reduce motion: the lane loader stops.
- **Network error:** no map (tiles may be missing too). `map` icon 48 dp in `color.error.text`, "Streets didn't load", "Check your connection and try again. Your city, area and difficulty are saved.", secondary **Change settings**, primary **Try again** (`retry` icon) at the bottom. Error tone + `HapticFeedback.vibrate()` (Android) / `heavyImpact()` (iOS) once.
- **Not enough streets here:** fewer than 10 distinct named streets for the level and area. Pindo `encouraging`, "Not enough streets here", the count ("This circle has 6 major roads at Easy. A round needs 10 streets."), secondary **Switch to Medium** (one level up, because each harder level adds road types), primary **Make the circle bigger** (districts mode: **Add a neighbouring district**). Hide the level button at Expert.

## 5 · Quiz question

- **Components:** top bar (icon Button `close` "Leave round" · Progress question bar, 10 segments (3 in a retry round) · **XP pill** with `xp` icon, XP this round), **StreetCard** plate, PlayerPin, map controls, MapAttribution, primary **Confirm**; first question of the first round only: **CoachMark** + pin reticle (new).
- **Layout:** plate 16 dp below the top bar with 16 dp gutters; Confirm at the bottom; map controls on the right above Confirm; attribution on the left above Confirm.
- **Plate fit (long names):** `headline.md` 26/32 → two lines, then step down 2 dp until it fits two lines, floor `size.plate.name-min` (20 × text scale), then wrap freely; never truncate. Test with a long name such as "Grand Union Canal Embankment North" on 390 and 360 dp and at 200 %. Implement with `TextPainter` in a `LayoutBuilder` (maxLines 2 test per size). Sub-line `body.sm`: transliteration in local mode, the local name in English mode.
- **States:** first-run hint (Confirm disabled, "Confirm. Drop a pin first.") · retry round (plate ask line "Try again: drop a pin on" with the `reroute` icon; the sub-line adds how far you were: "Marjanishvili Street · you were 1.2 km away"; question bar has 3 segments) · pin dropped · moving the pin (lifted 12 dp, wider fainter shadow) · scoring (Confirm shows the lane loader) · 200 % text (plate grows downward; if it would cover more than 45 % of the map, the sub-line moves to the reveal sheet).
- **Input:** tap drops or moves the pin; drag moves it (map pans with two fingers or when dragging off the pin); keyboard / switch: arrows move 8 dp, Shift 40 dp, Enter confirms.
- **Navigation:** Confirm → reveal (same route). ✕ → "Leave for now?" → Home with the saved round.
- **More states (canvas M-30 live, M-33):** pin falling and landing frames, dragging, pin outside the play area (outline + dimmed outside + toast, Confirm still allowed), offline mid-round (missing tiles drawn as the sunken grid, toast once, scoring stays local), resumed (toast "Welcome back. Your round continues at question 6.").

## 6 · Answer reveal (same screen, new state)

- **Components:** compact StreetCard (one line, may ellipsize), answer street in yellow paint, PlayerPin (no longer draggable), distance line + chip (ink), **RevealSheet** in tier colours (compact: about 240 dp plus the safe area): Pindo at 80 dp, a header row with the 44 dp tier badge, the tier label (`headline.md`) and the XP chip ("+74 XP"), the distance sentence, an optional chip row ("2 in a row" for Great or better), tier-coloured **Next** (Miss: **Got it**). Map auto-fits pin + street above the sheet with 24 dp padding.
- **Tiers:**

| Tier | Badge · label | Sentence | Pindo | Celebration (static frame on canvas) |
| --- | --- | --- | --- | --- |
| Perfect | `star` · "Perfect!" | "On the street. You know this city." | cheering, jumps | Big: 26 confetti pieces from the top, 10 dp lane-yellow edge glow, 12-dash burst around the badge |
| Great | `check-circle` · "Great!" | "84 m away. So close to perfect." | cheering, 12 dp hop | Medium: 12-dash burst around the badge, badge pop |
| Close | `target` · "Close" | "240 m away. You're in the right neighbourhood." | happy | Small: badge wiggle −6°, one cobalt ring pulse at the pin |
| Miss | `reroute` · "Not this time" | "1.2 km away. It's north-east of your pin. You'll see it again on your results." | encouraging | None; no XP chip |

- **Miss direction:** measured from the pin to the nearest point of the street (where the yellow paint starts), in eight 45° sectors centred on the compass points; a bearing on a border goes to the next sector clockwise. "It's north / north-east / east / south-east / south / south-west / west / north-west of your pin."; each translation gives the eight directions as whole sentences. Landmark sentences ("It runs along the river") come back when there is landmark data.
- **MVP specifics:** the XP pill counts up with the chip; no Pit stop yet, so a Miss says "You'll see it again on your results" and the street joins the retry set. The question-bar segment fills (yellow, or red for a Miss) as the sheet opens.
- **200 % text:** the sheet's content scrolls inside a max height; a 2 dp tier-fill rule marks the scroll edge; Next stays pinned.
- **Navigation:** Next → next question (plate slides out up 16 dp + fade, new plate slides in 24 dp + fade). After question 10 → `/results`.

### Motion, sound and haptics in the round

| Event | Motion | Reduce motion | Sound | Haptic |
| --- | --- | --- | --- | --- |
| Pin drop (tap) | Falls 24 dp, squash 14 %, one bounce, ground shadow 0.4 → 1, ring ripple at the tip; `motion.pin-drop` (520 ms), `motion.spring.bouncy` | Fades in at rest, 120 ms | Soft wooden "tok" (< 30 ms latency) | `lightImpact()` |
| Pin drag | Lifts 12 dp, shadow widens and fades; follows with `motion.spring.gentle` | No lift | None | None (one `selectionClick()` on pick-up) |
| Confirm | 3D press; halo pulse around the pin, 400 ms `motion.ease.standard`; Confirm shows the lane loader while scoring | No pulse | Confirm click | `mediumImpact()` |
| Reveal sheet | Map fits pin + street (`spring.gentle`); answer paint draws along the street 280 ms; sheet rises `motion.duration.base` decelerate; badge pops 80 ms later (`spring.bouncy`); XP counts up over `motion.count-up` | Sheet fades, map jumps, final numbers at once | Tier sound as the badge lands | Tier haptic as the badge lands |
| Perfect | Big, `motion.celebrate.big` (2 600 ms); repeats in a round drop to medium with "Perfect ×2" | Static badge, no confetti or glow | Bright three-note rise + bell | `heavyImpact()`, `mediumImpact()` +90 ms |
| Great | Medium, `motion.celebrate.medium` (1 400 ms); from the fifth Great in a row, a pop only | Static badge | Two-note rising chime | `mediumImpact()` |
| Close | Small, `motion.celebrate.small` (700 ms) | Static badge | Single soft blip | `lightImpact()` |
| Miss | Badge appears, Pindo encourages; `motion.duration.base` | Same | Soft low two-note fall (never a buzzer) | `selectionClick()` ×2, 60 ms apart |
| Next | Plate out (16 dp up, `motion.duration.fast`), map recentres, new plate in (24 dp, `motion.duration.base`); celebrations stop at once | Cross-fade 150 ms | None | `selectionClick()` |

Celebrations never block input. Sounds follow the Sound toggle, haptics the Haptics toggle, independently of reduce motion.

## 7 · Round results

- **Components:** close icon Button ("Done, back to home"), "Round complete!" (`headline.lg`, wraps at large text), area line, Pindo (`proud`, 64 dp) beside **RewardTotal** (lane-yellow plate, `xp` icon, "+695 XP"), level row ("Level 3", Progress XP bar, "1 305 / 1 500"), stat chip "+4 streets known", section title "Your streets" with a secondary md **Retry 3 missed** (`reroute` icon), **ResultRow** list (tier tile, street name, tier word in tier ink + distance, " · to retry" on Close and Miss rows, XP in `color.reward.text`), footer with secondary **Change settings** (48 dp) and primary **Play again**.
- **Layout:** the page scrolls under a pinned footer (2 dp top rule in `color.line.base`). The footer keeps Play again in the thumb zone.
- **States:** default · a row opened on the map (`/results/street/:index`: map with the answer street, the pin and the distance line; compact plate in the top bar with a back `mapctl`; bottom sheet with the row's tier, name, transliteration, distance and XP, **Previous** / **Next street** secondary buttons and **Back to results**) · 200 % text (title on two lines, rows grow, footer stays pinned).
- **Retry:** **Retry 3 missed** starts a 3-question round of the Close and Miss streets (same city, area and difficulty), then returns to a short results screen for those 3. Hidden when the round had no Close or Miss; then the header shows "No streets to retry".
- **Level up (canvas M-41, live):** when the bar reaches the end it glows, then a full-screen **LevelUpScreen** opens from the bar (circular reveal): cobalt, the shield stamps the new number (0.92 → 1.22, −6°, spring.bouncy), 16 rays, confetti, Pindo with a white sticker outline, "Level 4!", the total, a "Next: level 5" card and a lane-yellow **Continue**. Back on Results the bar has refilled into the new level and the chips add "Level 4!". Several levels in one round play once.
- **Variants (canvas M-42):** flawless (no retry, "No streets to retry"), tough (5+ Close or Miss: the footer primary becomes "Retry 8 missed"), retry results.
- **Motion, sound, haptics:** RewardTotal pops then counts up (`motion.count-up`, soft rising ticks, `mediumImpact()` on landing); the XP bar fills after the count; rows stagger 40 ms; medium celebration on arrival (big if the round had a first-ever Perfect). Reduce motion: everything at its final value.
- **Navigation:** Play again → `/round` with the same settings (new set of streets). Retry 3 missed → `/round?retry=<roundId>`. Change settings → `/area`. Close or system back → Home.

## 8 · Settings

- **Components:** back icon Button, title, cards / list groups with section titles (`title.md`), **SegmentedControl** (now also as real buttons, `.pd-seg > button`), Toggle rows (ListRow with `role=switch`), ListRow "Map data credits".
- **Rows:** App language: English and each translation, every language listed by its own name (switches the whole UI; restarts nothing) · Street names: Local | English, helper "English shows when the map has it, otherwise the local name." · Theme: Light | Dark | System · Sound (chimes, taps, celebrations) · Haptics (pin drop and answers) · Map data credits → a page with "© OpenStreetMap contributors" (ODbL, link to openstreetmap.org/copyright), "Map tiles © CARTO" (link to carto.com/attributions), the place-search credit and the FiraGO OFL licence (`LicenseRegistry`).
- **Behaviour:** changes apply immediately and persist (`shared_preferences`). Theme System follows `MediaQuery.platformBrightness`; switching animates `PindoroColors.lerp` over `motion.duration.base`. Sound/Haptics toggles: `selectionClick()` only when Haptics stays on.

## Production details (canvas sections 9–15)

The MVP page has a second half for implementation: **M-00** flow map, **M-01** rules (round lifecycle and saving, choosing the 10 streets, scoring with half-widths per road class, XP and levels, caching and offline, platform), live animated boards that loop on the canvas, with Replay, slow motion ×4 and reduce motion switches and a timeline that lights up as each phase plays (**M-10** cold start, **M-30** the round: tap the map to drop a pin, Confirm and Next, with real distance scoring, **M-40** results arrival, **M-41** level up, **M-43** Home after a round), states (**M-11** location explainer, locating, denied · **M-12** search loading, no results, offline · **M-13** first Home coach mark · **M-20** circle resize, nothing picked, all districts sheet, a town without outlines · **M-33** round edge cases · **M-34** saved round · **M-42** results variants · **M-50** map data credits), **M-60** motion, sound and haptics table with the sound kit, **M-61** screen reader walkthrough with focus order, **M-62** copy deck (157 strings in English, format rules) and **M-70** a quick dark check (Home, quiz, reveal, results).

- **Cold start:** native splash (cobalt.500, white pin, reversed wordmark; dark: asphalt.950) held with `FlutterNativeSplash.preserve()`; the first Flutter frame matches it, the pin hops 28 dp and lands with a squash on a short road, then Home (or Welcome) opens out of the yellow dot with a circular reveal. About 1 s; warm starts skip it.
- **Reveal paint** grows outwards from the point on the street nearest the pin (PathMetric.extractPath), so the eye goes straight to the gap; then the ink line and chip, then the sheet.
- **Sound kit:** 14 short mono sounds (−16 LUFS, under 1.2 s; fanfare 2.4 s), preloaded, low-latency pools; pin_tok within 30 ms of the touch.
- **New parts on the canvas:** LaunchScreen, LevelUpScreen, CreditsScreen; new states in QuizScreen, HomeScreen, CityScreen, AreaScreen and ResultsScreen. No new tokens or components; the reveal sheet keeps its title and chips above the burst rays (`.pd-sheet .pd-burst`).

## Accessibility checklist (all screens)

- 48 dp targets everywhere (chips 40 dp inside 48 dp; map controls, handles and icon buttons 48 dp).
- Primary actions at the bottom; destructive or leaving actions never in that spot.
- Text scales to 200 % without clamping; the plate, reveal sheet and results were drawn at 200 % on the canvas.
- Screen-reader labels: plate heading "Find: <name>, <transliteration>"; map region with how to drop the pin; pin ("Your pin. Double-tap and hold to move."); Confirm (disabled: "Drop a pin first"); question bar "Question 5 of 10"; reveal live announcement ("Great. 84 metres away. Plus 74 XP.") with focus on Next; result rows as full sentences; reward "Plus 695 XP"; level bar "Level 3, 1 305 of 1 500 XP". Pindo is decorative except in empty states.
- Never colour alone: tiers carry icon + label + sound + haptic; picked districts carry a check; the question bar is announced.
- Reduce motion has a calm version of every animation (tables above).

## New in the system for the MVP

Components: SearchField, MapAttribution, AreaSelector (districts, circle, rectangle), CoachMark (+ pin reticle), RewardTotal, TierTally, ResultRow; DifficultyCard and celebration-frame styles moved into the bundle; SegmentedControl accepts buttons. Tokens (all aliases of existing values, no new colours): `color.input.*` (6), `color.coach.*` (3), `color.map.area.center`, `color.map.area.label.*` (3), `color.map.reticle`, `color.map.attribution.*` (2), `color.map.region.*` (3), and `size.plate.name-min` (20). Updated guidance: StreetCard fit rule, PlayerPin reticle, Progress XP pill and bar, RevealSheet MVP notes, DifficultyCard OSM road classes. Added with Home: **CitySwitcher** (`.pd-cityswitch`), DistrictMap states in the bundle (`.pd-map-district` new / progress / mastered / locked / selected, `.pd-map-hatch`), the district minibar (`.pd-minibar`) and legend swatches (`.pd-swatch`). No new tokens.

## Releases after the MVP

Each release has its own canvas page. **New** screens are drawn in the light theme; **Changed** screens sit next to the version they replace. Everything uses existing tokens; the bundle classes for later releases are already in the system (bottom navigation buttons, streak pill states and freeze card, league header, ranks, avatars and zones, route overlays and endpoint pins, and for v2.0: **PlateChoice**, **StatTile**, route-drawing overlays `.pd-map-junction`, `.pd-map-finger`, `.pd-map-ghost`, `.pd-map-car`, and the LessonPath sheets and unlock motion).

### R2 · v1.1 · Daily habit

- **Home (changed):** streak pill (`flame`, "13") in the reserved top-bar slot; a daily-goal ring (56 dp, 9 dp stroke) on the level card. Tapping the pill opens Streak.
- **Streak (new):** count in 56 / 64 heavy tabular figures with "day streak" and "Your best: 21 days"; month calendar (`.pd-cal`: goal met in `color.streak.day.done`, freeze in `color.streak.freeze.*`, today ringed); freeze card "Streak freeze equipped · 1 of 2"; daily goal card with **Change**; pinned **Play a round**.
- **Rules:** a day counts when the daily XP goal is met (250, 500 or 1 000; default 500). A freeze is earned every 7 days in a row, at most 2 held, used automatically on a missed day. The pill shows `.pd-pill--risk` after 18:00 when today's goal isn't met, `.pd-pill--frozen` on a frozen day, `.pd-pill--off` at 0.
- **Results (changed):** "13-day streak" chip once today's goal is met. **Settings (changed):** Daily goal row and a Reminder switch (19:00 by default; fires only when the goal isn't met: "Your 13-day streak ends at midnight. One round keeps it going.").
- **Flutter:** `flutter_local_notifications` with one daily schedule, cancelled for the day when the goal is met; streak state in the local DB keyed by local date.

### R3 · v1.2 · Pit stop and mastery

- **Pit stop (new):** Pindo `encouraging`, "7 streets to tune up", the rule line; a list of due streets with tier tile, name, last result and age, and a 4-bar gauge for the review step ("Review step 2 of 4"); "+ 3 more streets"; the last Pit stop's TierTally; pinned **Start Pit stop · 7 streets**.
- **Rules:** Close and Miss answers enter the Pit stop. Reviews come back after 1, 3, 7 and 21 days; two Greats in a row graduate a street; a Miss resets it to step 1.
- **Home (changed):** Pit stop card on top when anything is due ("7 streets due today", **Review**); districts whose streets are all known become **mastered** (`color.map.district.mastered.*`, cobalt: you own them) and show "Complete".
- **Reveal, Miss (changed):** "You'll see it again on your results" becomes a chip "Added to your Pit stop" (`wrench`, `color.path.node.review.icon`); Close gets the same chip. **Results (changed):** chip "3 to your Pit stop"; Close and Miss rows say "in your Pit stop".

### R4 · v2.0 · Lessons and road trips (full spec)

The canvas page "R4 · v2.0 Lessons and road trips (full spec)" has the flow map (R4-00), the rules (R4-02) and every screen and state step by step (R4-10 to R4-70), each board with interaction notes and a Flutter hint. Screen components: PathScreen, LessonScreen, LessonDoneScreen, RouteScreen, UnitGuideScreen, MeScreen, WhatsNewScreen, plus HomeScreen (Free play tab) and PitStopScreen (tab, empty).

**Rules**

- **Course:** one per city; one unit per district, nearest-first from the district the player picks. A unit is lessons 1–3 → Pit stop → lessons 4–6 → Final drive. A stop unlocks when the one before it is done; the next unit opens when the Final drive is passed, or by passing a locked unit's Final drive (Jump ahead: the whole unit becomes done, checks only). Cities without district polygons get units by rings from the centre.
- **Lesson:** 11 steps. 4 new-street cards (no XP), then 4 pin drops and 2 "Which street is this?" mixed, then 1 road trip, all on the lesson's 4 streets (distractors from the unit). Mistakes (Close or Miss pin drop, wrong name, a road trip given up) come back once at the end at half XP; the bar grows a segment per mistake. A lesson can't be failed; a fix that's wrong again sends the street to the Pit stop. No mistakes = Perfect (yellow star, +50).
- **XP (Medium):** pin drop as the MVP (100 / 90→70 / 60→30 / 0); name the street 50 / 0; road trip 100 / `round(90 − 1.2 × p)` / `round(60 − (p − 25))` / 0; finishing +20; Perfect +50; unit bonus +100; Practise = test steps only at half XP, no bonuses; difficulty multipliers as the MVP. Max 670 per lesson.
- **Road-trip tiers:** p = drawn ÷ shortest − 1 on the same graph (one-way ignored). Perfect ≤ 3 %, Great ≤ 25 %, Close ≤ 60 %, Miss > 60 % or "Show the route". The Final drive passes when all 3 trips are Close or better; a Miss offers a new trip.
- **Known streets:** Great or Perfect pin drop, or a right name first time.
- **Pit stop on the path:** this unit's mistakes so far, one pass (R3 round with the reroute plate); required for lesson 4; completes itself when empty. Spaced repetition stays in the Pit stop tab.

**Screens and states**

- **Path (R4-10 to R4-13):** sticky compact signpost (unit number, district and progress, title, book button → Unit guide; locked units show a lock and open a sheet with Keep going / Jump ahead); a 24 dp road curving through round 3D stops 104 dp apart, asphalt up to the current stop and soft grey after it. Stops: done (cobalt, check), Perfect (yellow, star), current (72 dp, progress ring, Start tip, float), Pit stop (locked colours with wrench → white at 72 dp with a ring and a "Tune up" tip → done), Final drive (trophy, 72 dp, ring shows trips done; yellow when passed), locked (grey). See LessonPath. States: mid-unit, end of unit, new city (one-time coach mark), new player, loading (skeletons, then thinking Pindo + lane loader after 2 s), error (Try again, Open Free play). Tapping a stop opens a sheet: lesson (difficulty, 4 new streets, up to 670 XP, **Start lesson**), done or Perfect (result, **Practise again**, **See the streets**), Pit stop, Final drive. A locked stop wiggles and shows a coach bubble instead.
- **Lesson (R4-20 to R4-24):** one map screen driven by a step list. Top bar: ✕ (Dialog: Keep learning / Leave), step bar with one segment per step, XP this lesson. New-street card: plate "New street · n of 4", the street painted yellow, a short sheet with where it is, one line of facts ("2.1 km · avenue · crosses 9 streets"), **Hear the name** (TTS), **Got it** / **Start the test**. Which street is this: a one-line question card, the street painted yellow, three compact PlateChoice options, **Check**; after Check a short feedback bar in Great or Miss colours replaces the Check button (the options and most of the map stay visible). Pin drop: the MVP quiz and reveal; Close and Miss add "Comes back at the end". Fixes: a list of the mistakes, **Fix them**, then each with the reroute plate. Lesson complete: RewardTotal, StatTiles (accuracy, new streets, time), level bar, level-up and streak chips, **Continue**; Perfect adds the big celebration.
- **Road trip (R4-30 to R4-34):** plate with the destination; A and B endpoint pins; drag from A, the route snaps junction by junction (cobalt dashes over a white halo), a ring marks the next junction, the ink chip shows the distance so far; ← undoes the last street (hold: start over); map controls; **Show the route** (asks first; counts as a Miss); **Check route** unlocks on reaching B. Off-road drags show a rubber band and, after 1 s, a toast. First road trip ever: dotted ghost route with a looping finger dot and a coach note. Check → lane loader → replay (the car drives the best route over 1 200 ms with the yellow paint drawing behind it; Skip) → the map pans up 60 dp and the tier sheet rises with an ink chip at the detour. Screen readers (or Settings → Accessibility → Choose turns from a list) get turn by turn: a list of the next streets at each junction with headings, Undo last turn, Check route.
- **End of a unit (R4-40, R4-61):** Final drive sheet → 3 road trips (bar shows trips) → unit complete (trophy shield, numbers, next unit signpost, **Continue to Vere**) → the path flips the next signpost open and scrolls to its first lesson.
- **Tabs (R4-14):** Path · Free play · Pit stop · Me (+ Leagues in v2.1). Free play is the MVP Home without the settings gear; Pit stop is the R3 list with a due-count badge and an "All tuned up" empty state; Me has the level card, four StatTiles, cities with progress and the settings gear.
- **First launch (R4-50, R4-51):** existing players see What's new once, then placement (a lesson is done when 3 of its 4 streets are known; a unit when all its lessons are), with **Start lesson n** or **Start from Unit 1 instead**. New players: Welcome → City → "Where do you want to start?" (districts, nearest first) → path with lesson 1 current.

**Motion, sound and haptics** are tabled on board R4-63; the two storyboards (R4-60 next stop unlocks, 900 ms; R4-61 next unit opens) give the frame timings. Every animation has a reduce-motion version (final state or a 150 ms cross-fade).

**Flutter architecture:** `StatefulShellRoute.indexedStack` for the four tabs; `CourseRepository` builds and caches units per city (OSM boundaries, named ways, a road graph with A* for best routes); `LessonController` holds the step queue and appends `RedoStep`s; the lesson, Pit stop and Final drive reuse one map screen with different step lists; progress writes locally first (`UnitProgress`, `LessonResult`, `KnownStreet`) and syncs in v2.1. Starting a lesson caches its streets, graph and tiles (zoom 14–17) so it survives a lost connection; a killed app resumes the same step for 24 h.

### R5 · v2.1 · Leagues

- **League (new):** street-plate header (`.pd-league-head`: `flag` in yellow, "Avenue league", "Top 5 move up · 3 days left", a six-step ladder); 30 players ranked by this week's XP; medals for 1–3, initials avatars on token colours, your row in `color.primary.soft`; zone dividers with text and a chevron. Leagues: Alley → Lane → Street → Avenue → Boulevard → Highway.
- **Results (changed):** chip "Up to 4th in Avenue league" when the round moved you up. **Bottom bar (changed):** five destinations, Leagues uses the `flag` icon.
- **Needs** accounts and sync across devices (not designed yet).

## Decisions to confirm

- **Level curve:** 1 000 + 250 × (n − 1) XP per level (level 4 at 3 750 XP, level 10 at 18 000).
- **Retry set** = Close + Miss. Only Misses would make retries shorter but leave Close streets unpractised.
- **Streak freezes are earned** (one per 7 days, hold 2), not bought: there is no currency besides XP.
- **Release order:** daily habit before the Pit stop, because a streak brings players back to use it.
- **Road-trip tiers** (v2.0): Perfect ≤ 3 %, Great ≤ 25 %, Close ≤ 60 % longer than the best route; one-way streets ignored in lessons.
- **Lesson shape** (v2.0): 4 new streets, 6 tests, 1 road trip; mistakes once more at half XP; lessons can't be failed; the unit's Pit stop is required.
- **Brand pin** (Nov 2026): the rounder 40 × 48 pin replaced the 40 × 56 teardrop everywhere (map pins, A/B pins, Pindo, logo mark, wordmarks, app icon, splash); lesson stops became round buttons.

- **Not enough streets:** the fix offered is a *harder* level, because each harder level adds road types (Easy has the fewest streets).
- **Scoring formula** above (Great 90 → 70, Close 60 → 30) is a v1 proposal; the tiers and thresholds come from Feedback tiers.
- **District names** come from OpenStreetMap and can differ from local usage (for example Vere appears as "Vera" in some datasets); allow a per-city alias list if players report it.
- Translations are drafts for a native review.
- **Saved rounds** (Nov 2026): a round saves after every answer and resumes from Home; XP counts as you go; one saved round, expiring after 7 days or when the city or area changes.
- **Level up** is a full-screen moment, not inline on Results.
- **Street choice** proposals: skip names under 150 m in total, spread with a 3 × 3 grid, prefer unknown streets; Perfect uses a half-width per road class (motorway 14 m … residential 5 m) + 20 m.
