# Pindoro v3 learning system: spec

Source of truth for the v3 rebuild ("Learn the whole city"). It condenses two research reports
(`docs/research/01-learning-every-street.md`, `docs/research/02-routes-landmarks-imagery.md`) into
decisions and numbers. Screens: canvas "Pindoro screens: MVP and releases", page "v3 · Learn the whole
city" (`docs/design/v3-screens.md` lists every board). Every number marked **(tunable)** lives in one
constants file and is a starting value to be checked against the review log.

Goal: the player can see any street name and place it on a blank map, recognise a street from a photo,
drive from any A to any B without GPS, and recite the route by heart. First city: Tbilisi (3,282 core
streets ≥ 150 m; 4,465 in total).

---

## 1. Architecture

- All learning logic lives in a pure Dart package, `packages/pindoro_learning` (no Flutter, no I/O,
  no `DateTime.now()`: the clock is injected). It depends on `pindoro_core` for geometry and pack models.
- The app (`apps/mobile`) owns persistence (Drift/SQLite), UI and platform services (TTS, location,
  speech). It calls `pindoro_learning` with plain data and stores what it returns.
- The pack pipeline (server side, at build time) computes everything graph-heavy once: families, chunks,
  directed edges, turn restrictions, junction items, landmark salience, scene image selection.
- No server-side learning logic. The server only serves packs, tiles, optional backups.
- Determinism: given the same card states, log and clock, the planner returns the same session.
  Randomness (fuzz, tie-breaks) takes a seeded `Random`.

## 2. Data

### 2.1 Pack additions (read-only, built by the pipeline)

| Table / field        | Contents                                                                                                                                                                                                                                                                             | Used by                                  |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------- |
| `street.ring`        | `floor(dist(centroid, city centre) / 2 km)`; the centre is `centre` in `city.yaml` (Freedom Square for Tbilisi), which also becomes `city.center_lat/lon`                                                                                                                            | curriculum order                         |
| `street.bank`        | `L` / `R` side of the river (by centroid); the river is `river` in `city.yaml`                                                                                                                                                                                                       | curriculum order                         |
| `street.tier`        | `A` skeleton (motorway, trunk, primary) · `B` grid (secondary, tertiary) · `C` residential, unclassified, living                                                                                                                                                                     | curriculum, retention                    |
| `street.chunk_id`    | one `neighbourhood`-kind area per street (68 in Tbilisi): the one holding most of its length; streets in none go to the nearest neighbourhood by centroid                                                                                                                            | curriculum                               |
| `street.etymology`   | OSM `name:etymology`, null when absent                                                                                                                                                                                                                                               | intro card                               |
| `district.parent_id` | for a neighbourhood: the raion (`kind = district`) containing its centre                                                                                                                                                                                                             | chunk → district rows                    |
| `chunk_neighbour`    | `(chunk_a, chunk_b)`, both orders, for neighbourhoods whose boundaries come within 50 m                                                                                                                                                                                              | §6.3 "borders the most completed chunks" |
| `family`             | `parent_street_id`, `child_street_id`, `kind` (`lane` შესახვევი / `dead_end` ჩიხი / `passage` გასასვლელი), `n` (the number), `orphan` (child centroid > 1.5 km from parent geometry). Parsed from `name_ka` (`<parent> <Roman numeral> <kind word>`); a child can itself be a parent | intros, sibling caps, confusables        |
| `edge_directed`      | directed edges: `oneway=yes/-1`, `junction=roundabout` ⇒ one-way; `oneway:psv` ignored                                                                                                                                                                                               | recitals, drives, junction items         |
| `turn_restriction`   | from OSM `type=restriction` relations (`from` way, `via` node/way, `to` way; `no_*`, `only_*`; `motorcar` variants only)                                                                                                                                                             | edge-expanded graph                      |
| `junction_item`      | `(junction_id, approach_edge_id, exit_edge_id)` selected by coverage (§6.6), with `layer` (`skeleton` / `gateway_out` / `gateway_in` / `bridge`) and `rank`                                                                                                                          | J, G, B cards                            |
| `landmark`           | OSM landmarks with `kind`, `name`, `brand`, `salience` (§9), attached `junction_id`, `approach_edge_id`, `side`, `relation`                                                                                                                                                          | J, L cards                               |
| `scene_image`        | `image_id, junction_id, approach_edge_id, heading, captured_at, source, licence, author, file` (cropped WebP, 960 × 540 or 1280 × 720)                                                                                                                                               | S cards                                  |

### 2.2 Local tables (app database)

