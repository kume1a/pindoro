# Pindoro, Part 2: Route, Landmark and Visual Learning for Tbilisi, plus Street-Level Imagery Options

## Recommendation

Do not add route learning by scheduling whole routes. Schedule the individual decisions at each junction as FSRS cards, and use whole routes only as tests. Route recitals and real GPS-free drives work like exams: their results flow back into the decision cards. The method has three layers. First, a small skeleton: the 12 bridges, the main corridors and their junctions. Second, a "gateway" layer: how each of the 68 neighbourhoods connects to the skeleton. Third, landmark and scene cards attached to the same decision junctions. This matches how expert navigators actually plan. London cabbies plan hierarchically and use neighbourhood boundaries. People in general use landmarks mainly where they must decide where to turn.\[1\] Getting from any A to any B then means combining two gateway decisions with one skeleton path, not learning N² routes.

For imagery, I recommend three steps:

- **Now:** use Mapillary where coverage exists. Its images are CC BY-SA and can be downloaded, cached and bundled offline if you show the Mapillary logo and a link.\[2\] Separately, capture your own imagery of decision junctions with a 360° camera. Host it on a private Panoramax instance on your home server and bundle small cropped views into the city pack.\[3\]\[4\]
- **Google Street View:** use it only as an online "look around" link that opens the Google Maps app. Its terms forbid caching, offline use, and showing Street View on the same screen as a non-Google map. That rules it out for an offline quiz built on your own basemap. The coverage itself is good: it launched in Georgia on 22 June 2026 in partnership with the Ministry of Economy and Sustainable Development and the Innovation and Technology Agency (GITA), covering about 13,000 km including Tbilisi.
- **Later:** publish your own captures to Mapillary or a public Panoramax instance once they are blurred.

## TL;DR

- **Route learning:** add junction-decision, gateway, connection, landmark and scene cards. They share the existing FSRS-6 scheduler and unlock behind the street-name curriculum. Point-to-point recitals and GPS-free drives are graded tests, not cards. Tbilisi needs about 2,000 core route and visual items, not N² routes.
- **Workload:** these items add roughly 75 hours on top of the roughly 107 hours estimated for the street names. Core mastery moves to about 24 months at 15 min/day, 18 months at 20 min/day, or 12 months at 30 min/day, plus real driving.
- **Imagery:** use Mapillary plus your own 360° captures (self-hosted Panoramax, cropped WebP bundled into the pack) for all offline quiz imagery. Use Google Street View only through deep links into the Google Maps app; the API path is online-only, cannot be cached, needs a billing account and published terms, and cannot sit beside your own map.

## Key Findings

| #   | Finding                                                                                                                                                                                                                           | Evidence strength                                                                                                                                                                                                                                                                    | Design consequence                                                                  |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------- |
| 1   | Expert navigators plan hierarchically. London taxi drivers use neighbourhood boundaries to segment routes. Wiener & Mallot's "fine-to-coarse" heuristic plans with fine detail nearby and region-level detail far away.           | Strong (several lab studies plus Griesbauer et al., _Cognition_ 2024: 44 licensed London taxi drivers planning across more than 26,000 streets at about 1.8 s per street, with London's regional structure affecting response times)                                                 | Gateways plus skeleton decomposition; recitals scored hierarchically                |
| 2   | Landmarks are mentioned most at reorientation points, where the direction changes.\[1\] Route descriptions without landmarks are rated poorly.                                                                                    | Strong (consistent across studies and reviews)                                                                                                                                                                                                                                       | Attach landmarks to junction-decision cards, not to streets in general              |
| 3   | Landmark-based turn instructions improve incidental spatial learning compared with standard turn-by-turn instructions. Habitual GPS use is associated with worse spatial memory, and the effect is dose-dependent.\[5\]\[6\]\[7\] | Moderate (Gramann et al. 2017 in a driving simulator; Wunderlich & Gramann 2018, benefit still present three weeks after a single exposure; Wunderlich & Gramann 2021, replicated walking in real-world Berlin; the GPS data are correlational, with a small longitudinal subsample) | Drive GPS-free; if you must use guidance, phrase it with landmarks                  |
| 4   | Visual long-term memory stores thousands of detailed images.\[8\]                                                                                                                                                                 | Strong for recognition; weak evidence that this becomes name recall                                                                                                                                                                                                                  | Scene cards are cheap to review; pair them with recall, not just recognition        |
| 5   | Scene and route memory depend on viewpoint. Return paths and opposite-direction views are recognised worse.\[9\]\[10\]                                                                                                            | Moderate                                                                                                                                                                                                                                                                             | One image per approach direction; test the opposite direction separately            |
| 6   | Taxi drivers learn through "runs", recited street by street, and by visualising in-street views.                                                                                                                                  | Moderate (descriptive, observational)                                                                                                                                                                                                                                                | Keep the route book, but treat runs as practice material, not the unit of knowledge |
| 7   | Google Street View terms forbid caching (except pano IDs), offline use, and Street View on the same screen as a non-Google map.                                                                                                   | Strong (primary terms and policies)                                                                                                                                                                                                                                                  | Google only through deep links                                                      |
| 8   | Mapillary images are CC BY-SA and can be downloaded and served from your own servers with logo attribution. The terms forbid use in navigation synchronised to the device's position.\[2\]                                        | Strong (primary terms)                                                                                                                                                                                                                                                               | Mapillary is fine for quizzes; no live imagery while driving                        |

## Evidence in Detail

### Route knowledge, survey knowledge and how people plan in a known city

- **The classic sequence.** The standard model of spatial learning runs landmark → route → survey knowledge (Siegel & White).\[1\] Route knowledge is a sequence of views and turns. Survey knowledge is map-like and supports shortcuts.
  - Your goal ("any A to any B, without GPS, describe routes by heart") needs survey knowledge to choose a route and route knowledge to execute and recite it.
  - The name curriculum you already have, with its blank-map pin drops, builds survey knowledge. This report adds the route and landmark layers.
- **Fine-to-coarse planning (strong).** Wiener & Mallot (2003) showed in regionalised virtual environments that route planning "takes into account region-connectivity and is not based on place-connectivity alone". They proposed a planner that uses fine detail for nearby places and coarse, region-level detail for distant ones.\[11\]
  - Follow-up work found people plan a coarse region-level route first and refine it while travelling.\[12\]
  - Implication: the unit you plan with when far away is "district or neighbourhood → bridge → district", not individual streets.
