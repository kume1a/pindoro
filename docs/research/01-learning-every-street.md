# Pindoro: A Learning System for Every Street in Tbilisi

**Recommendation.** Rebuild Pindoro around one per-street memory model, FSRS-6 with its published default parameters and a 0.90 retention target. Every street in the city gets a schedule, not only the ones you miss. On top of the scheduler sits a fixed curriculum: the skeleton first, then the secondary/tertiary grid across the whole city, then neighbourhood by neighbourhood outward from the centre and from your home, with each parent street taught together with its numbered lanes and dead ends. Keep the blank-map pin as the main question. Grade it into FSRS ratings by distance and by which street the pin actually lands on, and replace "known after one good answer" with retention-based numbers. At a realistic 20 minutes a day this covers the ~3,150 core streets you don't yet know in roughly 10–11 months, with maintenance falling to about 3–5 minutes a day afterwards. The 16-week plan in your earlier doc can deliver the skeleton plus a few hundred streets, not the whole city.

## TL;DR

- **What to build:** FSRS-6 (21 default weights, desired retention 0.90) scheduling every street, with a pin-drop graded by distance _and_ by which street the pin snaps to. A curriculum queue runs skeleton → grid → neighbourhoods with parent-plus-lanes families, about 10 new streets a day at 20 min/day. Progress is reported as expected streets recalled today (Σ retrievability), not as "answered right once".
- **Why:** Retrieval practice with feedback and spaced reviews are the two best-supported learning techniques (both rated "high utility" by Dunlosky et al. 2013). The current app's design gaps fail them: massed first exposure, reviews only for mistakes, a "known" flag that never decays, and random free play. London Knowledge training confirms the shape of the curriculum: a main-road grid plus local quarter-mile areas, layered coverage, and spaced oral examinations.
- **How long:** With about 12 s per review and 45 s per new street, the core ~3,150 unknown streets take ~15 months at 15 min/day, ~10–11 months at 20 min/day and ~7–8 months at 30 min/day. Adding all 4,465 streets costs about 36 % more. Run a 3-week self-experiment first to measure your real seconds per item and to check that the predicted retention matches what you actually recall.

---

## 1. Key findings

1. **Your seven gaps are real, and the research says they are the important ones.** The biggest is gap 3 (no reviews for correct answers). Spacing is one of the most robust effects in memory research: in Cepeda et al. 2008, a study of 1,354 people, the best gap between study sessions declined from about 20–40 % of the retention interval for a test one week away to about 5–10 % for a test a year away. Remembering streets "for years" needs reviews stretching to months, and the current Pit stop stops at 21 days and then never schedules a street again.
2. **Recall with feedback beats recognition.** Rowland's 2014 meta-analysis of the testing effect found g = 0.50 (95 % CI 0.42–0.58) for testing over restudy across 159 effect sizes from 61 studies, and about 0.73 with feedback against 0.39 without. The three-option "Which street is this?" question is a recognition test with a one-in-three guess rate. It should not count towards "known".
3. **Map study builds survey knowledge; driving builds route knowledge.** Thorndyke & Hayes-Roth (1982) found that map learners judge global relations and straight-line distances better, while navigators judge route distances and local orientation better.\[1\] Montello (1998) argues the two kinds of knowledge grow together and continuously rather than in fixed stages.\[2\] Pindoro should therefore carry the survey and name layer, and your drives should carry the route layer, as your earlier plan assumed.
4. **The London Knowledge is a curriculum, not a quiz.** The Blue Book has 320 runs in 20 lists of 16. The runs are 2–3 miles long, mostly on trunk and primary roads ("Oranges and Lemons"), and are laid down in four overlapping layers of 80. Minor streets are learned from the start through the quarter-mile radius around each run's ends. Examinations ("appearances") come at intervals of 56, 28 and then 21 days.\[3\] Pindoro's curriculum should copy this structure: grid plus local areas, layered coverage, and spaced testing.
5. **Cities are remembered hierarchically, and the hierarchy distorts.** Stevens & Coupe (1978) and Hirtle & Jonides (1985) found that people store regions and judge positions through them. They underestimate distances within a cluster and overestimate them between clusters.\[4\]\[5\] Knowledge teachers fight a similar error caused by a bend in the Thames, which makes Victoria seem north of Waterloo.\[3\] Teaching by neighbourhood helps encoding. Interleaved city-wide reviews and orientation questions correct the distortions.
6. **Similar names cause interference, and the pack is full of them.** 1,552 "Nth Lane/Dead End of X" streets and 377 repeated names are exactly the material where errors persist. Butler et al. (2011) found that corrected errors mostly stay corrected immediately (86 %) but often come back after a week (only 56 % stayed corrected).\[6\]\[7\] Confusions need explicit tracking and an early re-test.
7. **Gamification helps a little, and the elements matter.** Sailer & Homner's 2020 meta-analysis found g = 0.49 on cognitive outcomes, 0.36 on motivation and 0.25 on behaviour, with effects that depend on which game elements are used.\[8\]\[9\] XP per answer rewards volume and easy answers. Reward cleared reviews and retained streets instead.
8. **No study tests learning a whole city's street names with an app.** The plan above combines strong general memory evidence with moderate spatial-cognition evidence and descriptive prior art. Its exact numbers are engineering assumptions to be checked with the self-experiment.

---

## 2. The evidence

### 2.1 Memory research

