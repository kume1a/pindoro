# Pindoro v3 learning system: spec

Source of truth for the v3 rebuild ("Learn the whole city"). It condenses two research reports
(`docs/research/01-learning-every-street.md`, `docs/research/02-routes-landmarks-imagery.md`) into
decisions and numbers. Screens: canvas "Pindoro screens: MVP and releases", page "v3 · Learn the whole
city" (`docs/design/v3-screens.md` lists every board). Every number marked **(tunable)** lives in one
constants file and is a starting value to be checked against the review log.

Goal: the player can see any street name and place it on a blank map,
drive from any A to any B without GPS, and recite the route by heart. First city: Tbilisi (3,282 core
streets ≥ 150 m; 4,465 in total).

---

## 1. Architecture

- All learning logic lives in a pure Dart package, `packages/pindoro_learning` (no Flutter, no I/O,
  no `DateTime.now()`: the clock is injected). It depends on `pindoro_core` for geometry and pack models.
- The app (`apps/mobile`) owns persistence (Drift/SQLite), UI and platform services (TTS, location,
  speech). It calls `pindoro_learning` with plain data and stores what it returns.
- The pack pipeline (server side, at build time) computes everything graph-heavy once: families, chunks,
  directed edges, turn restrictions, junction items, landmark salience.
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

Added by later milestones: `learn_city` (per city: placement done, home and work, M2),
`card_state.note TEXT` (leech mnemonic, M4), `turn_override` (local "report this turn" fixes, M5, and hidden places, §16.18 item 94),
`run` (route-book runs, M6). See §16.

`source` in the log: `session`, `placement`, `explore`, `recital`, `drive`. Never delete log rows;
the optimiser needs them. Street ids are already stable across pack versions: the pipeline matches
them by name + way overlap (`identity.json`) and never revives a retired id. A P/N/E card is keyed by
its NamedStreet (§16), and cards whose street is no longer in the pack are skipped, not deleted.

## 3. Items and cards

Item id scheme: `P:{streetId}`, `N:{streetId}`, `E:{streetId}`, `J:{junctionId}:{approachEdgeId}`,
`G:{chunkId}:{gatewayJunctionId}:{out|in}`, `B:{bridgeId}:{bank}:{approachEdgeId}`, `C:{streetId}`,
`L:{landmarkId}:{1|2|3}`, `R:{runId}`.
Every id inside an item id must survive pack rebuilds (§16): `{streetId}` is the NamedStreet's longest
part id, a junction is `n<OSM node id>`, an approach or exit edge is the OSM node id of the neighbouring
junction along it (so `J:n123:n456`), and bridge and landmark ids come from OSM ids.
The pack's own `junction.id` is pack-local and never goes into an item id.

| Card            | Cue → answer                                                               | Who gets it                                      | Unlocks when                                                                   |
| --------------- | -------------------------------------------------------------------------- | ------------------------------------------------ | ------------------------------------------------------------------------------ |
| P pin           | name → place on the blank map                                              | every street in scope                            | introduced                                                                     |
| N name it       | painted street → its name among 6                                          | tiers A and B + every family parent (~800)       | P card past its retrieval 2, or known before                                   |
| E extent        | name → both ends                                                           | streets > 1.2 km                                 | P stability ≥ 7 d                                                              |
| B bridge access | street + bank → bridge and the turns onto it                               | ~48 (12 bridges × 2 banks × ~2 approaches)       | tier A streets introduced                                                      |
| J junction      | street + heading + target + landmark → exit (+ street turned onto)         | ~450 skeleton decisions, then district junctions | skeleton: month 1; others: district grid ≥ 80 % Solid                          |
| G gateway       | chunk + direction → exit junction + street                                 | ~6 per chunk out (~400), in = phase 2            | ≥ 70 % of the chunk's parent streets Known                                     |
| C connection    | street → its end streets / "which street joins A and B"                    | grid + parents (~400)                            | the street and both ends Known                                                 |
| L landmark      | L1 landmark → pin · L2 landmark → junction · L3 junction + turn → landmark | ~300 + personal                                  | personal: immediately; OSM: when its street is Known                           |
| R recital       | A → B by heart (speak, type, draw)                                         | route-book runs + weekly random pairs            | runs: all their J/G/B items Known; random pairs: weekly from the gateway phase |

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
| Desired retention | 0.90 for every card **(tunable)**                                                                                                                    |
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

- **N name it**: every N review is a 6-name choice that includes confusables: right = Good, wrong = Again
  (§16.13 item 55).
- **E extent**: each end counts if within `max(150 m, 10 % of length)`. Both = Good, one = Hard, none = Again.
- **J / B decisions**: exit correct and (if typed) street correct = Good; exit correct, street wrong
  or missing when asked = Hard; wrong exit = Again (re-asked this session; show where the chosen exit leads
  and the sibling junction it is confused with).
- **G gateway**: pin graded like P against the gateway junction (radius 60 m), plus street name. Both = Good,
  one = Hard, neither = Again.