- **London cabbies (strong for hierarchy, moderate for training method).**
  - Griesbauer et al. tested drivers planning street-by-street across more than 26,000 streets. Drivers exploit neighbourhood boundaries for hierarchical planning, and changes of direction add response time.\[13\]
  - A related PNAS paper ("Expert navigators deploy rational complexity–based decision precaching for large-scale real-world planning") argues that experts concentrate planning effort on the hardest decision points, scaling its analysis to over 26,000 states.
  - Griesbauer's 2022 review describes how drivers learn: systematic map study, travelling overlapping runs, visualising places, and using subgoals.\[14\]
  - In the licensing exam, drivers must name every street and turn of a route in order.\[15\] That is exactly your "recital".
- **Do runs transfer to arbitrary routes? (moderate, indirect).** Nobody has published a controlled test that run-learning transfers to unseen point-to-point routes.
  - The mechanism the evidence supports is that overlapping runs build a network of known junctions and subgoals, and new routes are assembled from them.
  - So Pindoro should treat the decisions inside runs as the knowledge, and test transfer explicitly with unseen pairs (see the experiment section).
- **Skeleton and anchor points.** Anchor-point theory holds that a few well-known places and paths organise the rest of spatial memory. Your plan already uses the bridges and main roads as this skeleton. It fits the hierarchical evidence above, though the specific "skeleton first" order has not been tested as a training intervention.

### Landmarks in navigation

- **Where landmarks matter (strong).** Michon & Denis (2001) had people learn routes in Paris. Landmarks were reported most often at reorientation points, and route directions without landmarks were rated poorly.\[1\]\[16\]
  - A 2021 review (Yesiltepe et al., _Cognitive Processing_) concludes there is broad agreement that "landmarks on route and also at decision points (with a turn) are more effective during wayfinding tasks".\[1\]
  - Landmarks along the route mostly confirm that you are still on the right road. Lovelace et al. (1999) distinguish landmarks at choice points, at non-decision points on the route, and off the route.\[17\]
- **Local versus global landmarks (moderate).**
  - Local landmarks (shopfronts, petrol stations) reduce errors more than distant global ones. In some studies, mixing the two caused interference.\[1\]
  - People familiar with an area rely more on local landmarks.\[1\]
  - In Steck & Mallot's study, a petrol station was explicitly among the objects people chose for local decisions.\[1\]
  - For a daily Tbilisi driver, brand-tagged fuel stations, metro entrances, churches and malls at corners are therefore the right cue type. Your "Connect petrol station" example fits this exactly.
- **What makes a landmark salient.** The models of Raubal & Winter (2002) and Caduff & Timpf (2008) combine three kinds of salience:
  - Visual: size, contrast, façade.
  - Semantic: cultural meaning, function, and whether it has a name or brand.\[1\]
  - Structural: where it sits relative to the junction and the turn.
  - The review also notes that landmark descriptions should be short ("turn right after the bank").\[1\]
- **Landmarks versus street names, and GPS (moderate).**
  - Machine-generated instructions use street names and distances, while people use landmarks.\[1\]
  - In driving-simulator and real-world studies, landmark-based instructions ("turn right at the bookstore") improved landmark and route knowledge compared with standard instructions. The suppression of learning caused by standard turn-by-turn instructions was alleviated, and longer landmark descriptions helped more.\[6\]\[18\]\[19\]
  - Dahmani & Bohbot (2020, _Scientific Reports_, 50 drivers) found that greater lifetime GPS use went with worse spatial memory during self-guided navigation. In a three-year follow-up of a small subsample (13 people), more GPS use predicted a steeper decline. This is correlational, but the authors' dose-dependent finding ("the greater use of GPS, the greater decline in spatial memory over time") and the absence of reverse causation through sense of direction make it suggestive.
  - Implication: Pindoro's cards should pair street names with landmarks, because the names are what you recite and the landmarks are what you see. Real drives should be GPS-free.

### Verbal route descriptions and mental rehearsal

- **Practice is strong; transfer is weak.** The taxi exam itself is verbal recital, and drivers report visualising in-street views while planning.\[20\] The generation effect and retrieval practice (producing an answer rather than reading it) are among the best-supported findings in memory research. That supports typed or spoken recall over multiple choice.
- **Evidence gap.** No published controlled evidence shows that reciting routes aloud transfers to better real-world driving, as opposed to better recital. Treat it as plausible and measure it in your own experiment.
- **Quality of route directions.** Good directions mark each reorientation point with a landmark and the action to take, and add confirming landmarks on long stretches. This is a useful rubric for what a "good" recital should contain beyond street names.

### Visual scene memory and place recognition

- **Capacity (strong).** Standing (1973) showed people can recognise thousands of pictures. Brady, Konkle, Alvarez & Oliva (2008, _PNAS_) showed that 2,500 objects viewed over 5.5 hours were stored with fine detail.\[8\]\[21\]
  - Recognising "I have seen this junction before" is therefore cheap.
  - Recalling the name of a scene is a separate, harder association: a paired-associate task. Capacity results say nothing about its difficulty.
- **Viewpoint dependence (moderate).** Scene recognition costs more when the perspective changes between study and test. Recognition is better when the test view matches the orientation learned.\[9\] Return paths are harder than the learned direction, because travellers may not recognise the reverse view.\[10\]
  - Implication: one image per approach direction. A street learned from one end is a different item from the other end.
- **GeoGuessr-style skill (weak).** I found no peer-reviewed work on GeoGuessr-type training transferring to recognising real streets while driving.
  - Practical judgement: photo training at driver's eye height in the travel direction should transfer best.
  - Seasons, lighting and construction will reduce the match, so captures should be recent and taken from the road.

### Learning at junctions and decision points

- **Schedule decisions, not routes.** Route knowledge is a chain of view → action associations.\[22\] The landmark and route literature locates the hard part at reorientation points. Taxi-driver data show planning time concentrated on direction changes and boundary crossings.
- **Why not schedule whole routes.** A route card mixes 10–30 decisions of very different difficulty, so FSRS cannot estimate its stability properly. One failed turn would also force the whole route to repeat.
- **Recommendation:** junction-decision cards are the scheduled unit. Routes are test material, and each failed decision in a recital is credited back to its junction card.
- **Interference.** Similar junctions interfere: same road classes, similar geometry, the same fuel brand. The previous design already handles confusable sibling streets. Do the same for "sibling junctions": space them apart, and use contrastive feedback that shows both.