| Principle                          | What the evidence says                                                                                                                                                                                                                                                                                                                                                                                 | Strength                                                  | What it means for Pindoro                                                                                                                            |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Retrieval practice                 | Testing beats restudy, g = 0.50, 95 % CI 0.42–0.58 (Rowland 2014, 159 effects from 61 studies). Feedback roughly doubles the benefit (0.73 vs 0.39). Dunlosky et al. 2013 rate practice testing "high utility" because it "benefit[s] learners of different ages and abilities".                                                                                                                       | Strong (meta-analyses)                                    | Every exposure after the first should be a retrieval attempt (a pin or a recall), always followed by feedback.                                       |
| Spacing / optimal lag              | The optimal gap is a shrinking fraction of a growing retention interval: about 20–40 % for a test one week away, about 5–10 % for one a year away (Cepeda et al. 2008, 1,354 people; Cepeda et al. 2006 synthesis of 317 experiments). Dunlosky rates distributed practice "high utility".                                                                                                             | Strong                                                    | Use an expanding-interval scheduler whose intervals reach months, with no "graduate and never see again".                                            |
| Interleaving / discrimination      | Interleaving exemplars of similar categories improved later classification over blocking, while learners wrongly believed blocking worked better (Kornell & Bjork 2008; replicated by Birnbaum et al. 2013). Dunlosky rates it "moderate", because "the benefits of interleaving have just begun to be systematically explored".\[10\]\[11\]                                                           | Moderate                                                  | Interleave reviews across the city. Deliberately juxtapose confusable streets (siblings, same-name pairs) so you learn the differences between them. |
| Chunking / hierarchy               | Spatial memory is organised in regions (Stevens & Coupe 1978; Hirtle & Jonides 1985). Knowledge schools teach quarter-mile areas because they are "ideal for learning small areas … without overloading students" (Griesbauer et al.).\[3\]\[12\]                                                                                                                                                      | Moderate                                                  | Introduce streets in neighbourhood chunks and parent+lane families. Review them interleaved.                                                         |
| Elaboration                        | Elaborative interrogation is rated "moderate" (Dunlosky). Knowledge students use acronyms, stories, historical connections and personal memories for sequences of streets (Griesbauer et al.).\[3\]\[10\]                                                                                                                                                                                              | Moderate                                                  | Show meaning on the intro card: etymology, the parent street, crossing streets, direction from the centre. Keep it optional and short.               |
| Mnemonics (keyword, loci)          | The method of loci is powerful for ordered lists. In Dresler et al. 2017, mnemonics-naïve people trained 30 min/day for 40 days went from 26 to 62 words recalled, and were still about 22 words above baseline 4 months later. But Dunlosky rates the keyword mnemonic "low", since it "appears to benefit students for a limited number of materials and for short retention intervals".\[10\]\[13\] | Strong for lists, weak for thousands of paired associates | A street already _is_ a place, so loci add little. Offer a free-text mnemonic note only for leeches.                                                 |
| Error correction / hypercorrection | High-confidence errors are corrected readily after feedback (86 % on an immediate retest) but tend to return after a week (56 % corrected) (Butler, Fazio & Marsh 2011).\[6\]\[14\]                                                                                                                                                                                                                    | Moderate                                                  | After a miss: immediate feedback, a re-test later in the same session, and the next review the following day. Log confusion pairs.                   |
| Desirable difficulties             | Interleaving and spacing feel worse while you study yet produce better retention. Learners misjudge this (Kornell & Bjork 2008).\[11\]                                                                                                                                                                                                                                                                 | Moderate–strong                                           | Don't tune the system on how a session _feels_. Tune it on delayed test results.                                                                     |
| Recognition vs recall              | Recall-style tests produce larger testing effects than recognition (Rowland 2014 moderator analyses).\[15\]                                                                                                                                                                                                                                                                                            | Moderate                                                  | Three-option recognition is a scaffold at most. It never feeds the scheduler.                                                                        |

### 2.2 Spatial cognition

| Topic                      | Evidence                                                                                                                                                                                                                                                                                                                                  | Strength                                      | Implication                                                                                                                                                  |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Survey vs route knowledge  | Map learners are better at global relations and Euclidean distance; navigators are better at route distance and local orientation (Thorndyke & Hayes-Roth 1982). After enough exposure the two sources converge.\[1\]\[16\]                                                                                                               | Moderate (classic, replicated in VR)          | The pin trains survey knowledge. Driving and route call-outs train route knowledge. You need both.                                                           |
| Stage vs continuous models | Siegel & White proposed landmark → route → survey stages. Montello (1998) argues all three are acquired at once and improve continuously, with large individual differences.\[2\]\[17\]                                                                                                                                                   | Moderate (theory)                             | Questions about routes and orientation can start early for well-known areas. You don't have to "finish" the names first.                                     |
| Hierarchy and distortion   | Within-cluster distances are underestimated and between-cluster distances overestimated (Hirtle & Jonides 1985). Superordinate regions bend judgments, as in the classic Reno/San Diego error (Stevens & Coupe 1978).\[5\]                                                                                                                | Moderate                                      | Add orientation questions (bearing to a street from a known anchor) and cross-district interleaving. The Mtkvari bends are your Thames.                      |
| GPS dependence             | Among 50 drivers, more lifetime GPS use went with worse spatial memory in self-guided navigation. In an unplanned follow-up of 13 of those drivers after a mean of 3.2 years, more GPS use since baseline predicted a steeper decline (Dahmani & Bohbot 2020). A Cambridge review calls the domain-specific evidence "only suggestive".   | Weak–moderate (small n)                       | Your "drive without GPS" goal is reasonable, but the size of the effect is uncertain. Treat GPS-free driving as part of the training, not just the end test. |
| London taxi drivers        | 79 trainees and 31 controls were scanned over 3–4 years. Only those who qualified (39, just under half) showed growth in posterior hippocampal grey matter (Woollett & Maguire 2011). The training combines map study, travelling runs on a scooter, mental visualisation and subgoal planning (Griesbauer et al. 2022).\[3\]\[18\]\[19\] | Strong for "learnable"; descriptive for "how" | Learning a whole city is feasible for adults but takes years and fails often. Structure and daily consistency are what matter.                               |

### 2.3 Prior art