```
card_state(item_id TEXT PK, type TEXT, state TEXT,           -- new|learning|review|relearning|suspended
           stability REAL, difficulty REAL, last_review_at INT, due_at INT,
           reps INT, lapses INT, last_rating INT, last_distance_m REAL, last_snap_id TEXT,
           prior_known INT, intro_at INT)
review_log(id INT PK, ts INT, item_id TEXT, type TEXT, format TEXT, rating INT,
           distance_m REAL, snap_id TEXT, rt_ms INT, elapsed_days REAL,
           r_before REAL, s_before REAL, d_before REAL, session_id TEXT, source TEXT)  -- append-only
confusion(street_a TEXT, street_b TEXT, count INT, last_at INT, PRIMARY KEY(street_a, street_b))
landmark_personal(id TEXT PK, name TEXT, kind TEXT, lat REAL, lon REAL,
                  junction_id TEXT, approach_edge_id TEXT, side TEXT, created_at INT)
implicit_evidence(id INT PK, item_id TEXT, ts INT, source TEXT, outcome INT)        -- recitals, drives
-- learning settings (minutes_per_day, home, work, toggles) are typed columns on the app's existing
-- user_settings table, not a separate key-value table (§16)
```

Added by later milestones: `card_state.note TEXT` (leech mnemonic, M4), `turn_override` (local "report
this turn" fixes, M5), `run` (route-book runs, M6). See §16.

`source` in the log: `session`, `placement`, `explore`, `recital`, `drive`. Never delete log rows;
the optimiser needs them. Street ids are already stable across pack versions: the pipeline matches
them by name + way overlap (`identity.json`) and never revives a retired id. A P/N/E card is keyed by
its NamedStreet (§16), and cards whose street is no longer in the pack are skipped, not deleted.

## 3. Items and cards

Item id scheme: `P:{streetId}`, `N:{streetId}`, `E:{streetId}`, `J:{junctionId}:{approachEdgeId}`,
`G:{chunkId}:{gatewayJunctionId}:{out|in}`, `B:{bridgeId}:{bank}:{approachEdgeId}`, `C:{streetId}`,
`L:{landmarkId}:{1|2|3}`, `S1:{imageId}`, `S2:{imageId}`, `S3:{imageId}`, `R:{runId}`.
Every id inside an item id must survive pack rebuilds (§16): `{streetId}` is the NamedStreet's longest
part id, a junction is `n<OSM node id>`, an approach or exit edge is the OSM node id of the neighbouring
junction along it (so `J:n123:n456`), and bridge, landmark and image ids come from OSM or Mapillary ids.
The pack's own `junction.id` is pack-local and never goes into an item id.

| Card             | Cue → answer                                                               | Who gets it                                      | Unlocks when                                                                   |
| ---------------- | -------------------------------------------------------------------------- | ------------------------------------------------ | ------------------------------------------------------------------------------ |
| P pin            | name → place on the blank map                                              | every street in scope                            | introduced                                                                     |
| N name it        | painted street → name (self-graded)                                        | tiers A and B + every family parent (~800)       | P stability ≥ 7 d                                                              |
| E extent         | name → both ends                                                           | streets > 1.2 km                                 | P stability ≥ 7 d                                                              |
| B bridge access  | street + bank → bridge and the turns onto it                               | ~48 (12 bridges × 2 banks × ~2 approaches)       | tier A streets introduced                                                      |
| J junction       | street + heading + target + landmark → exit (+ street turned onto)         | ~450 skeleton decisions, then district junctions | skeleton: month 1; others: district grid ≥ 80 % Solid                          |
| G gateway        | chunk + direction → exit junction + street                                 | ~6 per chunk out (~400), in = phase 2            | ≥ 70 % of the chunk's parent streets Known                                     |
| C connection     | street → its end streets / "which street joins A and B"                    | grid + parents (~400)                            | the street and both ends Known                                                 |
| L landmark       | L1 landmark → pin · L2 landmark → junction · L3 junction + turn → landmark | ~300 + personal                                  | personal: immediately; OSM: when its street is Known                           |
| S1 scene → name  | photo → street name (typed)                                                | grid and up, one approach each (~800, phase 2)   | P and N Solid                                                                  |
| S2 scene → turn  | photo + destination → exit                                                 | skeleton + gateway approaches with imagery       | the J card is Known                                                            |
| S3 scene → place | photo → pin + heading (map on a separate screen)                           | as imagery allows                                | district ≥ 80 % Solid                                                          |
| R recital        | A → B by heart (speak, type, draw)                                         | route-book runs + weekly random pairs            | runs: all their J/G/B items Known; random pairs: weekly from the gateway phase |

Not scheduled (drills): family sweep (grades the children's P cards), crossings drill, bearing
questions, the three-option name question (intro scaffolding only).

## 4. Scheduler: FSRS-6

Ratings: `1 Again`, `2 Hard`, `3 Good`, `4 Easy`. `t` = whole days since the last review:
`floor((now − last_review) / 24 h)`, as py-fsrs counts them. A review is "same-day" when `t < 1`
(under 24 h since the last review), not when it falls on the same calendar day.

Default weights (FSRS-6 published medians; replace only with an offline fit, §12):

```
w = [0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796,
     1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542]
```

```
decay  = w[20];  F = pow(0.9, -1/decay) - 1
R(t,S) = pow(1 + F*t/S, -decay)
I(r,S) = S/F * (pow(r, -1/decay) - 1)                        // next interval; I(0.9,S) = S
days   = clamp(round(I(r,S')), 1, maxIntervalDays)            // whole days, then fuzz
S0(G)  = w[G-1]
D0raw(G) = w[4] - exp(w[5]*(G-1)) + 1
D0(G)  = clamp(D0raw(G), 1, 10)                               // first review only
D'     = D + (-w[6]*(G-3)) * (10-D)/9
D''    = clamp(w[7]*D0raw(4) + (1-w[7])*D', 1, 10)           // new difficulty; D0raw(4) is NOT clamped
success (G >= 2), later day:
S'r = S * (1 + exp(w[8]) * (11-D) * pow(S,-w[9]) * (exp(w[10]*(1-R)) - 1) * h * b)
      h = (G == 2) ? w[15] : 1;  b = (G == 4) ? w[16] : 1
lapse (G == 1), later day:
S'f = min(w[11] * pow(D,-w[12]) * (pow(S+1, w[13]) - 1) * exp(w[14]*(1-R)),
          S / exp(w[17]*w[18]))
same day (any G):
S'  = S * exp(w[17]*(G-3+w[18])) * pow(S, -w[19]);  if (G >= 2) S' = max(S', S)
```

`R` in these formulas is `R(t, S)` with the whole-day `t` above, and `D` is the difficulty before the
review. The formulas follow py-fsrs 6.3.2 with no learning or relearning steps; the golden vectors
(§14) are the source of truth if this text and the vectors ever disagree. Relearning inside a
session is the planner's job (§7), not an FSRS state.

| Parameter         | Value                                                                                                                                                |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Desired retention | 0.90 for P N E J G B C L R · 0.85 for S1 S2 S3 **(tunable)**                                                                                         |
| Tier C relief     | if the 7-day mean session time > budget × 1.2, tier C P cards use 0.85 until it drops below budget **(tunable)**                                     |
| Maximum interval  | 365 days **(tunable)**                                                                                                                               |
| Fuzz              | ±5 % on intervals > 3 days (seeded), applied to the whole-day interval and rounded again (py-fsrs's own fuzz bands are not used)                     |
| Relearning        | after Again: re-ask in the same session after 5–10 other items, then FSRS schedules (usually next day)                                               |
| Leech             | lapses ≥ 6 → `suspended`; re-introduce with intro card + side-by-side contrast with its top confusion + optional mnemonic note **(tunable)**         |
| Hand-check        | with defaults and only on-time Good answers, intervals run 2 → 11 → 46 → 163 d (py-fsrs 6.3.2; the reports' hand calculation said 2 → 12 → 50 → 174) |

Implicit evidence (recitals, drives): a failed decision counts as an Again review on that J/G/B card if
the card is due within 50 % of its interval or earlier; correct decisions are logged only, never counted
as reviews (no stability inflation from tests).

## 5. Grading

### 5.1 Pin (cards P, L1, G, and placement)

Inputs: pin point, target street geometry, response time `rt`, card history.

- `d` = distance from the pin to the nearest point of the target geometry.
- `snap` = street whose geometry is nearest the pin among streets within 150 m; null if none.
- `confusable(s)` = siblings in the same family + its parent + other streets with the same base name +
  any street in `confusion` with `s`.
- `halfwidth(class)`: the existing road-class half-widths.

| Check, in order                                                          | Shown as                            | Rating                                   |
| ------------------------------------------------------------------------ | ----------------------------------- | ---------------------------------------- |
| `snap ∈ confusable(target)` and `snap ≠ target`                          | Mix-up (Miss colours, reroute icon) | Again + upsert `confusion(target, snap)` |
| `d > 100 m`                                                              | Close (≤ 300 m) or Miss             | Again                                    |
| `d ≤ 100 m`, `snap ≠ target` (non-confusable neighbour)                  | Great                               | Hard                                     |
| `d ≤ 100 m`, `snap = target`, `rt > 20 s`                                | Great or Perfect                    | Hard                                     |
| `d ≤ halfwidth + 20 m`, `snap = target`, `rt ≤ 6 s`, ≥ 2 prior successes | Perfect                             | Easy                                     |
| otherwise (`d ≤ 100 m`, `snap = target`)                                 | Great or Perfect                    | Good                                     |

Thresholds 100 m, 20 s, 6 s are **(tunable)**. The old difficulty multipliers (×1.5 … ×0.5) are removed.
Display tiers keep their colours, icons, sounds and haptics; the XP chip becomes "Next review in N days".

### 5.2 Other cards

- **N name it**: self-graded "Forgot" = Again, "Knew it" = Good. Every 10th N review is verified with a
  6-name choice that includes confusables (wrong = Again).
- **E extent**: each end counts if within `max(150 m, 10 % of length)`. Both = Good, one = Hard, none = Again.
- **J / B / S2 decisions**: exit correct and (if typed) street correct = Good; exit correct, street wrong
  or missing when asked = Hard; wrong exit = Again (re-asked this session; show where the chosen exit leads
  and the sibling junction it is confused with).
- **G gateway**: pin graded like P against the gateway junction (radius 60 m), plus street name. Both = Good,
  one = Hard, neither = Again.
- **C connection, S1**: typed recall, fuzzy match (normalised Levenshtein ≤ 0.25 against Georgian, English,
  transliteration and personal aliases). Match = Good, no match = Again; multiple choice only after a failed
  recall and it never counts.
- **L2 / L3**: pick or type; correct = Good, else Again.
- **Bearing**: error ≤ 20° Great, ≤ 45° Close, else Miss; not scheduled.

### 5.3 Recital grading (card R and drives)

1. Tokenise; keep turn words (left/right/straight/U-turn and Georgian equivalents) and landmark mentions.
2. Resolve each name token by fuzzy match (≤ 0.25), ranking candidates by spatial plausibility (adjacent to
   the previous street); landmark tokens resolve to their junction.
3. Viterbi over candidate junctions on the edge-expanded directed graph, allowing up to 2 silent connectors
   of ≤ 150 m each (penalised); output the cheapest legal path through the named streets in order. Costs are
   metres; a U-turn adds `uTurnPenaltyM` and is forbidden on divided roads.
4. `stretch = length(path) / length(shortest legal A→B)`. Invalid if streets don't meet, a move is illegal
   (one-way, restriction) or > 2 connectors are needed.
5. Tier and rating: ≤ 1.03 and no hints → Perfect / Easy; ≤ 1.25 → Great / Good; ≤ 1.60 → Close / Hard;
   beyond or invalid → Miss / Again ("Not drivable" when illegal). A recital typed with next-street
   autocomplete is recognition, so it is capped at Great / Good.
6. Partial credit per decision: correct if legal and on some legal path to B with stretch ≤ 1.25 from there.
   Optional +0.1 per landmark named at a reorientation point (cap +0.3).
7. Failed decisions go to implicit evidence for their J cards (§4).

Drives: map-match the background GPS track (snap fixes to directed edges by distance and heading, fill gaps
with shortest legal paths), then grade as above. Flag U-turns and hesitations (speed < 5 km/h for > 10 s
away from traffic signals).

## 6. Curriculum

### 6.1 Scope

Phase 1 = the 3,282 streets ≥ 150 m (denominator of all progress numbers). Phase 2 = streets < 150 m,
unlocked per chunk once ≥ 80 % of its core streets are Solid.

### 6.2 Placement (once per city, about 15 min)

Pin every tier A street (88), then 5 random tier B streets per district. A first-sight Good/Easy creates the
card as rated Good/Easy (S0 = 2.31 d / 8.30 d) with `prior_known = 1`. If ≥ 4 of a district's 5 pass,
sweep the rest of that district's tier B the same way. "I don't know this one" leaves the street unseen.

### 6.3 Order

1. Tier B, city-wide: sort by `ring`, alternate `bank` within a ring, then length descending.
2. Tier C by chunk: start with the chunks holding the centre and the home / work anchors; then always the
   unfinished chunk that borders the most completed chunks (ties: distance to centre).
3. Within a chunk: parents by length descending → non-family streets by length → each family's children in
   numeric order.
4. New-slot split: while tier B is unfinished, 60 % of new slots go to B and 40 % to C (home first); then
   100 % C. **(tunable)**
5. Families: a child never before its parent reaches S ≥ 3 d; at most 4 new siblings of one family a day.

### 6.4 First exposure

Groups of 3 new streets from one chunk: optional pretest (children whose parent is Known: graded, not
scheduled) → intro card (§ design V3-20) → retrieval 1 after 3–6 other items (district zoom) → retrieval 2 at
the end of the session (city zoom, same-day FSRS update). Retrieval 1 sets S0/D0.

### 6.5 Route layers

Skeleton first (B cards, then skeleton J), gateways with each chunk, then district J cards. Any A → B =
A's gateway + skeleton path (bridge if banks differ) + B's gateway. Phase-2 route items (gateways in, S1)
are introduced only after the due count has stayed under the daily budget for 14 days in a row.

### 6.6 Junction item selection (pipeline)

Sample 20,000 random origin–destination pairs weighted by street length; compute shortest legal routes on the
edge-expanded graph; count each `(junction, approach, exit)` decision; greedily select until 90 % of decision
instances are covered **(tunable)**; `rank` = coverage order. Attach the top landmark within 60 m, preferring
the approach-side corner before the turn.

## 7. Session planner

```
budget   = minutesPerDay * 60                      // 15 | 20 | 30
nBase    = {15: 7, 20: 10, 30: 14}[minutesPerDay]  // (tunable)
tReview  = 12 s, tNew = 45 s                       // re-estimated weekly from review_log medians
due      = cards with due_at <= now, sorted by R ascending (most at risk first)
if due.length * tReview > budget:
    nNew = 0; reviews = due.take(floor(budget * 1.5 / tReview))      // backlog mode
else:
    reviews = due
    nNew = min(nBase, floor((budget - due.length * tReview) / tNew))
session = interleave([3 intros], [5 reviews], [retrieval 1 of those 3], ... ,
                     [all retrieval 2s + same-session relearns at the end])
```

- Route items (J, G, B, L, S) are reviews like any other; new route items are capped at 10 a day and paused
  when due > 120 % of budget.
- Drills: at most 1 family sweep per session (when ≥ 3 children due within 2 days), 1 crossings drill a day
  (on a Solid parent or grid street), 1–3 bearings per session (once the district's grid is ≥ 50 % Solid).
- "Learn 5 more" after a session adds 5 new streets; it is the only way past `nBase`.
- Sessions save after every answer; leaving keeps progress (no "lose progress" dialog).

## 8. Progress and motivation

| Label / number  | Definition                                                                                    |
| --------------- | --------------------------------------------------------------------------------------------- |
| Known (now)     | ≥ 1 successful P review on a day after `intro_at` **and** current R ≥ 0.80                    |
| Solid           | P stability ≥ 21 d                                                                            |
| Mastered        | P stability ≥ 90 d, last P review a success, N and E (where they apply) at S ≥ 21 d           |
| City memory     | Σ R_i(now) over the 3,282 core streets (unseen = 0); shown as streets and %                   |
| Recall rate     | share of the last 30 days' due reviews passed; healthy ≈ 0.90; < 0.85 ⇒ check grading/weights |
| Forecast        | due count per day for the next 14 days from current card states                               |
| Whole-city date | today + (unseen core streets ÷ current new-per-day)                                           |

Motivation rules:

- Removed: XP per answer, daily XP goal, levels, weekly XP leagues, Path, Pit stop tab, Jump ahead.
- Streak: a day counts when the due queue is cleared or the day's minutes are spent. Freezes (1 per 7-day run,
  hold 2) and the 19:00 reminder (only if reviews are due) stay.
- Milestones: City memory 500, 1,000, 1,500 … streets (R ≥ 0.8). Badges: a neighbourhood or district Mastered;
  "100-day maintenance"; "zero leeches".
- Friends (optional, later): cooperative board of City memory % and mastered neighbourhoods; no ranking by activity.

## 9. Landmarks

OSM tags and base type score: metro (`station=subway`, `railway=station|subway_entrance`) 1.0 · named bridge 1.0 ·
`place=square`, named `junction=roundabout` 0.9 · `amenity=fuel` 0.9 · `amenity=place_of_worship` 0.8 · `shop=mall`,
`supermarket`, `department_store` 0.8 · `amenity=bus_station`, `public_transport=station` 0.8 · `amenity=hospital|university` 0.7 ·
`historic=monument|memorial`, `tourism=attraction`, `man_made=tower` 0.7 · `leisure=stadium|park` 0.6 ·
`amenity=bank|pharmacy|fast_food` with brand 0.4 · `highway=traffic_signals` 0.3.

```
salience = 0.30*type + 0.15*brandOrName + 0.15*size + 0.10*wiki + 0.15*uniqueness + 0.15*structural   // (tunable)
size        = min(1, log10(footprint_m2 or building:levels*100) / 4)
wiki        = 1 if wikidata or wikipedia tag
uniqueness  = 1 / (same-type features within 300 m)
structural  = 1.0 within 40 m on the approach-side corner of the turn · 0.6 far corner · 0.3 along the route
```
Personal landmarks: salience 1.0, always preferred on their junction. Entry: long-press a junction or "here"
while parked → name, kind, snapped junction + approach (editable).

## 10. Imagery

| Source                                     | Use                                                                                  | Rules                                                                                                                                                                           |
| ------------------------------------------ | ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Mapillary (API v4)                         | offline scene cards where coverage exists                                            | CC BY-SA; download at pack build (signed URLs expire); show Mapillary logo + link and photographer credit; never in navigation synced to the device position; exclude NC images |
| Own 360° captures                          | decision junctions without coverage                                                  | host originals on a private Panoramax instance (Docker, PostGIS) on the home server; automatic face/plate blurring before anything leaves the device owner                      |
| Google Street View                         | only a "Look around in Google Maps" deep link (Maps URLs, opens the Google Maps app) | no API calls, no caching, no imagery inside Pindoro, never on a screen with the Pindoro map                                                                                     |
| Yandex, Apple Look Around, Bing, KartaView | not used                                                                             | coverage or terms don't fit                                                                                                                                                     |

Pack: per decision junction, the frame 25–40 m before it on the approach edge, reprojected to a forward 100°
field of view at the approach heading, exported as WebP. Budget ~2,100 images ≈ 170 MB (960 × 540) to 315 MB
(1280 × 720), downloadable separately from the street pack. Store licence and author per image.

## 11. Speech (recitals)

On-device Vosk with the small Georgian model (`vosk-model-small-ka`, ~45 MB, downloaded on demand). Restrict
recognition to a grammar of the city's street names, turn words and landmark names. Always show the transcript
as resolved chips with one-tap correction before grading; if confidence is low, fall back to self-grading.
English speech is best-effort. Verify the Flutter plugin on iOS before relying on it; typed and drawn
recitals must work without speech.

## 12. Tuning and data export

- Export `review_log` as CSV from Settings (share sheet).
- After ~1,000 reviews per card family (P; route items), fit FSRS weights offline (py-fsrs / fsrs-rs on the
  home server) and ship them as a JSON constants override.
- Calibration check: bin reviews by predicted R; observed pass rate within ±5 percentage points is healthy.

## 13. Constants (one file: `pindoro_learning/lib/src/constants.dart`)

| Name                                                           | Value                   |
| -------------------------------------------------------------- | ----------------------- |
| `fsrsWeights`                                                  | §4 list                 |
| `retentionDefault` / `retentionScene` / `retentionTierCRelief` | 0.90 / 0.85 / 0.85      |
| `maxIntervalDays`                                              | 365                     |
| `fuzzFraction`, `fuzzMinDays`                                  | 0.05, 3                 |
| `relearnGapMin`, `relearnGapMax`                               | 5, 10 items             |
| `leechLapses`                                                  | 6                       |
| `pinGoodMaxM`, `snapSearchM`                                   | 100, 150                |
| `rtHardMs`, `rtEasyMs`, `easyMinSuccesses`                     | 20000, 6000, 2          |
| `extentEndMinM`, `extentEndFraction`                           | 150, 0.10               |
| `extentMinLengthM`                                             | 1200                    |
| `unlockNameDays`, `unlockExtentDays`                           | 7, 7                    |
| `childParentMinDays`, `maxSiblingsPerDay`                      | 3, 4                    |
| `knownMinR`, `solidDays`, `masteredDays`, `masteredSideDays`   | 0.80, 21, 90, 21        |
| `newPerDay`                                                    | {15: 7, 20: 10, 30: 14} |
| `tReviewS`, `tNewS`                                            | 12, 45                  |
| `backlogCapFactor`                                             | 1.5                     |
| `tierBShare`                                                   | 0.60                    |
| `routeNewPerDayMax`, `routePauseFactor`                        | 10, 1.2                 |
| `fuzzyNameMax`                                                 | 0.25                    |
| `stretchPerfect`, `stretchGreat`, `stretchClose`               | 1.03, 1.25, 1.60        |
| `connectorMaxM`, `connectorMax`                                | 150, 2                  |
| `gatewayUnlockKnown`, `districtJunctionUnlockSolid`            | 0.70, 0.80              |
| `phase2ChunkSolid`                                             | 0.80                    |
| `bearingGreatDeg`, `bearingCloseDeg`                           | 20, 45                  |
| `junctionCoverage`, `odSamples`                                | 0.90, 20000             |
| `landmarkRadiusM`                                              | 60                      |
| `hesitationKmh`, `hesitationS`                                 | 5, 10                   |

Added with §16 (also in `constants.dart`; distances shared with the display tiers are referenced from
pindoro_core `ScoringConfig`, not copied):

| Name                                                                | Value                               |
| ------------------------------------------------------------------- | ----------------------------------- |
| `coreMinLengthM`                                                    | 150                                 |
| `groupSize`, `reviewsPerBlock`                                      | 3, 5                                |
| `retrieval1GapMin`, `retrieval1GapMax`, `retrieval1GapFloor`        | 3, 6, 2 items                       |
| `learnMoreCount`                                                    | 5                                   |
| `placementSamplePerDistrict`, `placementPassMin`                    | 5, 4                                |
| `familySweepMinChildren`, `familySweepWindowDays`                   | 3, 2                                |
| `crossingsPerDay`, `bearingsPerSessionMin`, `bearingsPerSessionMax` | 1, 1, 3                             |
| `bearingUnlockGridSolid`                                            | 0.50                                |
| `nameCheckEvery`, `nameCheckOptions`                                | 10, 6                               |
| `familyOrphanM`, `familyNearM`                                      | 1500, 500                           |
| `chunkNeighbourM`                                                   | 50                                  |
| `nearDueFraction`                                                   | 0.5 (implicit evidence and Explore) |
| `tierCReliefFactor`                                                 | 1.2                                 |
| `cityMemoryMilestone`, `maintenanceBadgeDays`                       | 500, 100                            |
| `uTurnPenaltyM`                                                     | 250                                 |
| `phase2StableDays`                                                  | 14                                  |
| `landmarkStructuralM`, `landmarkUniquenessM`                        | 40, 300                             |
| `sceneApproachMinM`, `sceneApproachMaxM`                            | 25, 40                              |
| `recitalLandmarkBonus`, `recitalLandmarkBonusCap`                   | 0.1, 0.3                            |
| `answerGapCapS`                                                     | 60                                  |
| `timeEstimateMinSamples`                                            | 50                                  |
| `migrationDueMinDays`, `migrationDueMaxDays`                        | 1, 7                                |
| `knownLabelMax`                                                     | 12                                  |

## 14. Test vectors (required before UI work)

- FSRS: golden vectors generated with py-fsrs 6.3.2 (same weights, retention 0.9, maximum interval 365,
  `learning_steps=()`, `relearning_steps=()`, no fuzz) for sequences `[3,3,3,3]`, `[3,1,3,3]`, `[1,1,3]`,
  `[4,4]`, `[2,3,3]`, including same-day reviews and late/early reviews (elapsed ≠ interval). Store as
  `shared/fixtures/fsrs_vectors.json` (`just fsrs-vectors`, script in `tools/fsrs-vectors/`); the Dart
  tests must match to 1e-4.
- Grader: fixtures for each row of §5.1 (pin on target, on a sibling lane, 140 m away, slow answer, fast perfect).
- Planner: backlog and normal mode, interleave order, sibling cap, parent-before-child.
- Recital grader: legal best route, legal detour (stretch 1.26 → Close), one-way violation (invalid).

## 15. Open questions

- Real Tbilisi junction count and decision-coverage curve (recompute §3 estimates from the pack).
- How often "Nth Lane / Dead End of X" lies near X (pipeline check: share within 500 m and 1.5 km).
- OSM turn-restriction completeness in Tbilisi; add a "report this turn" override stored locally.
- Seconds per review and per new street on a phone (measured from `review_log`; there is no
  self-experiment, decided 2026-11-14).
- Vosk on iOS via Flutter; Georgian accuracy on street names with the constrained grammar.
- Mapillary coverage of skeleton junctions (print a coverage report at pack build).

## 16. Decisions (2026-11-14)

Taken where the sections above were silent or where the code base forced a choice. They bind like the
rest of the spec. Numbers named here are in §13.

### 16.1 Units, ids and time

1. **A street card is a NamedStreet.** The app joins same-name pack parts within 500 m into one street
   (`NamedStreet` in pindoro_core). One P/N/E card per NamedStreet, keyed by its longest part's id; a
   card resolves through `streetsByPartId`, so it survives a pack that reshuffles parts. Progress
   denominators count NamedStreets with length ≥ `coreMinLengthM`, computed from the pack (the
   boards' "3 282" is illustrative).
2. **Stable route-item ids** come from OSM node ids (§3). The pipeline stores them alongside the
   pack-local ids.
3. **Today** is the device's local calendar day (midnight to midnight). It decides intros counted
   today, the streak, the "on a day after `intro_at`" rule for Known, and due-today: a card is due
   today when `due_at` falls before the next local midnight. FSRS arithmetic still uses whole 24 h
   periods (§4).
4. **`card_state.state`**: no row = unseen; `learning` = intro shown, retrieval 1 pending; `review`;
   `relearning` = rated Again in the current session, in-session relearn pending; `suspended` = leech.

### 16.2 Sessions

5. **Intro and retrievals.** The intro creates the card row (`intro_at`, state `learning`) and is not
   a review, so it writes no `review_log` row. Retrieval 1 is the card's first FSRS review (S0/D0);
   retrieval 2 is a same-day review. After Again on retrieval 1 the relearn comes 5–10 items later and
   retrieval 2 still closes the session.
6. **Interleaving with few items.** Retrieval 1 comes after `retrieval1GapMin`–`retrieval1GapMax`
   other items when that many exist; otherwise after all remaining items of its block, and never with
   fewer than `retrieval1GapFloor` items in between unless the session has none left.
7. **Abandoned sessions.** There is no saved plan: the next session is planned from the database.
   Cards left in `learning` get retrieval 1 first and still count towards today's new streets.
   Leaving never asks for confirmation.
8. **Several sessions a day.** `nNew = newPerDay[minutes] − introducedToday` and
   `budget = minutes × 60 − spentTodayS`. When both are used up, Today shows `done`. `Planner.plan`
   takes `introducedToday`, `spentTodayS`, `tReviewS` and `tNewS` as inputs.
9. **Time spent** comes from `review_log`: within a session, the gaps between consecutive answers,
   each capped at `answerGapCapS`. The session timer is an estimate and never ends a session.
   `tReviewS` / `tNewS` become the log medians once there are `timeEstimateMinSamples` samples (M3).
10. **`review_log.format`**: `placement`, `pretest`, `retrieval1`, `retrieval2`, `review`, `relearn`,
    `explore`; later `name`, `name_check`, `extent`, `family_sweep`, `crossings`, `bearing`, `junction`,
    `gateway`, `bridge`, `connection`, `landmark`, `scene`, `recital`, `drive`. `pretest`, `crossings`
    and `bearing` never change a schedule; the family sweep grades the children's P cards.

### 16.3 Grading

11. **Display tier** (Perfect / Great / Close / Miss) comes from pindoro_core
    `TierThresholds.forStreet(roadClass, Difficulty.medium)`: Perfect ≤ half-width + 20 m, Great ≤ 100 m,
    Close ≤ 300 m, else Miss. The rating comes from §5.1. A Mix-up shows the Miss tier.
12. **Response time** runs from the plate appearing to the Confirm tap.
13. **"≥ 2 prior successes"** counts P log rows with rating ≥ 2, placement and Explore included.
14. **Snap set**: every street part in the pack, mapped to its NamedStreet (bbox prefilter, then a
    scan; add a spatial index only if it gets slow).
15. **Confusables**: "same base name" means the same normalised `name_ka` (the 377 repeated names).
    Until the family table exists (M2) the set is same-name streets plus logged confusions.
16. **Explore answers** update a card only when it is due or near due (due within `nearDueFraction`
    of its interval, the implicit-evidence window); otherwise they are logged only. A first-sight
    Good/Easy creates the card like placement; a failure on an unseen street is logged only.

### 16.4 Progress

17. **Known for `prior_known` cards**: placement and migrated cards are Known whenever R ≥ 0.80;
    `prior_known` stands in for the "success on a later day" clause.
18. **Recall rate** uses only `format = review` rows from the last 30 days; a pass is rating ≥ 2.
19. **Whole-city date** = today + unseen core streets ÷ `newPerDay[minutes]`.
20. **City memory history** (the 10-week chart, "since yesterday") is computed by replaying
    `review_log` to the needed moments. No snapshot table.

### 16.5 Data and pack

21. **Families** are parsed from `name_ka` (`<parent> <Roman numeral> <შესახვევი | ჩიხი | გასასვლელი>`),
    kinds `lane`, `dead_end`, `passage`. A child can be a parent; the sibling cap applies per direct
    parent. Orphan: child centroid > `familyOrphanM` from the parent's geometry.
22. **Chunks** are `neighbourhood`-kind areas; their raion is `district.parent_id`; "borders" means
    `chunk_neighbour` (boundaries within `chunkNeighbourM`).
23. **Learning settings** are typed columns on the existing `user_settings` table. The plate script
    (`streetNames`) and the reminder settings already exist there and are reused.
24. **Pack formats**: learning needs pack format 4 or later; the app keeps opening format 3 packs for
    Explore until the background refresh replaces them.

### 16.6 Maps

25. **Labels** appear only on the intro and on reveals, never on a question map (board `pin` is
    blank), never for the target street, and only for Known streets: at most `knownLabelMax` of the
    nearest, drawn as `MapChip` images at street midpoints because the map style has no glyphs.

### 16.7 Routes (M5, M6)

26. **Routing** runs in Dart in the app (pindoro_core `RoadGraph`, made directed and edge-expanded
    with restrictions) and in a TypeScript twin in the pipeline for the origin–destination sampling;
    `shared/fixtures/directed_route_vectors.json` proves them equal.
27. **Route cost** is metres. A U-turn adds `uTurnPenaltyM` (report 2's 30 s at about 30 km/h) and is
    forbidden on divided roads.
28. **The graph** includes unnamed ways and `*_link` roads as connector edges (not streets), so legal
    routes don't detour around missing ramps.
29. **Bridges** come from OSM `bridge=yes` ways over the city's river, grouped by name, in a pack
    `bridge` table.
30. **Route-book runs** (`R:{runId}`) are generated on the phone from due J/G/B items and stored in a
    local `run` table.
31. **The Vosk model** is served from our own server next to the packs.

### 16.8 Motivation (M3)

32. **Badges**: keep firstPin, bullseye, onFire, nightOwl and explorer; redefine navigator as
    "a district Mastered" (§8 Mastered); add neighbourhood Mastered, 100-day maintenance, zero leeches
    and City memory milestones every `cityMemoryMilestone` streets; retire pitCrew and roadTrip.
    Earned badges stay earned.
33. **Road-trip drawing** (`RouteView`, the draw layer, `RouteDraft`) survives the removal of lessons
    in M3 because the recital's Draw mode (M6) reuses it.

### 16.9 Tuning (M8)

34. **FSRS weight overrides** are pasted or imported as JSON on a debug screen; there is no server
    endpoint.

### 16.10 Parked (in `docs/TODO.md`)

Personal name aliases for fuzzy matching, CSV import of personal landmarks, the friends cooperative
board, and per-type FSRS parameter presets.