## Buildable Spec

### New per-item state (pure Dart, stored in the user database next to street cards)

| Field            | Type                             | Notes                                                                                                                                                                                        |
| ---------------- | -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| itemId           | string                           | `J:{junctionId}:{approachEdgeId}`, `G:{neighbourhoodId}:{gatewayJunctionId}:{in/out}`, `C:{streetId}`, `L:{landmarkId}:{variant}`, `S:{imageId}:{variant}`, `B:{bridgeId}:{bank}:{approach}` |
| type             | enum                             | J, G, B, C, L, S1, S2, S3, R (run)                                                                                                                                                           |
| fsrs             | {D, S, lastReview, reps, lapses} | Same FSRS-6 implementation; separate parameter preset per type once ≥1,000 reviews exist (until then, default 21 weights)                                                                    |
| desiredRetention | double                           | 0.90 for J/G/B/C/L; 0.85 for S1–S3 (cheaper to re-learn, lower stakes)                                                                                                                       |
| prerequisites    | list of itemIds                  | Street cards that must be Known before unlocking                                                                                                                                             |
| siblings         | list of itemIds                  | Confusable junctions or images, used for spacing and contrastive feedback                                                                                                                    |
| implicitEvidence | list of {date, source, outcome}  | From recitals and driving logs; only failures change FSRS state (see below)                                                                                                                  |

### Item types and cards

| Type                    | Cue → response                                                                                                                                                            | Recall/recognition                                                                                 | What the question must show                                                                                                | Unlocks when                                                                                       |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| **B** Bridge access     | "On [left-bank street X] heading [toward anchor], how do you get onto [bridge]?" → sequence of 1–3 decisions plus landmark                                                | Recall (pick exits in order)                                                                       | Text cue; label-free map zoomed to the approach, with no names                                                             | The bridge and X are Known (skeleton phase)                                                        |
| **J** Junction decision | "On X heading toward [anchor/region], at [landmark or junction description], to reach [target street/region/bridge] → turn left/right/straight/U onto Z"                  | Recognition among the junction's _legal_ exits (2–5 options), then typed name of Z for full credit | Unlabelled local map of the junction with the approach arrow, _or_ the approach photo when one exists; target name as text | X and Z Known; for non-skeleton junctions, district grid ≥80 % Solid                               |
| **G** Gateway           | Out: "Leaving [neighbourhood] toward [skeleton road/bridge], which exit?" → gateway junction plus street. In: reverse                                                     | Pin drop of the gateway on the blank map plus typed street name                                    | Neighbourhood outline on the blank map, no labels                                                                          | ≥70 % of the neighbourhood's parent streets Known                                                  |
| **C** Connection        | "X runs from __ to __" (end streets) and "Which street connects A and B?"                                                                                                 | Typed recall; the existing crossings drill covers what lies between                                | Names only (no map), then a map in feedback                                                                                | The street and both end streets Known                                                              |
| **L** Landmark          | L1: landmark → pin location. L2: landmark → junction ("Connect station: on which street, near which crossing?"). L3: junction plus turn → which landmark is at the corner | L1 pin (graded like card P), L2/L3 typed or picked                                                 | Landmark name/brand/type text; for L3, the junction approach                                                               | Personal landmarks: immediately. OSM landmarks: once their street is Known                         |
| **S1** Scene → name     | Approach photo → street name (and road being entered)                                                                                                                     | Typed recall or self-grade; multiple choice only as a fallback after a failed recall               | One cropped forward-facing photo, no signs legible if possible                                                             | The street's P and N cards are Solid                                                               |
| **S2** Scene → action   | Approach photo plus destination → turn                                                                                                                                    | Pick                                                                                               | Photo plus destination text                                                                                                | The corresponding J card is Known                                                                  |
| **S3** Scene → location | Photo → pin plus heading on the blank map                                                                                                                                 | Pin plus arrow                                                                                     | Photo, then the blank map _on a separate screen_ (important for any Google content)                                        | The district is ≥80 % Solid                                                                        |
| **R** Run / recital     | "Recite A → B"                                                                                                                                                            | Free recall (typed, spoken or picked)                                                              | Start and end only (names or landmarks)                                                                                    | Run: all its J/G/B items Known. Random point-to-point: weekly, from the start of the gateway phase |

**How recitals and drives feed back.** A failed decision inside a recital or a logged drive is recorded as an Again review on that junction card, if the card is due within 50 % of its interval or earlier. Correct decisions are only logged, never counted as reviews. This avoids inflating stability through repeated test exposure.

### Making "any A to any B" achievable: decomposition and counts

Assumptions (stated because the graph statistics were not given):

- Skeleton = 12 bridges plus about 40 trunk/primary/secondary corridors, with about 150 junctions where two skeleton roads meet.
- Each neighbourhood has 4–8 gateways onto the skeleton, about 6 on average.

| Layer                  | Items                                          | Estimate for Tbilisi                      | Order                                         |
| ---------------------- | ---------------------------------------------- | ----------------------------------------- | --------------------------------------------- |
| Bridge access (B)      | 12 bridges × 2 banks × ~2 approaches           | ~48                                       | Month 1, right after the skeleton streets     |
| Skeleton decisions (J) | ~150 junctions × ~3 approaches                 | ~450                                      | Months 1–4, centre outward, alternating banks |
| Gateways out (G)       | 68 × ~6                                        | ~400                                      | With each neighbourhood chunk                 |
| Gateways in (G)        | 68 × ~6                                        | ~400 (optional, phase 2)                  | After the "out" card of that gateway is Solid |
| Connections (C)        | Secondary-and-above parent streets             | ~400                                      | With the grid phase                           |
| Landmarks (L)          | Top-salience OSM plus personal                 | ~300                                      | Personal: day 1; OSM: with the district       |
| Scene → action (S2)    | Skeleton and gateway approaches with imagery   | ~400                                      | As imagery becomes available                  |
| **Core total**         |                                                | **~2,000** (excluding in-gateways and S1) |                                               |
| Scene → name (S1)      | Secondary-and-above streets, one approach each | ~800 (phase 2)                            | After the street is Solid                     |

**How a route is composed.** Any A → B becomes:

- A → A's neighbourhood gateway (local; follows from the street-name knowledge of that neighbourhood);
- gateway → skeleton path (B and J cards, including a bridge if the banks differ);
- skeleton → B's gateway → B.