- **C connection**: typed recall, fuzzy match (normalised Levenshtein ≤ 0.25 against Georgian, English,
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
A's gateway + skeleton path (bridge if banks differ) + B's gateway. Phase-2 route items (gateways in)
are introduced only after the due count has stayed under the daily budget for 14 days in a row.

### 6.6 Junction item selection (pipeline)

Sample 20,000 random origin–destination pairs weighted by street length; compute shortest legal routes on the
edge-expanded graph; count each `(junction, approach, exit)` decision; greedily select until 90 % of decision
instances are covered **(tunable)**; `rank` = coverage order. Attach the top landmark within 60 m, preferring
the approach-side corner before the turn.

## 7. Session planner

```
budget   = minutesPerDay * 60                      // 15 | 20 | 30 | 45 | 60
nBase    = {15: 7, 20: 10, 30: 14, 45: 21, 60: 28}[minutesPerDay]  // (tunable)
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
- "Learn 10 more" after a session adds `learnMoreCount` new streets; it is the only way past `nBase`.
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
`place=square`, named `junction=roundabout` (§16.18 item 96) 0.9 · `amenity=fuel` 0.9 · `amenity=place_of_worship` 0.8 · `shop=mall`,
`supermarket`, `department_store` 0.8 · `amenity=bus_station`, `public_transport=station` 0.8 · `amenity=hospital|university` 0.7 ·
`historic=monument`, `historic=memorial` seen from a car (§16.18 item 93), `tourism=attraction`, `man_made=tower` 0.7 · `leisure=stadium|park` 0.6 ·
`amenity=fast_food` with a brand of fewer than 25 branches in the city 0.4 · `highway=traffic_signals` 0.3.
No pharmacies or banks (§16.18 item 96).

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

Dropped (2026-11-16, §16.16): no street photos, no photo pack. The only street-level imagery inside
Pindoro would have come from Mapillary, which covers little of Tbilisi. Google Street View stays out of
the app: no API calls, no caching, no imagery inside Pindoro (a Google Maps deep link is fine, as the
drive's "Lost? Show the way" does).

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

| Name                                                         | Value                                   |
| ------------------------------------------------------------ | --------------------------------------- |
| `fsrsWeights`                                                | §4 list                                 |
| `retentionDefault` / `retentionTierCRelief`                  | 0.90 / 0.85                             |
| `maxIntervalDays`                                            | 365                                     |
| `fuzzFraction`, `fuzzMinDays`                                | 0.05, 3                                 |
| `relearnGapMin`, `relearnGapMax`                             | 5, 10 items                             |
| `leechLapses`                                                | 6                                       |
| `pinGoodMaxM`, `snapSearchM`                                 | 100, 150                                |
| `rtHardMs`, `rtEasyMs`, `easyMinSuccesses`                   | 20000, 6000, 2                          |
| `extentEndMinM`, `extentEndFraction`                         | 150, 0.10                               |
| `extentMinLengthM`                                           | 1200                                    |
| `unlockNameReps`, `unlockExtentDays`                         | 2, 7 days                               |
| `childParentMinDays`, `maxSiblingsPerDay`                    | 3, 4                                    |
| `knownMinR`, `solidDays`, `masteredDays`, `masteredSideDays` | 0.80, 21, 90, 21                        |
| `newPerDay`                                                  | {15: 7, 20: 10, 30: 14, 45: 21, 60: 28} |
| `tReviewS`, `tNewS`                                          | 12, 45                                  |
| `backlogCapFactor`                                           | 1.5                                     |
| `tierBShare`                                                 | 0.60                                    |
| `routeNewPerDayMax`, `routePauseFactor`                      | 10, 1.2                                 |
| `fuzzyNameMax`                                               | 0.25                                    |
| `stretchPerfect`, `stretchGreat`, `stretchClose`             | 1.03, 1.25, 1.60                        |
| `connectorMaxM`, `connectorMax`                              | 150, 2                                  |
| `gatewayUnlockKnown`, `districtJunctionUnlockSolid`          | 0.70, 0.80                              |
| `phase2ChunkSolid`                                           | 0.80                                    |
| `bearingGreatDeg`, `bearingCloseDeg`                         | 20, 45                                  |
| `junctionCoverage`, `odSamples`                              | 0.90, 20000                             |
| `landmarkRadiusM`                                            | 60                                      |
| `hesitationKmh`, `hesitationS`                               | 5, 10                                   |

Added with §16 (also in `constants.dart`; distances shared with the display tiers are referenced from
pindoro_core `ScoringConfig`, not copied):

| Name                                                                 | Value                               |
| -------------------------------------------------------------------- | ----------------------------------- |
| `coreMinLengthM`                                                     | 150                                 |
| `groupSize`, `reviewsPerBlock`                                       | 3, 5                                |
| `retrieval1GapMin`, `retrieval1GapMax`, `retrieval1GapFloor`         | 3, 6, 2 items                       |
| `learnMoreCount`                                                     | 10                                  |
| `placementSamplePerDistrict`, `placementPassMin`                     | 5, 4                                |
| `placementPinS` (time estimate per placement pin)                    | 4 s                                 |
| `nightOwlBefore` (Night owl badge: an answer before this local hour) | 4                                   |
| `familySweepMinChildren`, `familySweepWindowDays`                    | 3, 2                                |
| `crossingsPerDay`, `bearingsPerSessionMin`, `bearingsPerSessionMax`  | 1, 1, 3                             |
| `familySweepMax`, `crossingsMax`, `crossingsTries`                   | 6, 5, 8                             |
| `bearingUnlockGridSolid`                                             | 0.50                                |
| `nameCheckOptions`                                                   | 6                                   |
| `familyOrphanM`, `familyNearM`                                       | 1500, 500                           |
| `chunkNeighbourM`                                                    | 50                                  |
| `nearDueFraction`                                                    | 0.5 (implicit evidence and Explore) |
| `tierCReliefFactor`                                                  | 1.2                                 |
| `cityMemoryMilestone`, `maintenanceBadgeDays`                        | 500, 100                            |
| `chartDailyDays`, `chartWeeks`                                       | 14, 10                              |
| `uTurnPenaltyM` (pindoro_core `RoutingConfig`, referenced)           | 250                                 |
| `turnStraightDeg`, `turnUTurnDeg` (a J card's exit directions)       | 30, 150                             |
| `phase2StableDays`                                                   | 14                                  |
| `landmarkStructuralM`, `landmarkUniquenessM`                         | 40, 300                             |
| `recitalLandmarkBonus`, `recitalLandmarkBonusCap`                    | 0.1, 0.3                            |
| `answerGapCapS`                                                      | 60                                  |
| `timeEstimateMinSamples`                                             | 50                                  |
| `migrationDueMinDays`, `migrationDueMaxDays`                         | 1, 7                                |
| `landmarkNewPerDay`, `relearnMaxPerSession` (§16.18)                 | 3, 2                                |
| `tRecitalS`, `recitalNewPerDay`                                      | 180 s, 1                            |
| `runLeadM`, `runMinItems`                                            | 800, 2                              |
| `randomRunEveryDays`, `randomRunTries`                               | 7, 50                               |
| `randomRunMinM`, `randomRunMaxM`                                     | 1500, 5000                          |
| `recitalTurnMismatchM`, `recitalNameWordsMax`, `recitalNameTieSlack` | 200, 5, 0.05                        |
| `driveSampleM`, `driveSnapM`, `driveHeadingM` (per 90°)              | 20, 35, 20                          |
| `driveTurnBackM`, `driveWrongWayM`, `driveArriveM`                   | 40, 15, 200                         |
| `hesitationJunctionM`                                                | 30                                  |
| `calibrationBins`, `calibrationTolerance`, `calibrationMinReviews`   | 10, 0.05, 20                        |
| `fitMinReviews`                                                      | 1000                                |
| `tierCReliefDays`, `tierCReliefReplayDays`                           | 7, 28                               |

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

Revisited in M8 (2026-11-16):

- Real Tbilisi junction count and decision-coverage curve (recompute §3 estimates from the pack):
  answered in `docs/research/junction-coverage.md` (6 424 items for 90 %, §16.14).
- How often "Nth Lane / Dead End of X" lies near X: answered in `docs/research/family-check.md`.
  98.5 % of numbered lanes find their parent; 97.9 % of those lie within 500 m of it and 98.7 % within
  1.5 km (20 orphans).
- OSM turn-restriction completeness in Tbilisi: open. The pack holds 879 restrictions; "Report this
  turn" (§16.15 item 80) fixes a missing or wrong one on the phone, and the reports themselves will
  show how incomplete the data is.
- Seconds per review and per new street on a phone: measured from `review_log` (`tReview`, `tNew`
  re-estimated from the log's medians once there are `timeEstimateMinSamples`, §16.12); the
  numbers come with real use.
- Vosk on iOS via Flutter; Georgian accuracy on street names with the constrained grammar: open,
  speech is parked (§16.15 item 73).
- Mapillary coverage of skeleton junctions: answered by looking, too thin for Tbilisi (most of the
  city has none, the suburbs about a tenth), so the street photos were dropped (§16.16).
- §13's numbers stay as they are until calibration on real reviews (§12, §16.17) says otherwise.

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
6. **Interleaving.** Each retrieval 1 is placed on its own, after a seeded `retrieval1GapMin`–
   `retrieval1GapMax` other items: §7's literal pattern (3 intros, 5 reviews, the 3 retrieval 1s)
   would put 7 items between every intro and its retrieval 1. Near the end, the closing retrieval 2s
   of streets already retrieved count as those items; a retrieval 1 comes earlier only when every
   step left waits on one (then with at least `retrieval1GapFloor` items in between when the
   session has them). A relearn goes 5–10 items after its Again, at the end when fewer are left,
   and always before the street's own retrieval 2.
7. **Abandoned sessions.** There is no saved plan: the next session is planned from the database.
   Cards left in `learning` get retrieval 1 first and still count towards today's new streets.
   Leaving never asks for confirmation.
8. **Several sessions a day.** `nNew = newPerDay[minutes] − introducedToday` and
   `budget = minutes × 60 − spentTodayS`. When both are used up, Today shows `done`, even with
   reviews still due. A backlog takes the most at-risk reviews that fit in `budget × backlogCapFactor`,
   skipping one that doesn't fit (a recital), and at least one while any budget is left. So a plan
   is empty only once the day counts. `Planner.plan` takes `introducedToday`, `spentTodayS`,
   `tReviewS` and `tNewS` as inputs.
9. **Time spent** comes from `review_log`: within a session, the gaps between consecutive answers,
   each capped at `answerGapCapS`. The session timer is an estimate and never ends a session.
   `tReviewS` / `tNewS` become the log medians once there are `timeEstimateMinSamples` samples (M3).
10. **`review_log.format`**: `placement`, `pretest`, `retrieval1`, `retrieval2`, `review`, `relearn`,
    `explore`, `exploreLog` (an Explore answer that schedules nothing, §16.16), `name`, `nameCheck`,
    `extent`, `familySweep`, `crossings`, `bearing` (M4), `junction`, `gateway`, `bridge`,
    `connection`, `landmark` (M5); later `recital`, `drive`. `pretest`, `crossings` and `bearing` never
    change a schedule; the family sweep grades the children's P cards.

### 16.3 Grading

11. **Display tier** (Perfect / Great / Close / Miss) comes from pindoro_core
    `TierThresholds.forStreet(roadClass, Difficulty.medium)`: Perfect ≤ half-width + 20 m, Great ≤ 100 m,
    Close ≤ 300 m, else Miss. The rating comes from §5.1. A Mix-up shows the Miss tier.
12. **Response time** runs from the plate appearing to the Confirm tap.
13. **"≥ 2 prior successes"** counts P log rows with rating ≥ 2, placement and Explore included.
14. **Snap set**: every street part in the pack, mapped to its NamedStreet (bbox prefilter, then a
    scan; add a spatial index only if it gets slow).
15. **Confusables**: "same base name" means the same normalised `name_ka` (the 377 repeated names).
    The set is same-name streets, logged confusions and the street's family: its parent and
    siblings, and its own children (an orphan has no family).
16. **Explore answers** update a card only when it is due or near due (due within `nearDueFraction`
    of its interval, the implicit-evidence window); otherwise they are logged only. A first-sight
    Good/Easy creates the card like placement; a failure on an unseen street is logged only.

### 16.4 Progress

17. **Known for `prior_known` cards**: placement and migrated cards are Known whenever R ≥ 0.80;
    `prior_known` stands in for the "success on a later day" clause.
18. **Recall rate** uses only `format = review` rows from the last 30 days; a pass is rating ≥ 2.
19. **Whole-city date** = today + unseen core streets ÷ `newPerDay[minutes]`.
20. **City memory history** (the chart, "since yesterday") is computed by replaying
    `review_log` to the needed moments. No snapshot table. The chart's window (v3.1, canvas
    V31-99): for the first `chartDailyDays` (14) calendar days a 14-day frame ending today with a
    point at the end of each day played; then a point a week from the first answer; from
    `chartWeeks` (10) weeks on, the last 10 weeks. Its scale never tops out under 100.

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

25. **Labels** (changed 2026-11-17, §16.18): street names appear on intros and reveals, never on a
    street question, never for the target street. See §16.18 for which streets and the place names.
    The basemap draws them as map text (FiraGO glyphs served by Martin).

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
33. **Road-trip drawing** survives the removal of lessons in M3 for the recital's Draw mode (M6):
    `RouteDraft`, the draw layer, the route layers and `MapProjection`. The trip screen
    (`RouteView`), trip picking and route scoring go; M6 builds its Draw screen on the drawing
    parts and grades with the recital grader.

### 16.9 Tuning (M8)

34. **FSRS weight overrides** are pasted or imported as JSON on a debug screen; there is no server
    endpoint.

### 16.10 Parked (in `docs/TODO.md`)

Personal name aliases for fuzzy matching, CSV import of personal landmarks, the friends cooperative
board, and per-type FSRS parameter presets.

### 16.11 Curriculum (M2)

35. **The skeleton is taught with the grid.** Tier A streets that placement leaves unseen are taught
    before tier B, in the same order (ring, bank, length). The 60/40 split of §6.3 holds while any
    core tier A or B street is unseen.
36. **Banks alternate** within a ring, starting with the bank of the ring's longest street.
37. **Chunk order**: home, then work, then the chunk holding the centre; then a chunk already
    started; then the chunk bordering the most finished chunks (ties: its centre nearer the city
    centre). A chunk is finished when none of its core tier C streets is unseen. The order is set
    once per plan.
38. **Within a chunk**, children are grouped by parent and ordered by number. A street that is both
    a child and a parent (a lane with its own dead ends) is taught as a child.
39. **Groups**: new slots fill in groups of `groupSize`, each group from one lane (skeleton and grid,
    or chunks). A lane with nothing left gives its slots to the other.
40. **Placement samples** a street's raion through its chunk (`district.parent_id`), with the plan
    seed.
41. **Streets without a chunk** (packs before format 4, and the bundled Vake pack's streets whose
    chunk lies outside Vake) form one chunk, taught last. Without tiers every street is tier C.
42. **Carried-over streets** (players of the old game): every street with a Great or Perfect and no
    card gets a P card rated Good on first sight, `prior_known = 1`, due on a seeded day
    `migrationDueMinDays`–`migrationDueMaxDays` out. No intro and no `review_log` row. It runs
    whenever a pack opens, so streets known in Explore before M3 still come over.
43. **Guess first** comes before the intro of a child whose parent is Known. The plate names what
    the player knows ("You know 26 May Street and 4 of its side streets"); the map stays blank, as
    on every question map (§16.6), although the board labels the family there. The guess is
    logged as `pretest` and saves no confused pair.
44. **Placement runs** (§6.2) skip streets that already have a P card. A pass is Good or Easy: it
    creates the card (`prior_known = 1`, format and source `placement`); Hard and Again are logged
    with no card; "I don't know this one" logs nothing. A raion's sweep follows when its sample's
    passes reach `placementPassMin` / `placementSamplePerDistrict` of the sample (a sample shrunk
    by carded streets keeps the ratio), and is asked right after the sample. Placement has no
    relearns.
45. **Placement state** is per city, in table `learn_city` with the home and work neighbourhoods:
    `placed_at` is set when a placement ends or the player starts from zero; Today shows
    `firstRun` until then. Leaving a placement keeps its answers, so starting again asks only the
    streets still unseen.
46. **Progress**: a district's number is City memory over its core streets (through their
    chunks); a neighbourhood is Mastered when all its core streets are, `now` is the first chunk of
    the teaching order, then begun ones, then the rest in teaching order ("Starts after" names the
    chunk before it). Districts sort by their share remembered. The replay of §16.20 skips
    `pretest` rows and placement rows that made no card.

### 16.12 Replacing the old game (M3)

47. **A day counts** for the streak once the player answered that day (a session, placement or
    Explore) and then either nothing is due before midnight or the day's minutes are spent. It is
    checked after every learning answer and written to `goal_day` once; a day never un-counts.
48. **The reminder** fires at 19:00 on a day that hasn't counted, and only when a review is due by
    the end of that day.
49. **Badge rules**: Keeper is 100 counted days, in a row or not. Clear road needs a street that
    once became a leech (`leechLapses` lapses) and no suspended card now. City memory milestones
    use the open city's City memory (Σ R) and are stored as `cityMemory<n>`. Bullseye counts
    Explore Perfects and session or placement pins Perfect at medium. Explorer keeps its rule (5
    raions with a street known), now from the cards. Pit crew and Road trip are retired: earned
    ones show with a Retired pill, unearned ones never show.
50. **Time estimates**: once the log holds `timeEstimateMinSamples` reviews, `tReviewS` is the median
    gap before a review answer in its session and `tNewS` keeps its default ratio to it.
51. **The old tables** go in schema 17 (`review_item`, `review_cleared`, `course`,
    `lesson_result`, `lesson_answer`, `saved_lesson`, and the XP, Pit stop, daily goal and turn
    list columns). Streets the lessons knew are kept in `legacy_known` first, so carry-over still
    finds them for cities not opened yet.
52. **Learn 10 more** plans `learnMoreCount` new streets past the daily number and the minutes. Today
    offers it when done; Session done offers it when nothing is left due.
53. **Catching up** shows the days the due reviews take at the day's minutes (`due × tReviewS ÷
    budget`, rounded up) and City memory's change over the week.

### 16.13 More street cards and drills (M4)

54. **Name and ends cards open**, a name card once the street's P card has had `unlockNameReps`
    answers (its retrieval 1 and 2) or was known before, an ends card once it reaches
    `unlockExtentDays` of stability: a name card for tiers A and B and every family parent, an ends
    card past `extentMinLengthM`. An open card without a row starts as a first review (no intro)
    after the due reviews, the most stable streets first, at most as many a day as the day's new
    streets (`newPerDay[minutes]`), in the minutes left after the new streets; a backlog and Learn
    10 more start none.
55. **The name check** is every name review: `nameCheckOptions` names, the street, its confusables
    nearest first, then the nearest streets, one per name. Right is Good; wrong is Again and saves
    the mixed-up pair. (Until 2026-11-17 nine in ten were self-graded Forgot / Knew it, logged as
    `name`.)
56. **A street's ends** are its two line ends farthest apart; the pins count either way round. Both
    ends show Great, one Close, none Miss.
57. **Name and ends answers** log as `nameCheck` and `extent` whatever their step (first
    review, review, relearn). Again relearns them in the session like a pin. Recall rate stays on P
    reviews; City memory counts only P cards.
58. **Mastered** needs each name and ends card that applies at `masteredSideDays`; one not started
    yet keeps the street from Mastered.
59. **Leeches**: a lapse that brings `lapses` to a multiple of `leechLapses` suspends the card, so
    lapses stay a plain count (Clear road reads it). A card suspended before today comes back first
    among the new streets (a new slot; none in a backlog): its intro says "Back for a closer look",
    traces its top confusion (most counts, then latest) in cobalt with its name, and takes an
    optional note (`card_state.note`). The intro makes it relearning and due at once, so the
    session's retrievals relearn it on its kept memory. The reveal of the suspending answer says
    "Back tomorrow for a closer look".
60. **The family sweep** takes the parent with the most children due within
    `familySweepWindowDays` (at least `familySweepMinChildren`), up to `familySweepMax` of them,
    earliest due first; they leave the review list. Each label on its own lane is Good, elsewhere
    Again with a mixed-up pair (the child, the lane it went on). Labels are dragged, or tapped and
    then a lane tapped.
61. **The crossings drill** takes a Solid street of tier A or B or a family parent, trying up to
    `crossingsTries` in seeded order. Crossings are ordered along the line between the street's
    ends, from a seeded end; the first names where the drive starts, then up to `crossingsMax`
    Known crossings are asked, at least two. A typed name matches by `fuzzyNameMax` against the
    Georgian name, its Latin transliteration and the English name, each without its kind of street
    ("street", "ქუჩა", …); a wrong name that matches another street saves the pair. A suggestion
    row offers the street whose name the typing starts. Each answer is logged on the crossed
    street's P item and moves no card; one drill a day.
62. **Bearings** point from the city centre (`centre` in `city.yaml`) to the midpoint of a Solid core
    street at least 1 km from it, in raions whose core tier B streets are `bearingUnlockGridSolid`
    Solid; `bearingsPerSessionMin`–`bearingsPerSessionMax` a session, seeded. Logged with Great as
    Good, Close Hard, Miss Again; no card moves. Landmarks (M5) can replace the centre later.
63. **Drills** sit half-way through the session (the sweep, the crossings, then the bearings); a
    backlog keeps only the sweep. The sweep and the crossings show Great when all are right, Close
    for half or more, else Miss. Every drill answer counts `tReviewS` in the estimates.

### 16.14 Route items (M5)

64. **The directed graph** (pack format 5) is a column, not a table: `road_edge.oneway` (1 along the
    way, -1 against it, 0 both; motorways one-way unless `oneway=no`). Connector edges (`street_id`
    NULL) are drivable ways without a name and every `*_link`. `turn_restriction` keeps node-via
    restrictions whose from and to ways end at the via node; way-via and ambiguous ones are left
    out.
65. **A decision** is a junction on a route with another legal way on, U-turns aside. Tbilisi's
    20 000 routes drive about 74 each, and 6 424 items cover 90 % (`docs/research/junction-coverage.md`).
    Layers: `bridge` when the exit leads onto a bridge (its own edge, or one reached before the next
    junction with a choice); `gateway_out` from a tier C street onto tier A or B (the gateway's
    chunk is the tier C street's), `gateway_in` the other way; `skeleton` between tier A streets;
    else `district`. `dest_chunk_id`, where the routes through an item mostly head, is the J card's
    "heading to".
66. **J item ids name the exit**: `J:n<junction>:n<approach>:n<exit>`. §2.1's items are
    (junction, approach, exit) triples and two exits from one approach are two questions, so §3's
    `J:{junctionId}:{approachEdgeId}` gains the exit. G ids name the junction node, B ids the node
    where the turn towards the bridge is made, with the approach street's bank.
67. **Landmarks on turns**: each item takes the landmark within `landmarkRadiusM` with the highest
    salience including structural (1.0 within `landmarkStructuralM` before the turn, 0.6 within it
    after, else 0.3), and its side driving in; both live on `junction_item`. Candidates need a name
    or brand; traffic signals are left out. Bridges are named bridge ways crossing the river line,
    with same-name bridge ways within 200 m.
68. **A J card** is asked only where its junction offers two or more legal ways on with distinct
    directions (within `turnStraightDeg` straight on, past `turnUTurnDeg` a U-turn, else left or
    right), so its buttons are exactly the legal exits. "Then you're on" is optional; left empty it
    is Hard only once that street is Known (§5.2 "missing when asked").
69. **Unlocks** (§3): bridges once every core tier A street is introduced; skeleton turns when the
    approach and exit streets are Known; district turns also need the raion's core tier B streets
    `districtJunctionUnlockSolid` Solid; gateways `gatewayUnlockKnown` of their chunk's main streets
    (core, not lanes) Known and the main street Known; gateways in also phase 2, taken as a streak
    of `phase2StableDays` (a counted day has nothing due left); connections when the street and both
    end streets are Known; OSM landmarks when their turn's approach street is Known; personal
    landmarks at once.
70. **New route items** start like name cards (§16.13 item 54): after the reviews and side cards,
    at most `routeNewPerDayMax` a day, none while the due reviews take more than `routePauseFactor`
    of the minutes, none in Learn 10 more; in layer order (bridges, skeleton turns, gateways,
    district turns, connections, landmarks), then coverage rank. Today's Turns tile counts the
    plan's route items. New OSM places are taught first instead (§16.18 item 87).
71. **The other route cards**: a gateway asks "Way out of {chunk}" (or into), graded by a pin within
    `landmarkRadiusM` of the junction and the main street typed (optional). A bridge question offers
    the four nearest bridges as numbered tips. A connection asks "{street} runs from {one end}
    to…", the ends being the first and last streets crossing it, for core tier B streets and family
    parents. Landmarks get L1 (pin, Good within `pinGoodMaxM`), L2 (its junction among four) and L3
    (the landmark among four names); J, G, B, C and L answers relearn after Again like pins.
72. **Personal landmarks** (`landmark_personal`, schema 19) are added from Learning settings → Your
    landmarks: a tap on the map or "Here" snaps to the nearest junction, then a name, a kind (fuel,
    metro, church, shop, other), the approach they are seen from and their side. They get L cards
    at once; they don't replace OSM landmarks on J cards yet.

### 16.15 Recitals and drives (M6)

73. **Speech is parked** (decided 2026-11-16): recitals are typed or drawn. The one Flutter Vosk
    plugin that claims iOS (`vosk_flutter_service`) downloads a prebuilt library from its single
    maintainer's release and couldn't be tried on a phone; Speak, the transcript chips and the
    model download wait in `docs/TODO.md`.
74. **Runs** (`run`, schema 20) keep their ends as OSM nodes: id `n<from>:n<to>`, card
    `R:n<from>:n<to>`, with the J items of the book their best route drives. A route-book run is
    made when none is open: the Known, near-due J card due first that no run drives seeds it, from
    about `runLeadM` back along its approach street to about as far on along its exit street, on the
    best legal route; kept when that route drives the seed and at least `runMinItems` J items of
    the book, all Known. A random pair comes every `randomRunEveryDays` once a gateway card exists
    (the gateway phase): two junctions on Known streets `randomRunMinM`–`randomRunMaxM` apart.
75. **R cards in the plan** start at most `recitalNewPerDay` a day, after the route items and paused
    with them; a recital takes `tRecitalS` of the minutes, due or new. FSRS schedules R like any
    card; an Again isn't asked again in the session.
76. **Typing a recital**: A's street is step 1; each step is an optional turn (Left, Straight,
    Right) and a street or landmark, typed (resolved as §5.3 step 2) or picked from the suggestion
    row. A pick is a hint: the recital is capped at Great / Good. Among names that differ only in
    their kind word (a street and its lane) the full name typed wins, and "and" (და) stays inside a
    name. Draw follows legal exits only (§16.8 item 33), so a drawn route is never "Not drivable".
77. **The path search** (§5.3 step 3): a first or last street left unsaid is A's or B's; turn words
    cost `recitalTurnMismatchM` when the path doesn't make them and a landmark said costs the
    distance beyond `landmarkRadiusM` from it, so both only choose between paths; a connector counts
    only when it touches a junction of the street left or joined and costs its length again; more
    than `connectorMax` make the recital invalid. "Not drivable" is the same search with one-ways
    and turn restrictions ignored; the first offending move is reported, one-way before restriction.
78. **Decisions** (§5.3 step 6) are junctions with another legal way on, U-turns aside; the start
    counts (no approach, no turn), and so does a chosen U-turn. A path with none scores 1 unless it
    is a Miss. The result lists the turns onto another named street.
79. **Evidence** (§4): every decision on a J item of the book is an `implicit_evidence` row (outcome
    1 or 0, source `recital` or `drive`). G and B ids name no approach, so only J items get it. A
    failed decision counts against every J item at that junction from that approach; an item met
    twice keeps its worse outcome. A failure on a near-due reviewed card is also an Again review
    (`format` `recital` or `drive`). After a recital the J cards it failed join the session as
    relearns ("Turn added to practice").
80. **Report this turn** (`turn_override`, schema 20): a "Not drivable" move can be reported, and it
    counts as legal for recitals and drives on this phone from then on: a one-way
    (`oneway:n<from>:n<to>`) or a turn (`turn:n<from>:n<via>:n<to>`; an `only_*` restriction at its
    way in is dropped). The route book keeps the pack's rules.
81. **Drives** go to today's run (the route-book run whose recital is due first), a surprise (a
    junction on Known streets `randomRunMinM`–`randomRunMaxM` from the start) or the player's own
    street (its junction nearest the start). Fixes come once a second, also while stopped and with
    the screen locked (Android foreground service, iOS background location on while-in-use
    permission). The track is matched (fixes `driveSampleM` apart, snaps within `driveSnapM`,
    `driveHeadingM` per 90° off, `driveWrongWayM` against a one-way, `driveTurnBackM` to turn back;
    a jump is bridged by the shortest legal drive; the first and last edge count when more than half
    was driven), then graded from its first junction to the destination when it ended within
    `driveArriveM` of it, else it is a Miss ("You stopped … from …"). A drive reviews no R card.
    "Lost? Show the way" ends the test unsaved and opens directions in the Google Maps app. The
    track lives in memory: a killed app loses the drive.
82. **Hesitations**: the pack has no traffic signals, so junctions stand in for them: a stop within
    `hesitationJunctionM` of a junction, or at the start or end, is not a hesitation. The review
    counts hesitations and U-turns in its sentence.

### 16.16 Street photos (M7): dropped

83. **No street photos** (decided 2026-11-16). Mapillary, the one source the app could ship, covers
    little of Tbilisi: most of the city has no imagery and the suburbs about a tenth. Google Street
    View covers it but can't be shown or stored inside the app (§10), and filling the gaps with our
    own 360° captures would mean driving every approach with a camera. So the S1–S3 cards, the
    `scene_image` photo pack, the Panoramax server and `retentionScene` are gone from the spec and
    the code. The M7 build stays on the unmerged `feat/v3-m7` branch should a source turn up.

### 16.17 Tuning (M8)

84. **Fitted weights**: `just fsrs-fit <csv>` runs py-fsrs's optimizer (Docker, CPU PyTorch) on the
    exported log's rows that moved a card (`changesSchedule`), all card types together (per-type
    presets stay parked, §16.10), with a carried-over card's first Good (no row of its own) put
    back before its first review, and prints `{"weights": […], "reviews", "cards"}`. Learning
    settings → Memory model takes it pasted (§16.9 item 34): 21 numbers, each within py-fsrs's
    own parameter bounds (its scheduler refuses anything else). They are kept in
    `user_settings.fsrs_weights` (schema 21, so the account backup carries them) and loaded at
    launch into `FsrsWeights.active`, which every `Fsrs()` uses: scheduling, recall, labels and
    City memory all run on one model for the whole run, so new weights apply from the next start.
85. **Calibration** (§12): reviews at least a day after the card's last review that moved it, with
    a predicted recall, in `calibrationBins` bins of predicted recall. Implicit evidence from
    recitals and drives stays out, since only its failures are logged. A bin is healthy when its
    share recalled (Hard or better) is within `calibrationTolerance` of its mean prediction, and
    judged only from `calibrationMinReviews` reviews. The Memory model screen shows it as bars and
    rows; it isn't hidden behind a debug flag, since the app ships as release builds.
86. **Tier C relief** (§4): a day is judged by the mean time of the days played among the
    `tierCReliefDays` before it (days without play don't count; the day itself doesn't either, so
    its state holds all day), against today's minutes a day. It turns on above
    `tierCReliefFactor` × the minutes and off below the minutes, replayed day by day over
    `tierCReliefReplayDays` from off. While on, a session answer on a tier C street's P card is
    scheduled for `retentionTierCRelief`; Explore answers and other cards keep their retention.

### 16.18 Field feedback (2026-11-17)

From the first "Start from zero" run on a phone: places asked without ever being shown, a chain
("Dunkin'", 20 branches) asked by name alone, the same unknown places asked again and again, and
blank maps after every answer.

87. **New places are taught first.** A new OSM landmark's L1 card starts with an intro, like a new
    street (§6.4): the place in yellow among the streets around it, where it is ("At A × B", or "On
    A" where only connectors meet), its kind and a Street View link; then retrieval 1 and 2 in the
    same session. At most `landmarkNewPerDay` a day, after the new streets, at `tNewS` each, paused
    like the route items and none in Learn 10 more; they count in Today's Turns, not its new
    streets. The player's own landmarks still start as a first review.
88. **A place's L2 and L3** open only once its L1 is Known; a turn, connection or OSM place needs
    at least one named street to be Known (one met only by connectors stays shut).
89. **Chains and repeated names** (a brand, or a `name_ka` shared by another landmark in the pack)
    are asked with their street, the one of the junction's streets nearest the place: "Dunkin',
    Dolidze Street".
90. **Relearns** after Again stop at `relearnMaxPerSession` per card per session; the card then
    waits for its due time (at least a day out), and the reveal says when.
91. **Maps** (replaces §16.6 item 25):
    - Names are the basemap's own map text from OpenStreetMap, never badges: street names along
      their roads, place names under their icons, as the map has room for them (changed
      2026-11-17 after the first field run).
    - Intros and reveals name every street and place, Known or not.
    - Street questions name places but no streets; a place sharing a word stem with the street's
      name is left out (a metro named after its avenue). The player's own landmarks are not in
      the map data and stay unnamed.
    - A place question names no places and only Known streets, never the street in the place's
      own name; its reveal marks the place in yellow, the dotted ink line from the pin and the
      distance, and names everything.
92. **Street View** (§10, a Google Maps link): on every street intro and pin reveal, at the
    street's point nearest the answer looking along it; on every place intro and L1 reveal, from its
    street looking at it.
93. **Only landmarks you can see from a car.** A memorial counts (as `monument`, §9) only when
    `memorial=statue|sculpture|obelisk|column|war_memorial`; plaques, busts and stones are left out.
    In Vake 38 of the 41 monuments were plaques and busts nobody can spot from the road
    (found 2026-11-17, a bust asked by name that the player could not find on Street View).
94. **"Can't find it?"** on a pack place's intro and on every reveal of its cards: after a confirm
    ("Hide {place}?"), the place is hidden on this phone (`turn_override` row
    `place:<landmark id>`, no schema change): its L1–L3 cards leave the session and the route book,
    and its turns ask "at the next junction" instead. Its review log stays. The player's own
    landmarks are deleted in Settings instead.
95. **Area places are graded against their outline.** A park, mall, university or any other place
    mapped as an area keeps its outline in the pack (`landmark.outline`, format 6). An L1 pin inside
    it is 0 m away, one outside is measured to its nearest edge; the reveal draws the outline in
    yellow with the point. Parks reach 1.4 km² in Tbilisi, so the point alone failed a right pin
    300 m from the middle.
96. **Which places are asked** (the whole city's 581 places of 2026-11-17 became 339):
    - Pharmacies and banks are not landmarks: five pharmacy chains had 70–181 branches each and
      Bank of Georgia 100; they were 35 % of the places asked, small shopfronts on every corner.
    - Fast food only for a brand with fewer than 25 branches in the city (McDonald's, KFC, Subway
      stay; Dunkin' and Tempo go).
    - A named roundabout is one place however many ways OSM splits it into (they were asked up
      to 5 times), and none when its name is a road's (a street through it, a square's address,
      "… Street") or a `place=square`'s, which is asked as itself.
97. **Never one street twice in a row.** A session never asks about the same street (or place,
    turn, recital: one item key) in two steps running while another step can go between: the
    planned session, and again each time a relearn goes in (`Planner.unstacked`). A repeat takes
    the nearest later step about something else between the two, else the nearest earlier one;
    one street's steps keep their order. It caught a new street's retrieval 1 and 2 at the end of a
    session, a relearn just before its own retrieval 2, and a street's name and ends cards side by
    side.
98. **Name it right after learning a street.** A street's name card opens once its pin card has had
    its two same-day retrievals (a street known before at once), not after 7 days of stability, and
    every name review picks among six names: a self-grade proved nothing. So the names keep pace,
    as many name and ends cards start a day as new streets, instead of 5.