| System                                                    | What it does                                                                                                                                                                                                                                                                            | What works                                                                                                                                   | What doesn't                                                                                                                                                                                                                                           |
| --------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| London Knowledge (Blue Book, schools, call-overs)         | 320 runs in 20 lists of 16. Quarter-mile study around each origin and destination. Runs of 2–3 miles mostly on trunk and primary roads. Spaced oral "appearances" at 56-, 28- and 21-day intervals. Points and minor roads learned through quarter-miles from run 1 onward.\[3\]        | A main-road grid plus local areas. Layered coverage (four layers of 80 runs). Spaced, high-stakes recall. Recall _of sequences_ (call-outs). | Training "typically takes between 3 and 4 years", and only about half qualify: Woollett & Maguire (2011) report 39 of 79 trainees qualifying, a rate they give as 51.9 %, in line with PCO figures. It is far more than a 20-minute habit can deliver. |
| Knowledge apps (KPApp, KOL App, TheLTK, TNA Revision App) | Digital Blue Book runs, audio playback, quarter-mile revision, points quizzes. KOL App advertises a "points revision engine that increases the frequency of points that need more attention". TNA's app has a "dropped points" list. TheLTK uses XP and levels.\[20\]\[21\]\[22\]\[23\] | Adaptive repetition of weak points. Self-graded run calling.                                                                                 | Store descriptions only. No published evidence of efficacy.                                                                                                                                                                                            |
| Back of Your Hand (Adam Lynch)                            | Random street names in a circle on an OSM map; you pin each one. Same-name ways are merged ("I include all streets/segments with the same name, even if it's at the other side of the city").\[24\]                                                                                     | The same core move as Pindoro: it shows the pin-on-blank-map works.                                                                          | No memory model. Random sampling. HN players called it "luck-based" between main roads and three-house roads, and one got the same street 3 times out of 5 in a rural circle.\[25\]\[26\]                                                              |
| Name This Street                                          | Highlights a street and asks for its name. Has a spaced-repetition learning mode and per-street progress. Marketed to police recruits learning patrol areas.\[27\]\[28\]                                                                                                                | The place → name direction plus spacing.                                                                                                     | Seen only through its marketing pages. No efficacy data.                                                                                                                                                                                               |
| Anki Ultimate Geography                                   | Four templates (Country→Capital, Capital→Country, Flag→Country, Map→Country), plus an extended Country→Map.\[29\]                                                                                                                                                                       | Both directions as separate cards. Supplementary "similar flags" notes for confusables.                                                      | Users report leeches among similar items with one-way map cards.\[30\]                                                                                                                                                                                 |
| Duolingo half-life regression                             | A trainable forgetting model (Settles & Meeder 2016). It cut recall-prediction error by 45 %+ against baselines and raised daily engagement by 12 % in an operational test.\[31\]                                                                                                       | Shows that a per-item memory model beats fixed boxes (Leitner).                                                                              | Needs large multi-user training data, which you don't have.                                                                                                                                                                                            |
| Memory athletes                                           | Method of loci, 30 min/day for 40 days roughly doubled list recall (Dresler et al. 2017).\[32\]                                                                                                                                                                                         | Daily consistency and structured encoding.                                                                                                   | Built for ordered lists and short retention, not thousands of name↔place pairs.                                                                                                                                                                        |

---

## 3. The spec

### 3.1 Scope: which streets

- **Core (Phase 1): the 3,282 streets ≥ 150 m.** This is the curriculum and the denominator of every progress number.
- **Phase 2: the 1,183 streets under 150 m.** A neighbourhood's short streets unlock once ≥ 80 % of its core streets are Solid (defined in 3.7). Most are dead ends and lanes named after a parent, so they come cheap once the family is known. They add ~36 % to total time.
- **Assumption:** the user already knows ~130 streets (the 88 motorway/trunk/primary streets, the bridges and some majors). A placement test (3.4) confirms this rather than taking it on trust.
- **Assumption:** the same name in another place (377 names, up to ~10 places each) is a separate street. The plate always shows a disambiguating sub-line with the district, e.g. "Rustaveli St · Gldani".

### 3.2 Unit of learning