This is fine-to-coarse planning made explicit. For same-neighbourhood trips, the name layer alone suffices. Instead of learning about 20 million ordered pairs, you learn about 2,000 decisions plus the street names you are already learning.

**Choosing the minimal set automatically (server-side, at pack build).**

1. Sample about 20,000 random origin–destination pairs weighted by street length.
2. Compute directed shortest paths on the turn-restricted graph.
3. Count how often each (junction, approach, exit) decision is used.
4. Greedily select decisions until 90 % of the decision-instances on sampled routes are covered. Expect a heavy-tailed distribution, with a few hundred skeleton decisions covering most traffic.
5. Use the counts to order unlocking within a phase.

### Reciting a route by heart and grading it

**Input formats** (all offline):

1. **Typed**, with autocomplete restricted to the next legal streets. That is recognition, so the score is capped at Good.
2. **Typed free text**, parsed afterwards. Full credit.
3. **Spoken**, recognised on the device. Full credit when the transcript is confirmed.
4. **Pick sequence** on an unlabelled map, junction by junction. This is your existing road-trip mode.
5. **Self-graded fallback.** Speak aloud with no recognition, then compare with the model route and rate it 1–4.

**Grading algorithm** (pure Dart, runs in under 100 ms on a city-sized graph):

1. **Tokenise.** Split on separators and connective words ("then", "left", "right", "at", "past", Georgian equivalents). Keep turn words and landmark mentions as annotations.
2. **Resolve names.** Fuzzy-match each token against Georgian, English and transliterated names plus personal aliases. Use normalised Levenshtein ≤0.25, then pick among candidates by spatial plausibility (the previous street's neighbours). Landmark tokens resolve to their attached junction.
3. **Build the path.** Run a Viterbi pass over candidate junctions between consecutive streets on the _directed, turn-restricted_ graph. Allow up to 2 "silent connectors" of ≤150 m each (unnamed or short links), each penalised. Output the cheapest legal path that visits the named streets in order.
4. **Score.**
   - stretch = length(path) ÷ length(shortest legal path A→B);
   - Perfect ≤1.03, Great ≤1.25, Close ≤1.60 (same thresholds as road-trip mode);
   - invalid if a transition is impossible (streets don't meet), illegal (against a one-way or a turn restriction), or needs more than 2 connectors.
5. **Partial credit.** Score each consecutive decision. A decision is correct if it is legal and lies on some legal path to B with stretch ≤1.25 from that point. Partial score = correct ÷ total. Optionally reward landmarks named at reorientation points (+0.1 each, capped at +0.3) to encourage Michon & Denis-style directions.
6. **Map to an FSRS rating** for run cards:

| Result                                   | FSRS rating |
| ---------------------------------------- | ----------- |
| Invalid, or stretch >1.60                | Again       |
| Stretch 1.25–1.60                        | Hard        |
| Stretch 1.03–1.25                        | Good        |
| Stretch ≤1.03 and recalled without hints | Easy        |

**Speech recognition, Georgian and English (offline).**

- **Vosk** is offline and supports Georgian. Its small Georgian model (vosk-model-small-ka-0.42) is 45 MB, with a word error rate of 18.0 % on Fleurs and 14.2 % on Common Voice 17 according to Alpha Cephei's official model list (Apache 2.0); the larger 700 MB model reaches 12.7 % on Fleurs. Flutter plugins exist (vosk_flutter and forks); the official plugin was historically Android-first, so verify iOS.
- **Accuracy trick:** Vosk allows quick vocabulary reconfiguration.\[23\] Restrict recognition to a grammar of the 3,841 street names plus turn words and landmark names, which should cut errors substantially on proper nouns.
- **Platform speech engines:** I could not confirm on-device Georgian support in the Android or iOS engines. Assume online-only or unsupported.
- **English street names** read aloud by a Georgian speaker will be poorly served by English models. Prefer reciting in Georgian with the Georgian model, and treat English speech as best-effort.
- **Always show the transcript** for one-tap correction before grading. If recognition confidence is below a threshold, fall back to self-grading.

### Landmark data

**OSM tags to extract** (pack build, PostGIS):

| Category                     | Tags                                                                 | Base type score (0–1)             |
| ---------------------------- | -------------------------------------------------------------------- | --------------------------------- |
| Fuel                         | `amenity=fuel` + `brand`/`operator`/`name`                           | 0.9                               |
| Metro                        | `station=subway`, `railway=station`, `railway=subway_entrance`       | 1.0                               |
| Bridges, river               | `bridge=yes` + `name`, `waterway=river`                              | 1.0 (structural)                  |
| Worship                      | `amenity=place_of_worship` + `religion`, `building=church/cathedral` | 0.8                               |
| Malls, big shops             | `shop=mall`, `shop=supermarket/department_store` + `brand`           | 0.8                               |
| Transport hubs               | `amenity=bus_station`, `public_transport=station`                    | 0.8                               |
| Hospitals, universities      | `amenity=hospital/university`                                        | 0.7                               |
| Monuments                    | `historic=monument/memorial`, `tourism=attraction`, `man_made=tower` | 0.7                               |
| Squares, roundabouts         | `place=square`, `junction=roundabout` + `name`                       | 0.9                               |
| Stadiums, parks              | `leisure=stadium/park`                                               | 0.6                               |
| Banks, pharmacies, fast food | `amenity=bank/pharmacy/fast_food` + `brand`                          | 0.4 (frequent, so low uniqueness) |
| Traffic lights               | `highway=traffic_signals`                                            | 0.3 (structural only)             |

**Salience formula** (after Raubal & Winter and Caduff & Timpf; weights are a starting assumption, to be tuned by your personal use):

`salience = 0.30·type + 0.15·brandOrName + 0.15·size + 0.10·wiki + 0.15·uniqueness + 0.15·structural`

- size = min(1, log10(footprint m² or `building:levels`·100)/4);
- wiki = 1 if `wikidata` or `wikipedia` is present;
- uniqueness = 1 / (number of same-type features within 300 m);
- structural = 1 if within 40 m of the junction on the approach-side corner of a turn, 0.6 if on the far corner, 0.3 if along the route.

**Attaching landmarks to junctions.** For each J item (junction, approach, exit), choose the top landmark within 60 m. Prefer the corner _before_ the turn on the approach side. Store `landmarkId`, `side` (left/right) and `relation` (before/after/at).

**Personal landmarks (fast entry).** Long-press on the map, or "here" from the phone's location while parked. Then:

- type a short name ("Connect");
- pick a category;
- the app snaps the landmark to the nearest junction and approach.

Personal landmarks get salience 1.0 and take priority, because self-chosen cues are what you actually notice. Personal landmarks can also be imported from a CSV of lat/lon/name.

### One-ways and turn restrictions

- **One-ways.** Convert the graph to directed edges: `oneway=yes/-1/no`, `junction=roundabout` implies one-way, and `oneway:psv` is ignored for private cars.
- **Turn restrictions.** Parse OSM `type=restriction` relations (`from` way, `via` node or way, `to` way). Values: `no_left_turn`, `no_right_turn`, `no_u_turn`, `no_straight_on`, `only_*`. Include conditional or vehicle-specific variants only for `motorcar`.
- **Graph form.** Use an edge-expanded graph, where states are directed edges and transitions are allowed turns. Then A* handles restrictions naturally. Add a U-turn penalty of 30 s-equivalent, and forbid U-turns on divided roads.
- **Data quality caveat.** I could not assess how complete Tbilisi's OSM turn restrictions are. Assume gaps:
  - include a "report: this turn is actually forbidden or allowed" button in feedback, stored as a local override and synced to the server;
  - fix true errors in OSM itself.
- **Migration.** The existing road-trip mode should move from the undirected graph to this one, so that drives and recitals are graded consistently.

### Feedback that each question must show

| After              | Must show                                                                                                                                                                                                                                                                                                                            |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| J/G/B decision     | Correct exit highlighted on the unlabelled local map; the attached landmark and its side; the approach photo if present; if wrong, where your choice leads and the sibling junction you may be confusing it with                                                                                                                     |
| Recital/run        | Your parsed path versus the shortest legal path on the map; stretch ratio and verdict; the first divergence junction; correct, legal-but-detour and illegal segments in distinct styles; reasons for illegal moves (one-way, restriction); landmarks at missed decisions; one-tap jump to the failed junction cards                  |
| S1/S2/S3 scene     | Street name in Georgian and English; position and heading on the blank map (on a separate screen if the image is Google content); the junction and which approach; the opposite-direction image if available; capture date and attribution (photographer + licence + Mapillary logo/link where required); confusable sibling streets |
| L landmark         | Landmark on the map with its attached junction(s), side and approach                                                                                                                                                                                                                                                                 |
| GPS-free drive log | Map-matched track versus the shortest legal route; stretch; hesitations (speed under 5 km/h for over 10 s outside traffic lights), U-turns; decisions credited or failed                                                                                                                                                             |

### Workload and timeline

Assumptions:

- About 8 reviews per item in the first year, including learning steps.
- About 10 s per J/G/C/L/S review and 30 s per new-item introduction, so about 100 s per item in its first year.
- About 3 minutes per day of recitals once the gateway phase starts.

Previous estimate for the street names: about 10–11 months at 20 min/day, roughly 107 hours.

| Component                                     | Hours (first year) |
| --------------------------------------------- | ------------------ |
| Street names (previous design)                | ~107               |
| Core route and visual items (~2,000 × ~100 s) | ~55                |
| Recitals (3 min/day over ~400 days)           | ~20                |
| **Total**                                     | **~180**           |

| Daily budget | Time to core mastery (streets + route/visual core) | Suggested split                |
| ------------ | -------------------------------------------------- | ------------------------------ |
| 15 min/day   | ~24 months                                         | 11 names / 4 route             |
| 20 min/day   | ~18 months                                         | 13 names / 5 route / 2 recital |
| 30 min/day   | ~12 months                                         | 18 names / 8 route / 4 recital |

These are estimates; FSRS will reveal the real cost within 4–6 weeks. Add phase-2 items (in-gateways, S1) only when the daily due count stays under budget for 14 days. Cap new route items at 10 per day and stop introducing new items on days when due reviews exceed 120 % of the budget. Workload creep is the main risk.

**Balance with real driving.** Your earlier plan budgeted 3–4 hours a week, and you drive daily, so use that.

- **"Drive this run today."** Each morning the app proposes one run that overlaps your likely trips, drawn from due B/J/G items.
- **GPS-free drive mode.** Record a background GPS track with the screen off and no map. Afterwards:
  - map-match on the device: snap fixes to directed edges by distance and heading, then fill gaps with shortest legal paths;
  - grade the drive like a recital;
  - log decisions as implicit evidence.
- **Safety rule:** no in-app interaction while moving. Recitals are done parked or as a passenger.
- **Weekly target:** at least 2 GPS-free trips to a place you haven't driven to before.

## Street-Level Imagery Options

### Comparison

| Source                                       | Tbilisi coverage                                                                                                                                                          | Licence and terms                                                                                                                                                                                                                                                                                                  | Offline cache/bundle?                                                                   | Cost                                                                 | Fit for Pindoro                                                                                                                                                              |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------- | -------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Google Street View Static API**            | Very good and fresh: Georgia launched 22 Jun 2026; 13,000 km including Tbilisi, captured from 2025\[24\]\[25\]                                                            | Proprietary. No caching except `pano` IDs (which may be stored indefinitely); no pre-fetch or bulk download; no derived content (e.g. building a location index from imagery); apps must have public Terms of Use and a Privacy Policy; attribution; no Street View with a non-Google map on the same screen\[26\] | **No**                                                                                  | 10,000 free/month, then $7 per 1,000; billing account required\[27\] | Online-only, separate screens, live fetch each time. Legal grey area for a quiz; not recommended as core                                                                     |
| **Google Map Tiles API – Street View Tiles** | Same                                                                                                                                                                      | As above, plus "applications should use Map Tiles API for map visualizations"; non-visualisation and offline uses not allowed; EEA terms forbid use with any map\[28\]\[29\]                                                                                                                                       | **No**                                                                                  | 100,000 free/month, then $2 per 1,000\[27\]                          | Building your own panorama viewer from tiles adds nothing over the Static API, with stricter rules                                                                           |
| **Google Street View Metadata**              | Same                                                                                                                                                                      | Returns pano ID and date                                                                                                                                                                                                                                                                                           | Pano IDs cacheable                                                                      | Unlimited free\[27\]                                                 | Useful server-side to record which junctions have Google coverage, for deep links                                                                                            |
| **Google Maps SDK / Embed / Maps URLs**      | Same                                                                                                                                                                      | SDK and Embed are listed as unlimited free; Maps URLs open the Google Maps app                                                                                                                                                                                                                                     | No                                                                                      | Free                                                                 | **Recommended Google path:** a "look around here" button that opens Google Maps at the junction and heading (Maps URLs). Zero caching, no API key, no imagery inside Pindoro |
| **Mapillary (Meta), API v4**                 | Patchy, crowdsourced; at least one Tbilisi contributor reports about 103,500 images over 470 km; check the coverage map\[30\]                                             | User content CC BY-SA 4.0 (Meta may serve some under CC BY-NC-SA); images may be downloaded and served from your own servers with the **Mapillary logo plus link**; register the app (client_id); no use in navigation synchronised to the device's position\[2\]\[31\]                                            | **Yes** (thumbnails up to 2048 px; signed URLs expire, so download at pack build)\[32\] | Free                                                                 | **Use now** for scene cards wherever coverage exists; per-image photographer credit\[2\]\[33\]\[34\]                                                                         |
| **Panoramax** (self-hosted)                  | Essentially none in Georgia                                                                                                                                               | Server is open source (Python/Flask + PostgreSQL/PostGIS, Docker Compose); instances typically CC BY-SA 4.0; automatic face/plate blurring; private instances allowed\[35\]\[36\]                                                                                                                                  | **Yes** (your own data)                                                                 | Your server and disk                                                 | **Use now as the host for your own captures**; matches your stack\[3\]\[4\]                                                                                                  |
| **KartaView**                                | Nothing found for Tbilisi                                                                                                                                                 | CC BY-SA; mostly flat image sequences\[37\]                                                                                                                                                                                                                                                                        | Yes (licence)                                                                           | Free                                                                 | Ignore unless coverage turns up                                                                                                                                              |
| **Yandex Panoramas**                         | A Tbilisi street-panorama layer exists, but coverage appears thin and central; capture dates unclear; Georgia is not listed among Yandex's panorama countries\[38\]\[39\] | Proprietary (terms not reviewed; assume no caching)                                                                                                                                                                                                                                                                | Assume no                                                                               | n/a                                                                  | Not recommended                                                                                                                                                              |
| **Apple Look Around**                        | Not available in Georgia (as of May 2025; not on announced expansion lists)\[40\]\[41\]                                                                                   | Proprietary                                                                                                                                                                                                                                                                                                        | No                                                                                      | n/a                                                                  | No                                                                                                                                                                           |
| **Bing Streetside**                          | No evidence of Georgia coverage                                                                                                                                           | Proprietary                                                                                                                                                                                                                                                                                                        | No                                                                                      | n/a                                                                  | No                                                                                                                                                                           |
| **Own capture** (360° camera)                | Whatever you drive                                                                                                                                                        | You own it; publish CC BY-SA if uploaded                                                                                                                                                                                                                                                                           | **Yes**                                                                                 | Camera plus time                                                     | **Core source** for decision junctions                                                                                                                                       |

**OpenStreetMap and imagery.** OSM itself hosts no photos. It links to imagery through tags such as `mapillary=‹image id>` and `panoramax=<uuid>` on features. Your pack builder can use these tags to pick a curated image for a landmark or junction when one exists.

### What exactly Google allows (and does not) in this situation

- **Allowed:**
  - live display of Street View Static images or SDK panoramas in an online app;
  - storing panorama IDs indefinitely;
  - Metadata calls;
  - opening Google Maps through Maps URLs.
- **Not allowed:**
  - caching or storing the images (so no offline packs);\[26\]
  - pre-fetching or bulk download;\[42\]
  - building indexes or derived content from imagery;
  - Map Tiles for offline or non-visualisation uses;
  - Street View imagery on the same screen as a non-Google map. Your unlabelled self-hosted basemap counts, so an S3 "photo → pin on map" card with Google imagery would violate this unless photo and map are on separate screens.\[43\]
  - Showing Street View Static content in the app also requires publicly accessible Terms of Use and a Privacy Policy linked from the download page and settings.\[26\] That is awkward for a sideloaded private app, though doable with a one-page site on your domain.
- **My reading:** a live, online "photo → type the street name" quiz on its own screen is probably within the letter of the terms, but turning Google imagery into flashcards is close to "creating content based on Google Maps Content". Treat it as legal risk and keep Google to deep links.

### Capturing your own imagery

- **Hardware:** a current consumer 360° camera, such as the Insta360 X-series or GoPro MAX, on a roof or window mount. Mapillary's guides recommend for driving:
  - Insta360: 8K 360 timelapse video at a 0.2 s interval;\[44\]
  - GoPro MAX: 360 video at 25 fps.\[45\]
    A phone or dashcam (forward-facing, 1080p+) is an acceptable cheaper option for the forward-view crops the cards need.
- **Resolution and size:** GoPro MAX photos are 5,760×2,880. Mapillary says about 13 hours of Insta360 8K/0.2 s timelapse fits on 256 GB, which works out to about 1.1 MB per extracted frame (my calculation).\[44\]\[46\]
- **Storage for all of Tbilisi:**
  - 2,202 km at one frame every 5 m is about 440,000 frames, roughly 0.5 TB at 1.1 MB per frame, one direction only.
  - It would also mean well over 100 hours of driving.
  - Not worth it for learning.
- **Storage for what the cards need:**

| Set                                | Images     | At ~150 KB (1280×720 WebP crop) | At ~80 KB (960×540) |
| ---------------------------------- | ---------- | ------------------------------- | ------------------- |
| Skeleton + bridge approaches (J/B) | ~500       | ~75 MB                          | ~40 MB              |
| Gateways out + in (G)              | ~800       | ~120 MB                         | ~64 MB              |
| S1 street scenes (secondary+)      | ~800       | ~120 MB                         | ~64 MB              |
| **Total in pack**                  | **~2,100** | **~315 MB**                     | **~170 MB**         |

- **Pipeline:**
  1. Drive with continuous 360° capture.
  2. Upload originals to the self-hosted Panoramax, which handles GPS, sequences and blurring.
  3. At pack build, for each decision item, select the frame 25–40 m before the junction on the approach edge.
  4. Reproject a forward-facing 100° field of view at the approach heading.
  5. Export WebP and store it in the pack with `{imageId, junctionId, approachEdgeId, heading, capturedAt, licence, author}`.
  6. Optionally keep the full 360° panorama on the server for an online "look around" view (Flutter `panorama_viewer` renders equirectangular images on Android and iOS).\[47\]\[48\]\[49\]
- **Privacy in Georgia:**
  - Georgia's 2023 Law on Personal Data Protection defines processing to include "photographing" and "video monitoring". Faces and plates in your captures are personal data.\[50\]\[51\]
  - Blur before sharing beyond yourself. Panoramax instances provide automatic face and plate blurring; Mapillary blurs on upload.\[2\]
  - Do not capture private property or schools deliberately (Mapillary's content rules also forbid this).\[2\]
  - I did not confirm whether a personal or household exemption applies; assume sharing with friends is not exempt.

### Flutter integration

| Source                           | Integration                                                                                                                         |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Bundled crops (own or Mapillary) | `Image.file` from the pack; no network                                                                                              |
| Online 360° (own Panoramax)      | `panorama_viewer` (equirectangular, Android/iOS, sensor controls) fed from your server\[47\]\[48\]                                  |
| Mapillary live                   | REST v4 (`graph.mapillary.com`) with a client token for coverage checks at pack build; MapillaryJS only in a WebView if ever needed |
| Google                           | `url_launcher` with a Maps URL for Street View at lat/lon/heading; no SDK needed                                                    |

## Changes to the 3-Week Self-Experiment

- **Design:** within-subject, with matched district pairs.
  - Split districts into matched pairs (similar size, distance from home, prior familiarity) and randomly assign one of each pair to "route + visual training" and the other to "names only".
  - Pre-test on day 0, post-test on day 21, delayed retest on day 35.
- **Tests:**

| Test               | Items                                                                                                                                                   | Measure                                                               |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| Recital transfer   | 20 random A→B pairs (3–8 km straight line): 10 in trained, 10 in control districts; half of the trained ones avoid any studied run                      | Stretch ratio, validity, partial score, time                          |
| Scene recognition  | 40 photos: 15 trained approach direction, 10 trained junctions from the _opposite_ direction, 15 control                                                | S1 accuracy and reaction time; viewpoint cost = same − opposite       |
| Landmark-junction  | 20 L2 items (half personal landmarks)                                                                                                                   | Accuracy                                                              |
| **GPS-free drive** | 4 drives from random A to random B, picked by the app (2 trained, 2 control districts); background GPS log, no map; a passenger holds a sealed fallback | Stretch ratio vs shortest legal route, U-turns, hesitations, abandons |

- **Primary outcome:** the trained-minus-control difference in drive stretch and recital stretch.
- **Secondary outcomes:** viewpoint cost and transfer to non-run pairs.
- **Small-N caution:** with one subject, read effects as directional. Pre-register the thresholds: for example, a ≥0.10 lower median stretch in trained districts counts as a meaningful benefit.

## Risks and Open Questions

| Risk                                                  | Severity         | Mitigation                                                                            |
| ----------------------------------------------------- | ---------------- | ------------------------------------------------------------------------------------- |
| Imagery licensing (Google)                            | High if misused  | Google only through deep links; never cache                                           |
| Mapillary share-alike/NC exceptions, logo requirement | Low              | Store licence per image; show logo and credit; exclude NC images                      |
| Coverage gaps (Mapillary, Panoramax)                  | High             | Own capture of decision junctions first; cards work without photos (map-only J cards) |
| Viewpoint mismatch (season, direction, lane)          | Medium           | One image per approach; recapture yearly; test the opposite direction explicitly      |
| Workload creep                                        | High             | Hard daily caps; phase-2 items gated on stable due counts                             |
| Georgian speech recognition quality                   | Medium           | Vosk with a constrained grammar; confirm the transcript; self-grade fallback          |
| OSM turn-restriction completeness in Tbilisi          | Medium (unknown) | Local overrides plus OSM fixes; flag low-confidence junctions                         |
| Transfer from app to road is unproven                 | Medium           | GPS-free drive logs as ground truth; the experiment above                             |
| Safety while driving                                  | High             | No interaction while moving; recitals parked or as a passenger                        |
| Privacy of own captures                               | Medium           | Blur before any sharing; avoid sensitive sites                                        |

**Open questions:**

- What is the real junction count of the Tbilisi graph? Recompute the item estimates from the pack.
- Whether "Georgi Mindeli Bridge" in the dictation is a transcription of another bridge name. The example works either way.
- Whether Vosk's iOS path in Flutter is mature enough. Prototype before committing.
- How much Mapillary actually covers Tbilisi's skeleton junctions. Query the coverage tiles at pack build and print a coverage report.

## Caveats

- Several numbers are engineering estimates, not measured values: the item counts, salience weights, review-time assumptions and timelines. Replace them with pack statistics and FSRS logs after the first month.
- The pricing and terms quoted reflect Google's pages as published in 2026. Re-check before enabling any Google API, since Google changes pricing and terms periodically.
- The evidence that verbal recital and photo training transfer to real driving is indirect. The design therefore treats GPS-free drives as the final test.
- A source list is attached separately by the citation pass.

## Sources

1. [Landmarks in wayfinding: a review of the existing literature - PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC8324579/)
2. [Terms of Use](https://www.mapillary.com/terms)
3. [Panoramax - OpenStreetMap Wiki](https://wiki.openstreetmap.org/wiki/Panoramax)
4. [🖥️ Host an instance - Panoramax - Docs](https://docs.panoramax.fr/how-to-contribute/hosting-instance/)
5. [Habitual use of GPS negatively impacts spatial memory during self-guided navigation](https://www.nature.com/articles/s41598-020-62877-0)
6. [Landmark-Based Navigation Instructions Improve Incidental Spatial Learning in Real-Life Environments](https://www.biorxiv.org/content/10.1101/789529v2.full)
7. [(PDF) Landmark information included in turn-by-turn instructions induce incidental acquisition of lasting route knowledge](https://www.researchgate.net/publication/357623969_Landmark_information_included_in_turn-by-turn_instructions_induce_incidental_acquisition_of_lasting_route_knowledge)
8. [A review of visual memory capacity: Beyond individual items and toward structured representations](https://jov.arvojournals.org/article.aspx?articleid=2191865)
9. [Orientation and perspective dependence in route and survey learning - PubMed](https://pubmed.ncbi.nlm.nih.gov/14736304/)
10. [Frontiers](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2016.01956/full)
11. ['Fine-to-coarse' route planning and navigation in regionalized environments - Bournemouth University Staff Profile Pages](https://staffprofiles.bournemouth.ac.uk/display/journal-article/13753)
12. [(PDF) Path planning and optimization in the traveling salesman problem: Nearest neighbor vs. region-based strategies.](https://www.researchgate.net/publication/221026120_Path_planning_and_optimization_in_the_traveling_salesman_problem_Nearest_neighbor_vs_region-based_strategies)
13. [London taxi drivers exploit neighbourhood boundaries for hierarchical route planning](https://www.biorxiv.org/content/10.1101/2024.02.20.581139v1)
14. [Griesbauer2022-review (pdf) - CliffsNotes](https://www.cliffsnotes.com/study-notes/28675072)
15. [Expert Navigators Deploy Rational Complexity-Based Decision Prioritization for Large-Scale Real-World Planning](https://www.biorxiv.org/content/10.1101/2024.03.25.586612v2.full)
16. [When and Why Are Visual Landmarks Used in Giving Directions?](https://www.researchgate.net/publication/221600769_When_and_Why_Are_Visual_Landmarks_Used_in_Giving_Directions)
17. [Full article: Wayfinding Through Orientation](https://www.tandfonline.com/doi/full/10.1080/13875868.2017.1322597)
18. [Landmark-Based Turn-by-Turn Instructions Enhance Incidental Spatial Knowledge Acquisition](https://www.biorxiv.org/content/10.1101/2020.11.30.403428.full.pdf)
19. [Landmark-Based Navigation Instructions Improve Incidental Spatial Knowledge Acquisition in Real-World Environments](https://www.biorxiv.org/content/10.1101/789529v3.full)
20. [Expert Navigators Deploy Rational Complexity-Based Decision](https://www.biorxiv.org/content/10.1101/2024.03.25.586612v2.full.pdf)
21. [\[PDF\] Visual long-term memory has a massive storage capacity for object details](https://www.semanticscholar.org/paper/Visual-long-term-memory-has-a-massive-storage-for-Brady-Konkle/8458e49fb08d2cca3a8d7355465e182c30785220)
22. [(PDF) How useful are landmarks when learning a route in a virtual environment? Evidence from typical development and Williams syndrome](https://www.researchgate.net/publication/224872851_How_useful_are_landmarks_when_learning_a_route_in_a_virtual_environment_Evidence_from_typical_development_and_Williams_syndrome)
23. [VOSK Offline Speech Recognition API](https://alphacephei.com/vosk/)
24. [Google Street View officially launches in Georgia - 1TV](https://1tv.ge/lang/en/news/google-street-view-officially-launches-in-georgia/)
25. [Street View opens a new window into Georgia](https://blog.google/products-and-platforms/products/maps/georgia-street-view/)
26. [Policies and attributions for Street View Static API | Google for Developers](https://developers.google.com/maps/documentation/streetview/policies)
27. [Google Maps Platform core services pricing list | Pricing and Billing | Google for Developers](https://developers.google.com/maps/billing-and-pricing/pricing)
28. [Google Maps Platform EEA Service Specific Terms](https://cloud.google.com/terms/maps-platform/eea/maps-service-terms)
29. [Map Tiles API Policies | Google Maps Tile API | Google for Developers](https://developers.google.com/maps/documentation/tile/policies)
30. [User:David Osipov - OpenStreetMap Wiki](https://wiki.openstreetmap.org/wiki/User:David_Osipov)
31. [\[EPIC\] Street-level imagery in the trainer game: investigated, and rejected on three independent grounds · Issue #374 · openzigs/onyourleft · GitHub](https://github.com/openzigs/onyourleft/issues/374)
32. [Download Mapilarry images with API v4 - Page 2 - Imagery - Mapillary Community Forum](https://forum.mapillary.com/t/download-mapilarry-images-with-api-v4/5215?page=2)
33. [User:David Osipov - Wikidata](https://www.wikidata.org/wiki/User:David_Osipov)
34. [Mapillary](https://atlas.co/data-sources/mapillary/)
35. [All Panoramax instances](https://www.panoramax.xyz/en/instances)
36. [Panoramax: At Mathias house](https://panoramax.basi.re/end-user-license-agreement)
37. [KartaView](https://bellingcat.gitbook.io/toolkit/more/all-tools/kartaview)
38. [Яндекс Панорамы — Википедия](https://ru.wikipedia.org/wiki/%D0%AF%D0%BD%D0%B4%D0%B5%D0%BA%D1%81_%D0%9F%D0%B0%D0%BD%D0%BE%D1%80%D0%B0%D0%BC%D1%8B)
39. [Сферические панорамы Грузии на Яндекс картах](https://gruzia.ge/our-works/13-panorams)
40. [Look Around (Apple)](https://en.wikipedia.org/wiki/Apple_Look_Around)
41. [Apple Maps Look Around coming to more areas](https://appleinsider.com/articles/24/08/12/apple-maps-look-around-spreading-outside-city-centers-in-the-us-coming-to-more-countries)
42. [02/05/2024, 10:27 Google Maps Platform Terms Of Service](https://assets.applytosupply.digitalmarketplace.service.gov.uk/g-cloud-14/documents/703097/494591824933587-terms-and-conditions-2024-05-02-0829.pdf)
43. [Appendix B-2: Google Maps Content](https://cesium.com/legal/terms-for-google/)
44. [Insta360 X Series](https://help.mapillary.com/hc/en-us/articles/11951588568604-Insta360-X-Series)
45. [GoPro MAX Series](https://help.mapillary.com/hc/en-us/articles/360012674619-GoPro-MAX-Series)
46. [GoPro MAX Action Camera — Specs, Reviews, Used Prices\<!-- --\>](https://gearfocus.com/m/gopro-max-360-camera)
47. [panorama\_viewer](https://pub.dev/packages/panorama_viewer)
48. [panorama\_viewer changelog](https://pub.dev/packages/panorama_viewer/changelog)
49. [Panorama](https://itsallwidgets.com/panorama)
50. [პერსონალურ მონაცემთა დაცვის შესახებ](https://matsne.gov.ge/en/document/view/5827307?publication=5)
51. [Georgia](https://www.globallegalpost.com/lawoverborders/data-protection-law-guide-1072382791/georgia-273882423)