| Level                    | Definition                                                                                                                                                                                                      | Role                                                    |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| **Street card** (atomic) | One street = one name in one place (the pack's 4,465 units). It carries its own FSRS state per card type.                                                                                                       | Scheduling, grading, progress.                          |
| **Family**               | A parent street plus every "Nth Lane / Nth Dead End of X" whose parent is resolved by name and lies ≤ 1.5 km from the parent's geometry. Otherwise the family is flagged "orphan" and taught as single streets. | Introduction order, sibling drills, confusion handling. |
| **Chunk**                | A neighbourhood (68). The 849 streets in no quarter are assigned to the nearest neighbourhood by centroid; where neighbourhoods overlap, a street goes to the one holding most of its length.                   | Curriculum order, local progress.                       |
| **Tier**                 | Skeleton (motorway/trunk/primary) → Grid (secondary + tertiary) → Residential.                                                                                                                                  | Ordering, retention targets.                            |

**Card types per street:**

| Card                 | Question                         | Who gets it                               | When                                       |
| -------------------- | -------------------------------- | ----------------------------------------- | ------------------------------------------ |
| **P** (name → place) | The pin drop.                    | All streets.                              | At introduction. This is the primary card. |
| **N** (place → name) | Street painted; recall its name. | Skeleton, grid and parent streets (~800). | Once P reaches S ≥ 7 d.                    |
| **E** (extent)       | Pin both ends.                   | Streets > 1.2 km.                         | Once P reaches S ≥ 7 d.                    |

Card E fixes gap 7: on a 3 km avenue, one pin anywhere proves very little. N matters for reading the map in your head and for call-outs. It is not given to the ~1,500 lane/dead-end children, because their names are derivable from the parent.

### 3.3 Grading a pin into an FSRS rating

Drop the difficulty multipliers (×1.5 … ×0.5). Thresholds become absolute. Two numbers come from geometry:

- `d` = distance from the pin to the nearest point on the target's geometry.
- `snap` = the street whose geometry is nearest to the pin, searched among all streets within 150 m. It is null if none is that close.

`confusable(s)` = siblings in the same family, the parent, other streets with the same base name, and any street you have previously confused with this one (from the log).

| Condition (check in order)                                                                        | Display tier                 | FSRS rating                            |
| ------------------------------------------------------------------------------------------------- | ---------------------------- | -------------------------------------- |
| `snap` ∈ confusable(target) and `snap` ≠ target                                                   | "Wrong street: you placed X" | **Again (1)** + log the confusion pair |
| `d` > 100 m                                                                                       | Close / Miss                 | **Again (1)**                          |
| `d` ≤ 100 m, `snap` ≠ target (a non-confusable neighbour)                                         | Great                        | **Hard (2)**                           |
| `d` ≤ 100 m, `snap` = target, response time > 20 s                                                | Great / Perfect              | **Hard (2)**                           |
| `d` ≤ halfwidth(class) + 20 m, `snap` = target, RT ≤ 6 s, card already has ≥ 2 successful reviews | Perfect                      | **Easy (4)**                           |
| otherwise (`d` ≤ 100 m, `snap` = target)                                                          | Great / Perfect              | **Good (3)**                           |

Why "Close" counts as a failure: in a residential grid, 100–300 m is two or three streets away, so you would not find the street. Keep the Close tier on screen as feedback, since it is useful information, but it does not count as recall. **Card E:** each end is scored against `max(150 m, 10 % of length)`. Both ends inside → Good. One end inside → Hard. Neither → Again. **Card N** is self-graded: you recall the name, tap reveal, then grade it Forgot (Again) or Recalled (Good). Every tenth N review is verified instead by picking from 6 names that include the confusables.

### 3.4 Order: sequencing all ~3,300 streets

Precompute one **curriculum queue** per pack:

1. **Placement (day 1, ~15 min).** Pin every skeleton street, plus 5 random grid streets per district. A first-sight Good or Easy initialises the card as if rated Good or Easy (S0 = 2.31 d or 8.30 d), and FSRS confirms it at the next review. If ≥ 4 of a district's 5 sampled grid streets pass, sweep that district's remaining grid streets the same way. Failed and unseen streets enter the queue.
2. **Tier B, the grid (secondary 122 + tertiary 301 = 423 streets), city-wide.** Sort by ring (`floor(distance of the centroid from Freedom Square / 2 km)`), alternating river banks within each ring, then by length descending. This is Pindoro's Blue Book: city-wide coverage by main roads before local detail.
3. **Tier C, residential, by chunk.** Start with the chunk containing the centre and, if set, the chunks containing your **home and work anchors**. After that, always pick the unfinished chunk that borders the most completed chunks, breaking ties by distance to the centre. Coverage grows outward from what you know, as the Knowledge grows from run ends. Within a chunk, teach parent streets by length descending, then non-family streets by length, then the children of each family in numeric order.
4. **New-slot allocation:** while Tier B is unfinished, 60 % of each day's new slots go to B and 40 % to C (starting at home). After that, 100 % go to C.
5. **Sibling cap:** at most 4 new children of the same family per day, and never a child before its parent has reached S ≥ 3 d.

### 3.5 First exposure (fixing gap 2)

For each new street, in groups of 3 from the same chunk:

1. **Pretest when it is derivable.** If the parent is known, ask for a pin before showing anything ("Where is 26 May 4th Lane?"). Grade it but do not schedule it; it is a generation attempt. Errors corrected by feedback stick (hypercorrection).\[33\]
2. **Intro card (~15 s).** Show the street in yellow within its neighbourhood. Label only streets you have already learned (parent, crossings, neighbours). Also show the street's length, direction from the centre, number of crossings, `name:etymology` if present, and the name spoken by TTS in Georgian.
3. **Retrieval 1**, after 3–6 other items: a pin on a map zoomed to the district. This first graded answer sets S0(G) and D0(G).
4. **Retrieval 2**, at the end of the session: a pin on the whole-city map. It uses the FSRS-6 same-day update.
5. **Next review**, due by FSRS (about 2 days after a Good).

No street is "known" on the day it is introduced.

### 3.6 Scheduler: FSRS-6 (pure Dart, ~150 lines)

**Why FSRS over the alternatives:**

| Algorithm                               | Model                                                                                                                                                                           | Pros                                                                                               | Cons                                                                                                         | Verdict   |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ | --------- |
| Leitner (current Pit stop is a variant) | Fixed boxes, e.g. 1/3/7/21 d                                                                                                                                                    | Trivial to build                                                                                   | No probability, no long intervals, ignores how late a review is                                              | Reject    |
| SM-2                                    | Ease factor, starting at 2.5 (minimum 1.3); intervals 1, 6, then × EF\[34\]                                                                                                     | Simple, proven                                                                                     | "Never says how likely you are to remember a card", so it can't target a retention level or report one\[34\] | Reject    |
| HLR (Duolingo)                          | Trained half-life regression                                                                                                                                                    | Accurate at scale                                                                                  | Needs a large multi-user training set                                                                        | Reject    |
| **FSRS-6**                              | Difficulty, stability, retrievability; 21 weights whose published defaults are the per-parameter medians from running FSRS-6 on ~10,000 Anki collections (~727 million reviews) | Explicit recall probability, a retention target, handles late and early reviews, optimisable later | Defaults were fit to flashcards, not map pins                                                                | **Adopt** |

**Default weights** `w[0..20]` = `[0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542]`\[35\]

**Formulas** (G ∈ {1 Again, 2 Hard, 3 Good, 4 Easy}; t = days elapsed since the last review):

```
decay  = w[20];  F = pow(0.9, -1/decay) - 1
R(t,S) = pow(1 + F*t/S, -decay)
I(r,S) = S/F * (pow(r, -1/decay) - 1)            // next interval; I(0.9,S)=S
S0(G)  = w[G-1]
D0(G)  = clamp(w[4] - exp(w[5]*(G-1)) + 1, 1, 10)
D'     = D + (-w[6]*(G-3)) * (10-D)/9
D''    = clamp(w[7]*D0(4) + (1-w[7])*D', 1, 10)
// success (G>=2), review on a later day:
S'r    = S * (1 + exp(w[8]) * (11-D) * pow(S,-w[9]) * (exp(w[10]*(1-R)) - 1) * h * b)
         h = (G==2) ? w[15] : 1 ;  b = (G==4) ? w[16] : 1
// lapse (G==1):
S'f    = min(S, w[11] * pow(D,-w[12]) * (pow(S+1, w[13]) - 1) * exp(w[14]*(1-R)))
// same-day review:
S'     = S * exp(w[17]*(G-3+w[18])) * pow(S, -w[19]);  if (G>=2) S' = max(S', S)
```

**Parameters:**

| Parameter              | Value                                                                                                                                 | Note                                                                                                                                                                         |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Desired retention r    | **0.90** (all tiers at start)                                                                                                         | Anki's default. The Anki manual says "above 90% the workload increases very quickly". For S = 10 d, r = 0.85 gives a 19-day interval and r = 0.90 gives 10 days.\[34\]\[36\] |
| Auto-relief            | If 7-day mean session time > budget × 1.2, set r = 0.85 for Tier C only                                                               | Driving-critical grid streets stay at 0.90.                                                                                                                                  |
| Max interval           | 365 d                                                                                                                                 | Caps drift. Keeps a yearly touch on every street.                                                                                                                            |
| Fuzz                   | ±5 % on intervals > 3 d                                                                                                               | Stops reviews bunching up.                                                                                                                                                   |
| Relearning after Again | Re-test in the same session after 5–10 items, then FSRS (S'f is usually < 1 d, so it comes back the next day)                         | Fights returning errors.                                                                                                                                                     |
| Leech                  | lapses ≥ 6                                                                                                                            | Suspend, then re-introduce with an intro card, a confusion-pair contrast and an optional mnemonic note.                                                                      |
| Optimiser              | After ~1,000 reviews, export the log and fit the weights offline (py-fsrs/fsrs-rs on the home server). Load the new `w` into the app. | Optional. The logic stays on the phone.                                                                                                                                      |

With default weights and only Good answers, the intervals come out at about **2 → 12 → 50 → 174 → 526 days** (hand calculation from the formulas above with D0(3) ≈ 2.1). That is about 4 successful reviews in the first year.

**Per-street state** (one row per street × card type):

| Field                                            | Type                                             |
| ------------------------------------------------ | ------------------------------------------------ |
| `street_id`, `card_type` (P/N/E)                 | key                                              |
| `state`                                          | new / learning / review / relearning / suspended |
| `stability`, `difficulty`                        | double                                           |
| `last_review_at`, `due_at`                       | timestamp                                        |
| `reps`, `lapses`                                 | int                                              |
| `last_rating`, `last_distance_m`, `last_snap_id` | int / double / id                                |
| `prior_known`                                    | bool (from placement)                            |
| `intro_at`                                       | timestamp                                        |

**Review log** (append-only; required for the optimiser and the experiment): `ts, street_id, card_type, format, rating, distance_m, snap_id, rt_ms, elapsed_days, R_before, S_before, D_before, session_id`. **Confusion table:** `(street_a, street_b, count, last_at)`.

### 3.7 "Known" and "mastered", and the progress numbers

| Label             | Definition                                                                                                     |
| ----------------- | -------------------------------------------------------------------------------------------------------------- |
| Seen              | Introduced.                                                                                                    |
| **Known (today)** | At least one successful P review on a day after `intro_at`, **and** current R ≥ 0.80. It decays automatically. |
| **Solid**         | P stability ≥ 21 d.                                                                                            |
| **Mastered**      | P stability ≥ 90 d, last review a success, plus E (if it applies) and N (if it applies) each with S ≥ 21 d.    |

**Headline number:** _City memory_ = Σ R_i(now) over the 3,282 core streets (unseen = 0), shown as streets and as %. It means "streets you'd place correctly right now", and it drops if you stop. **Secondary numbers:** Solid and Mastered counts per district and chunk; **true retention** (share of the last 30 days' due reviews passed; it should sit near 0.90 — if it falls below 0.85, the grading or the weights are off); a 30-day due forecast; and an ETA at the current pace.

### 3.8 Question types

| Format             | Direction                                                             | Recall/recognition      | Scheduled?                                | When                                                                                      | Screen must show                                                                                                                                              | Feedback must show                                                                                                                                                                                                 |
| ------------------ | --------------------------------------------------------------------- | ----------------------- | ----------------------------------------- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Pin** (P)        | name → place                                                          | Recall                  | Yes (core)                                | From introduction                                                                         | Name in your chosen script + the other script as a sub-line + district disambiguator; blank map at city zoom (district zoom for retrieval 1 only); TTS button | Yellow true geometry in full; cobalt pin; ink line with metres; tier; **name of the street you actually hit** if snap ≠ target; parent and 2–3 known crossings labelled; for confusions, both streets side by side |
| **Name it** (N)    | place → name                                                          | Recall, self-graded     | Yes                                       | P S ≥ 7 d                                                                                 | Street painted on the blank map, neighbours unlabelled                                                                                                        | Name (both scripts) + TTS, parent, crossings                                                                                                                                                                       |
| **Extent** (E)     | name → both ends                                                      | Recall                  | Yes                                       | Long streets, P S ≥ 7 d                                                                   | Name; two pins in sequence                                                                                                                                    | Full geometry, both end errors                                                                                                                                                                                     |
| **Family sweep**   | place children                                                        | Recall + discrimination | Grades the due children                   | When ≥ 3 children of one family are due within 2 days                                     | Parent labelled; children's lines unlabelled; drag "1st…Nth Lane" labels onto them                                                                            | Correct mapping, misplaced pairs highlighted                                                                                                                                                                       |
| **Crossings**      | "Driving along X from A, name the streets you cross"                  | Recall (sequence)       | Not scheduled per item; one drill per day | Parent and grid streets once Solid                                                        | X labelled; junctions marked in order                                                                                                                         | Correct sequence; errors become confusion pairs                                                                                                                                                                    |
| **Orientation**    | "From [anchor], which way is X?" (drag a bearing)                     | Survey judgement        | No; 1–3 per session                       | Once a district's grid is ≥ 50 % Solid                                                    | Anchor (landmark or known square), compass                                                                                                                    | True bearing and error in degrees                                                                                                                                                                                  |
| **Call-out route** | A → B by choosing the next street at each junction from its crossings | Recall of a sequence    | Yes (each route is a card)                | Per district once ≥ 80 % of its grid is Solid; route book of ~120 points paired into runs | Origin and destination only                                                                                                                                   | Your route vs the A\* shortest (one-way aware once added); length excess %                                                                                                                                         |
| 3-option name      | place → name                                                          | Recognition             | **No**                                    | Only inside the intro, as scaffolding                                                     | —                                                                                                                                                             | —                                                                                                                                                                                                                  |

### 3.9 The daily session (algorithm)

```
budget = userMinutes*60
due    = cards where due_at <= now, sorted by R ascending
tReview = 12 s/item, tNew = 45 s/new street (both re-estimated from the log weekly)
if (due.length*tReview > budget) { nNew = 0; reviews = due.take(budget*1.5/tReview) }
else nNew = min(nBase, floor((budget - due.length*tReview)/tNew))
session = interleave( [3 new intros] , [5 reviews] , [retrieval 1 of those 3] , ... ,
                      [all retrieval 2s + same-session relearns at end] )
```

Defaults: `nBase` = 7 / 10 / 14 for 15 / 20 / 30 minutes. With a backlog, reviews come before new streets, as the Anki manual recommends: stop introducing new cards until the backlog is cleared.\[37\]

### 3.10 Workload maths

**Assumptions:** 12 s per review (pan, zoom, pin, ~3 s of feedback); 45 s per new street (intro + 2 retrievals); ~6.5 reviews per card in its first year (4 if all Good, plus lapses and relearning at a 10 % failure rate); after a year, ~1–2 reviews per card per year. Steady state while learning: daily time ≈ 45·N + 6.5·12·N ≈ 123·N seconds. The Anki manual's rule of thumb (20 new/day → ~200 reviews/day) implies a heavier ratio.\[37\]\[38\] If your pin reviews behave like that, cut N by ~25 %.

| Budget                         | New/day | Reviews/day at plateau | Core (~3,150 unknown) done in | All 4,465 (~4,335 unknown) done in | Maintenance after |
| ------------------------------ | ------: | ---------------------: | ----------------------------- | ---------------------------------- | ----------------- |
| 10 min (old plan's quiz share) |       5 |                    ~30 | ~21 months                    | ~29 months                         | ~3 min/day        |
| **15 min**                     |       7 |                    ~45 | **~15 months**                | ~21 months                         | ~3–4 min/day      |
| **20 min**                     |      10 |                    ~65 | **~10–11 months**             | ~14–15 months                      | ~4 min/day        |
| **30 min**                     |   14–15 |                    ~95 | **~7–8 months**               | ~10 months                         | ~4–5 min/day      |

**Maintenance estimate:** once mature (mean interval ~250 days), 3,282 cards ÷ 250 ≈ 13 reviews/day ≈ 3 min. N- and E-cards add ~1 min. **What this means:** the 16-week plan would need ~29 new streets a day, ~190 reviews a day and ~55 min/day for the whole core, so it cannot cover the whole city. Treat 16 weeks as "skeleton + grid + home districts" (~800–1,000 streets) and the full city as a 10–15-month project.

### 3.11 Gamification

| Element                           | Effect on learning                                                                               | Decision                                                                                                                                  |
| --------------------------------- | ------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------- |
| XP per answer, scaled by distance | Rewards volume and easy items. Free play on known streets farms XP. Disconnected from retention. | **Remove** as currency. Keep the Perfect/Great/Close/Miss tiers as feedback only.                                                         |
| Daily XP goal (250/500/1,000)     | Same problem.                                                                                    | **Replace** with "due cleared + today's new streets".                                                                                     |
| Streak + freezes                  | Supports the daily consistency that spacing needs. Risk of hollow minimum sessions.              | **Keep**, but a day counts only if the due queue was cleared (or the budget's minutes were spent). Keep freezes. Keep the 19:00 reminder. |
| Levels                            | Arbitrary.                                                                                       | **Replace** with City-memory milestones (500, 1,000 … streets with R ≥ 0.8).                                                              |
| Weekly leagues (XP)               | Competition on volume pushes cramming new cards, which creates review debt.                      | **Remove**, or replace with a cooperative friends board: each person's city memory % and mastered neighbourhoods, no ranking by activity. |
| Badges                            | Fine when tied to real milestones.                                                               | **Change**: a badge per neighbourhood or district reaching Mastered; "100-day maintenance"; "zero leeches".                               |

What to reward: cleared reviews, streets retained (Σ R) and neighbourhoods mastered. The meta-analytic gains from gamification are modest (g = 0.25–0.49), so it should not drive the design.\[8\]

---

## 4. Keep, change, remove

| Feature                       | Decision                     | Why / how                                                                                                                                                                                                                                                                                      |
| ----------------------------- | ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Free play**                 | **Keep, demote**             | Good for fun and checking an area. Every answer feeds FSRS: due or near-due cards update normally; a first-sight success on an unseen street initialises it like placement; failures on unseen streets are logged but not scheduled. Remove XP.                                                |
| **Difficulty (road classes)** | **Remove as a setting**      | Road class becomes curriculum tier. Remove the threshold multipliers; the absolute grading plus snapping in 3.3 replaces them. Keep a "class filter" in Free play only.                                                                                                                        |
| **Scoring tiers**             | **Change**                   | Keep the tiers for display. Map them to FSRS ratings by distance + snap + RT. Add a "wrong street" outcome.                                                                                                                                                                                    |
| **Path (course)**             | **Replace**                  | A 240-street ceiling and districts ordered nearest-first can't reach the goal. The new path is the curriculum queue (placement → grid → chunks), shown as chunk progress. Drop "Jump ahead"; you can re-anchor (home/work) instead.                                                            |
| **Lesson**                    | **Change**                   | Keep "can't fail", groups of 3 to 4 and the intro card (add parent, crossings, etymology, TTS). Add a pretest for family children. Remove "known after one answer" and the 3-option question as a counted item. Introductions are mixed into the daily session, not a separate 5-minute block. |
| **Road trip**                 | **Change, defer**            | Becomes the call-out route (choose the next street at each junction). It unlocks per district once ≥ 80 % of its grid is Solid. Add one-way data before it counts. Routes are FSRS cards drawn from your ~120-point route book.                                                                |
| **Final drive**               | **Replace**                  | Becomes a "district call-out": 3 routes, plus a suggested real GPS-free drive logged in the app.                                                                                                                                                                                               |
| **Pit stop**                  | **Remove (merged)**          | Reviews are no longer a separate mode; every street is scheduled in the daily session.                                                                                                                                                                                                         |
| **Known streets**             | **Replace**                  | Use the decaying Known / Solid / Mastered of 3.7, with Σ R as the headline. "Never reverts" goes.                                                                                                                                                                                              |
| **Daily habit**               | **Change**                   | Goal = due cleared + new streets. Keep the streak, freezes and reminder.                                                                                                                                                                                                                       |
| **Levels / leagues / badges** | **Remove / remove / change** | See 3.11.                                                                                                                                                                                                                                                                                      |

---

## 5. Self-experiment (3 weeks plus a delayed test)

**Question:** does the new loop (FSRS + graded pins + family intros) beat the current lesson loop per minute spent, and are the workload assumptions right?

**Design (within-subject):**

1. **Day 0, baseline.** Choose three unfamiliar neighbourhoods of similar size (~45–55 core streets each) in different districts, e.g. one in Isani, one in Saburtalo, one in Gldani. Pin-test every street in all three, and drop any you already know. Assign them at random to **A (new system)**, **B (current Path lessons + Pit stop)** and **C (control: no study, so it measures what you pick up from driving)**.
2. **Days 1–21.** 20 min/day, split roughly 12 min A and 8 min B. Log time per arm. A uses a minimal build: FSRS-6 with defaults, the 3.3 grading, the 3.5 intro, and a family sweep if a family exists. B runs the existing app unchanged.
3. **Day 21, test.** Pin-test every street in A, B and C on a city-zoom blank map with no hints. Add a place → name recall on 20 random streets per arm.
4. **Days 22–35:** no study of A or B.
5. **Day 35, delayed test.** Repeat the day-21 test. Then make 3 GPS-free drives that end on random streets in A and in B, and log any wrong turns.

**Metrics:** the share of streets with snap = target and d ≤ 100 m; median d; place→name accuracy; **streets retained at day 35 per hour spent**; seconds per review and per new street (to check 3.10's assumptions); and FSRS calibration (bin A's reviews by predicted R and compare with the observed pass rate; ±5 pp is fine).

**Decision rule:** build the full system if A's day-35 retained-per-hour is ≥ 1.5× B's and calibration is within ±7 pp. If calibration is off, adjust the grading thresholds (3.3) before changing r. If seconds per review are > 15, revise the N values in 3.10 down in proportion.

**Data check before day 0:** run a script on the pack to measure what share of "Nth Lane/Dead End of X" streets lie ≤ 500 m and ≤ 1.5 km from X. The family design assumes most do.

---

## 6. Risks and open questions

| Risk / question                              | Why it matters                                                                        | Mitigation                                                                                    |
| -------------------------------------------- | ------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| FSRS defaults fit flashcards, not pins       | Intervals may be too long or too short for spatial items.                             | Watch true retention; refit the weights offline after ~1,000 reviews.                         |
| Grading thresholds are invented              | 100 m / 20 s / 6 s are judgment calls.                                                | Calibrate in the experiment; log raw distance and RT so you can re-grade history.             |
| Sibling interference (1,552 lanes/dead ends) | Could produce leeches in bulk.                                                        | Parent first, max 4 siblings per day, family sweeps, the confusion table, a pretest.          |
| Duplicate names (377)                        | The pin may land on the "other" Rustaveli.                                            | District sub-line on the plate; same-name streets in the confusable set.                      |
| Motivation over 10–15 months                 | Most long projects fail on consistency, as about half of Knowledge trainees do.\[18\] | Small daily budget, streak on cleared reviews, visible decaying memory number, friends board. |
| Transfer to driving                          | Map knowledge ≠ route knowledge.                                                      | Call-outs, crossings drills, GPS-free drives logged.                                          |
| Pack updates (renames, re-merges)            | Per-street state could orphan.                                                        | Stable street IDs across pack versions (match by name + geometry overlap); migrate state.     |
| Phone map precision                          | Fat-finger error on dense lanes at city zoom.                                         | Snap test plus allowing zoom; the measured RT will show the cost.                             |
| Short streets (<150 m) worth it?             | +36 % time for low driving value.                                                     | Phase 2 per chunk; decide after Phase 1.                                                      |
| Open: is 0.90 right for residential?         | Lower retention = less work but more lapses.                                          | Experiment, then the Tier C auto-relief rule.                                                 |

**Evidence caveat:** no controlled study tests app-based learning of a whole city's street names. The scheduler and curriculum rest on strong general memory research, moderate spatial-cognition research and descriptive prior art. Some sources were seen only as abstracts or summaries, not opened in full: Rowland 2014, Thorndyke & Hayes-Roth 1982, Hirtle & Jonides 1985, Stevens & Coupe 1978, Montello 1998, Kornell & Bjork 2008, Butler et al. 2011, Sailer & Homner 2020, Settles & Meeder 2016, Dahmani & Bohbot 2020, the Knowledge app store pages and Name This Street. The figures above are as their abstracts report them. Opened in full: the FSRS algorithm wiki, the Taalhammer FSRS explainer, the Anki manual's deck options, Griesbauer et al.'s Knowledge study (preprint), Adam Lynch's Back of Your Hand write-up, Dunlosky et al. 2013 and the Cell Press release on Dresler et al. 2017. Your earlier "Learning Every Tbilisi Route" doc could not be opened, so this report relies on the summary in your brief.

## Sources

1. [When to look at maps in navigation: metacognitive control in environment learning - PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC6156696/)
2. [Using a picture (or a thousand words) for supporting spatial knowledge of a complex virtual environment - PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC10368603/)
3. <https://www.biorxiv.org/content/10.1101/2021.06.04.447168.full.pdf>
4. [Perception of Space by Multiple Intrinsic Frames of Reference](https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0010442)
5. [The Number, Type, and Configuration of Landmarks Distort Distance Estimates](https://escholarship.org/content/qt8970w3d9/qt8970w3d9_noSplash_3d34434ee135b1e8e3d40b0ea53241ab.pdf?t=op2m8a)
6. [New Insights Into How to Correct False Knowledge](https://today.duke.edu/2012/02/hypercorrection)
7. [New insights into how to correct false knowledge](https://phys.org/news/2012-02-insights-false-knowledge.html)
8. [ERIC - EJ1245270 - The Gamification of Learning: A Meta-Analysis, Educational Psychology Review, 2020-Mar](https://eric.ed.gov/?id=EJ1245270)
9. [Does Gamified Learning Actually Work?](https://www.cogn-iq.org/blog/gamified-learning/)
10. <https://www.whz.de/fileadmin/lehre/hochschuldidaktik/docs/dunloskiimprovingstudentlearning.pdf>
11. [Why interleaving enhances inductive learning: The roles of discrimination and retrieval](https://link.springer.com/article/10.3758/s13421-012-0272-7)
12. [Cognitive maps for hierarchical spaces in the human brain](https://academic.oup.com/cercor/article/35/9/bhaf261/8261489?login=false)
13. [Super-sized memory is trainable and long lasting](https://www.sciencedaily.com/releases/2017/03/170308131236.htm)
14. [scholars.duke.edu](https://scholars.duke.edu/publication/736161)
15. [https://www.ebi.ac.uk/europepmc/ ...](https://www.ebi.ac.uk/europepmc/webservices/rest/PMC12894256/fullTextXML)
16. [Different “routes” to a cognitive map: Dissociable forms of spatial knowledge derived from route and cartographic map learning - PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC4169750/)
17. [Introduction](https://www.frontiersin.org/journals/human-neuroscience/articles/10.3389/fnhum.2019.00240/xml)
18. [How acquiring The Knowledge changes the brains of London cab drivers](https://www.nationalgeographic.com/science/article/acquiring-the-knowledge-changes-the-brains-of-london-cab-drivers)
19. [Changes in London taxi drivers' brains driven by acquiring 'the Knowledge'](https://www.sciencedaily.com/releases/2011/12/111208125720.htm)
20. [TheLTK App - App Store - Apple](https://apps.apple.com/gb/app/theltk-app/id6755438731)
21. [KPApp - App Store - Apple](https://apps.apple.com/gb/app/kpapp/id6478486962)
22. [Free Taxi Now Knowledge school prepares to launch with all 320 Blue Book runs and more than 90 students signed up](https://www.taxi-point.co.uk/post/free-knowledge-school-prepares-to-launch-with-all-320-blue-book-runs-and-more-than-90-students-signe)
23. [Blue Books — KnowledgeOfLondon.co.uk](https://www.knowledgeoflondon.co.uk/bluebooks)
24. [Introducing Back Of Your Hand](https://adamlynch.com/back-of-your-hand/)
25. [Hi HN, I made Back Of Your Hand, a map-based game where you're given random stre...](https://news.ycombinator.com/item?id=30733344)
26. [Show HN: A game that tests how well you know your local area](https://news.ycombinator.com/item?id=30733339)
27. [Name This Street](https://makewithmaplibre.com/products/name-this-street/)
28. [Learn Your Patrol Area Streets](https://solutionsagiles.ca/learn-streets-police-officer/)
29. [GitHub - anki-geo/ultimate-geography: Geography flashcard deck for Anki · GitHub](https://github.com/anki-geo/ultimate-geography)
30. [Ultimate Geography v5.3 - AnkiWeb](https://ankiweb.net/shared/info/2109889812)
31. [Table 3 from A Trainable Spaced Repetition Model for Language Learning](https://www.semanticscholar.org/paper/A-Trainable-Spaced-Repetition-Model-for-Language-Settles-Meeder/cb836d2b8e126dc31ded5e674d73021604dcc6e0/figure/5)
32. [Method of Loci Technique: How To Create A Memory Palace - PsyBlog](https://www.spring.org.uk/2023/01/method-of-loci-memory-palace.php)
33. [The hypercorrection effect persists over a week, but high-confidence errors return](https://link.springer.com/article/10.3758/s13423-011-0173-y)
34. [How FSRS Works: The Spaced Repetition Algorithm Explained](https://www.taalhammer.com/how-fsrs-works/)
35. [The Algorithm](https://github.com/open-spaced-repetition/awesome-fsrs/wiki/The-Algorithm)
36. [Deck Options - Anki Manual](https://docs.ankiweb.net/deck-options.html?highlight=learning)
37. <https://docs.ankiweb.net/deck-options.html>
38. [Best Anki Settings 2026: FSRS, Learning Steps and New Cards](https://studycardsai.com/blog/anki-settings-guide)
