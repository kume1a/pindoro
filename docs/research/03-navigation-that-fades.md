# Navigation that fades: designing in-app car guidance that teaches Tbilisi and then gets out of the way

## Recommendation

Build the feature, but fade guidance per decision, not per route, and keep all active learning out of the moving car: the best evidence (Brügger, Richter & Fabrikant 2019; Parush, Ahuvia & Erev 2007; Münzer et al. 2006; Ishikawa et al. 2008) says spatial learning suffers when the system does the self-locating and attention-allocating for the driver, and improves when the driver has to do that work, so Pindoro should give voice help only at decisions the driver has not yet shown they know, stay silent elsewhere, step in only when a decision fails, and put every question, rehearsal and quiz before the drive (a 60–90 s north-up route preview) or after it (a debrief within the same day). Turn the three levels into four (Guided → Coached → Quiet → Off), where the new Coached level speaks only at decisions that are not yet Known, using a landmark-first cue with no question and no answer required. In Quiet, show no map and no route: only a dark screen with a heading arrow, the district name and a small status dot; the map appears only during a recovery. Count a correct, unprompted decision in Quiet or Off as a successful FSRS review (Good, or Hard if hesitant), but only when the card is due or close to due, at most once per card per day, and not repeatedly on a habitual commute. In Georgia, a phone in a holder used without touching it, with voice through the car's audio, fits the hands-free exception in the Law on Road Traffic; touching it while moving does not, and the fine rose to 50 GEL on 1 May 2026, so the design must need no touches while the car moves.

## TL;DR

- **Fade per decision, not per route.** A route is a set of J cards; each decision gets its own help level from its FSRS state. Suggest the route level from the share of "silent-eligible" decisions (Known, retrievability ≥ 0.85, no failure in 14 days): ≥ 90% → Off, ≥ 70% → Quiet, ≥ 40% → Coached, else Guided.
- **Add a fourth level.** Guided (every decision, landmark-first voice, heading-up map) → Coached (voice only at not-yet-Known decisions, cue without a question) → Quiet (error-triggered only, no map) → Off (GPS-free). Evidence for each step is pedestrian/VR-heavy; validate in the drive log.
- **No questions while driving.** A "Which way?" prompt is an auditory-vocal retrieval task in the hardest part of driving (the approach to a junction). Strayer's AAA work rates even listening-only voice tasks near phone-conversation workload. Put active retrieval in a pre-drive preview and post-drive debrief instead.
- **Quiet screen = heading, district, status.** No route line, no next-turn arrow, no street labels, no map. North-up maps build survey knowledge better than heading-up ones (Rizzardo & Colle 2013), so use north-up maps in preview and review, and heading-up only for Guided and for recoveries.
- **Credit unprompted successes, carefully.** Correct unaided decision → Good (Hard if a hesitation was flagged within 150 m before the junction), only if the card's retrievability ≤ 0.92, max once per card per day, max once per card per 7 days on a habitual corridor. Guided decisions: logged as exposure only.
- **Safety and law.** Zero touches while moving; single glances under 2 s and no task needing more than 12 s total eyes-off-road (NHTSA); text cap height ≥ 6 mm at 60–80 cm; contrast ≥ 3:1 by day and ≥ 5:1 at night (ISO 15008:2017); a dark, dim night theme.
- **Habit.** Keep "2 GPS-free trips a week" as the floor, add "1 new destination a week", count weeks not days, and let one missed week pass without penalty (Lally et al. 2010).

## Key findings

| #   | Finding                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | Evidence strength                                                 |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| 1   | When the navigation system automates self-localisation and attention to landmarks, people cannot reverse the route as well; making users tag their own landmarks cut route-reversal errors (3 of 16 users erred, vs 6 and 10 of 16 in the more automated groups) with no cost to the assisted walk (Brügger, Richter & Fabrikant 2019, 64 participants, 14 intersections, Zurich).\[1\]                                                                                                       | Moderate (one real-world pedestrian study, low error counts)      |
| 2   | GPS-guided wayfinders travel further, stop more and draw poorer sketch maps than map users or people who walked the route with a guide (Ishikawa et al. 2008, 66 pedestrians).\[2\]\[3\] Navigation-system users build good route memory but poor survey knowledge (Münzer et al. 2006).\[4\]                                                                                                                                                                                                 | Strong for the direction of effect; pedestrian-only               |
| 3   | Orientation information (global landmarks, regions, structure) in instructions improves survey knowledge (sketch maps, pointing) without harming wayfinding (Schwering et al. 2017; Löwen, Krukar & Schwering 2019); local features support route knowledge, global features support survey knowledge.\[4\]\[5\] A virtual-reality study by Kuo, Chang & Chu (2022) found that "orientation-based guidance yielded poor navigation performance, similar to the turn-by-turn navigation aids." | Moderate, partly conflicting                                      |
| 4   | North-up maps support configural (survey) learning; track/heading-up maps support immediate turn decisions and cardinal-direction judgements (Rizzardo & Colle 2013, virtual driving, N = 96 and 192; aerial navigation study in Human Factors, PubMed 22908682).\[6\]\[7\] Forward-up users catch up with practice (time-course study 2023).\[8\]                                                                                                                                            | Moderate (simulator/VR)                                           |
| 5   | Good landmarks in driver instructions improve navigation and reduce glances compared with distance-to-turn (May & Ross 2006, road trial, 48 drivers; Burnett 1998, 2000). Traffic lights are the most-used driver landmark.\[9\]                                                                                                                                                                                                                                                              | Strong for drivers                                                |
| 6   | Navigation aids impair spatial memory largely by dividing attention (Gardony et al. 2013, 2015).\[10\]                                                                                                                                                                                                                                                                                                                                                                                        | Moderate (VR)                                                     |
| 7   | Voice interactions are not "free": listening to voice messages rated about category 2 on Strayer's 5-point cognitive distraction scale (≈ a phone conversation), composing replies category 3; OEM voice systems averaged 3.34 (range 2.37–4.57) (Strayer et al. 2013–2017, AAA Foundation).\[11\]                                                                                                                                                                                            | Strong                                                            |
| 8   | NHTSA's visual-manual guidelines: single glances ≤ 2 s, total eyes-off-road ≤ 12 s per task, met by 85% of test drivers; the 2016 proposed Phase 2 extended the same limits to portable devices.\[12\]\[13\]                                                                                                                                                                                                                                                                                  | Strong (as a design standard, voluntary)                          |
| 9   | ISO 15008:2017 minimum symbol/background contrast: 5:1 night, 3:1 twilight, 3:1 day, 2:1 direct sunlight; legibility literature recommends characters of about 20–24 arcmin (≈ 4.9 mm cap height at 70 cm).\[14\]                                                                                                                                                                                                                                                                             | Strong (standard)                                                 |
| 10  | In Georgia, the Law on Road Traffic forbids using a mobile communication device while driving unless the driver uses an earpiece or loudspeaker function and both hands stay free for driving; Article 118² of the Code of Administrative Offences sets the fine, raised to 50 GEL from 1 May 2026.\[15\]\[16\]                                                                                                                                                                               | Strong (primary law), with interpretation gaps for screen viewing |
| 11  | The "assistance dilemma": too much help hurts learning, too little causes floundering; the right amount depends on the learner's current state (Koedinger & Aleven 2007). No study gives navigation-specific thresholds.\[17\]                                                                                                                                                                                                                                                                | Moderate (general); thresholds are Expert judgement               |
| 12  | Habits form over a median of 66 days (range 18–254) and a single missed opportunity did not materially affect habit formation (Lally et al. 2010, 96 participants).\[18\]                                                                                                                                                                                                                                                                                                                     | Moderate                                                          |
| 13  | London Knowledge students learn ~25,000 streets and 320 runs over about 3–4 years by reciting routes in spaced oral exams; only 39 of 79 trainees in Woollett & Maguire 2011 qualified.\[19\]\[20\]\[21\] No Knowledge app or street-quiz app has a published evaluation.                                                                                                                                                                                                                     | Strong (descriptive); Weak for app efficacy                       |
| 14  | Repeatedly following route guidance did not hurt route knowledge compared with testing from memory with feedback (Sjolund & Kelly 2021, retested after 48 hours); in five virtual-building experiments, testing beat studying only when feedback came before the move, and feedback after a wrong move made performance worse than studying (Kelly, Carpenter & Sjolund 2015).                                                                                                                | Weak–Moderate (lab, pedestrian)                                   |

## Q1. Fading assistance: what to fade, and the ladder

**What the evidence says.**

- _Automation level matters more than modality._ Brügger et al. (2019) varied who did two jobs: locating yourself (always-on blue dot vs a "GPS on" button showing the dot for 10 s) and allocating attention to landmarks (system pushes a landmark vs the user tags three landmarks of their choice). All groups walked the assisted route equally fast with zero errors. On the unaided reversal, errors were 18% in both self-tagging groups, 37.5% with system landmarks + always-on dot, and 62.5% with system landmarks + on-demand dot, whose users pressed "GPS on" a median of 14 times.\[1\] Lesson: on-demand help alone does not make people learn; they simply ask for it often. What helped was a task that made them attend to the environment.
- _Quizzing during navigation._ Parush, Ahuvia & Erev (2007) built the original "where are you?" quiz into a navigation aid and argued that constant position display makes users "mindless" of the environment.\[1\]\[22\] The full text was not re-checked for this report; treat the direction as plausible but the size as unknown.
- _Orientation and landmark content._ Landmark-based instructions improve incidental learning (settled). Orientation information (global landmarks, districts, direction) adds survey knowledge (Schwering et al. 2017; Löwen et al. 2019), though a virtual-reality study (Kuo, Chang & Chu 2022) found orientation-based guidance gave poor later navigation performance, similar to turn-by-turn. Treat orientation cues as useful but not proven for driving.
- _Error-triggered help._ No controlled study tests a "silent until you go wrong" car navigator. The closest is the Iowa State route-learning work: in Sjolund & Kelly (2021), testing from memory with corrective feedback was no better than following guidance for route knowledge, and in Kelly, Carpenter & Sjolund (2015) testing improved route memory only when feedback about the correct choice came before moving, while feedback after a wrong move made performance worse than studying. Implication: Quiet's recovery voice should fire as soon as a wrong move is detectable, and Pindoro should help just before a likely error (Coached) at decisions the driver does not yet know.
- _Fading in instruction._ Faded worked examples and the expertise-reversal effect (Renkl; Kalyuga) say guidance that helps novices becomes redundant and even harmful for people who already know the material. That supports fading per decision: a Known decision that still gets a voice prompt is redundant help.

**Is the three-level ladder right?** Mostly, but the jump from Guided (every decision) to Quiet (error-triggered only) is too big for a route where half the decisions are Known. Use four levels and apply them per decision:

| Level         | Voice                                                                                                                                                 | Screen                                              | FSRS effect                                             |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- | ------------------------------------------------------- |
| Guided        | Every decision, landmark-first, plus one confirmation after each turn                                                                                 | Heading-up map, route line, labels, north indicator | Exposure only                                           |
| Coached (new) | Only at decisions not silent-eligible; cue without question ("At Vake Park, left onto Chavchavadze"); silent at Known decisions; recovery as in Quiet | Quiet screen                                        | Prompted decisions: exposure; unprompted ones: evidence |
| Quiet         | Silent; recovery voice when a decision fails until back on a good path                                                                                | Quiet screen (no map)                               | Unprompted decisions: evidence                          |
| Off           | None                                                                                                                                                  | Recording indicator only                            | Evidence                                                |

Do not add separate "landmark-only" or "orientation-only" levels: those are content choices, used inside Guided and Coached, not steps on the ladder. A "confirm-only" mode (silent unless asked) repeats Brügger's on-demand failure, and asking would need a touch, so leave it out.

## Q2. What the screen should show

**Evidence.** North-up displays give better configural knowledge; track-up gives easier turn decisions and better cardinal-direction judgements. Rizzardo & Colle (2013) found that with glance-limited viewing, a north-up display with a spatial + verbal turn indicator still produced spatial learning, while track-up did not even with long glances.\[6\] Whole-route views help survey knowledge (Ishikawa et al. 2008 attribute part of the GPS deficit to piecemeal, dynamically updated views).\[23\] Every glance at the screen is time not spent on the road and on landmarks (Gardony et al.).\[1\]

**Rules.**

- _Pre-drive preview (parked):_ north-up, whole route, district names, the 3–7 key decisions highlighted with their landmarks. This is where the survey picture gets built.
- _Guided (moving):_ heading-up map for safety and easy turn decisions, with a fixed north arrow, district names and the route line. Show the current and next street names only. No traffic, POIs or clutter.
- _Coached and Quiet (moving):_ no map, no route line, no next-turn, no street labels. Show: (1) a heading arrow with the cardinal letter (e.g. "N"), (2) the current district name in large type (e.g. "Vake"), (3) a small status dot (green = on a good path; amber = recovery active). Dark background. This gives orientation information (which supports survey knowledge) without giving the answer to any card. Do not show the current street name in Quiet: street names are a tested card type, and the screen would answer it.
- _Recovery (in Coached or Quiet after a failure):_ switch to heading-up, next-turn arrow + the street to turn into, until the driver is back within 1.25× of the best route; then fade back to the Quiet screen after 10 s on a good path.
- _Off:_ black screen with a small "recording" indicator. Screen stays on only so the OS keeps the recording alive.
- _Post-drive review (parked):_ north-up, whole track over the best route, each decision coloured.

## Q3. Voice content, order and frequency

**Evidence.** Drivers navigate better and glance less with good landmarks than with distance-to-turn (May & Ross 2006; Burnett 1998, 2000); good landmarks are permanent, visible, at the decision point, and unique.\[24\]\[25\] Street names are used infrequently as cues and need sign-reading.\[26\] Orientation cues aid survey knowledge (Schwering).\[4\] Voice prompts carry a real cognitive cost (Strayer), so fewer, shorter prompts are better.\[27\]

**Rules.**

- _Order:_ landmark → action → street name. "At Vake Park, turn left onto Chavchavadze Avenue." Distance only when no good landmark exists within 50 m of the junction ("In 200 metres, turn left onto …"). Traffic lights count as a landmark ("At the lights, …").
- _Timing (urban, ≤ 70 km/h):_ one prepare prompt at max(150 m, 10 s) before the junction; one action prompt at max(40 m, 4 s). In Coached, only the prepare prompt unless the driver already passed the last point at which the correct lane can safely be reached. Never more than 2 prompts per decision.
- _Confirmation:_ in Guided, one confirmation 5–10 s after each completed turn: "Chavchavadze Avenue, heading west." In Coached/Quiet, no confirmations (silence is the confirmation; the status dot stays green).
- _District/cardinal cues:_ "Into Vake, heading north" when crossing a district boundary, at most once per 2 km and once per 3 minutes, in Guided and Coached only. In Quiet, the screen carries this.
- _Length:_ ≤ 3 s of speech per prompt; ≤ 8 words except when the street name is long.
- _Language:_ say street names the way locals say them (Georgian pronunciation), because recognition of signs and of local speech is the real-world target.
- _Does hearing names help the street-name curriculum?_ Plausibly a little, as incidental exposure paired with the place, but evidence is thin; the settled finding is that names are poor driving cues. Log name exposure per card (see "What to log") and check whether exposed-but-unreviewed name cards have higher first-review success than unexposed ones.

## Q4. Active learning while driving: almost nothing in the car

**Evidence.** Glance limits are 2 s single and 12 s total per task (NHTSA). Auditory-vocal tasks cost cognitive workload: listening to messages is about category 2 on Strayer's scale, composing a spoken reply category 3, and OEM voice systems averaged 3.34; the AAA studies also found workload stays raised for a while after a voice task ends.\[28\]\[29\] Retrieval ("which way?") is effortful by design: that effort is the learning mechanism and also the distraction. The approach to a junction is the highest-workload moment of urban driving (lane choice, pedestrians, signals). No study shows a safe in-car quiz protocol.

**Judgement.** A "Which way?" question with the answer revealed seconds later should not ship. It invites an answer (a spoken reply is category ~3), it times retrieval to the riskiest moment, and the reveal adds a second prompt. The safer equivalent is Coached's _cue without a question_: the landmark is named well before the junction and the driver acts; no answer is invited, and correctness is judged from the track. If you ever experiment with an explicit anticipation cue ("Next decision: Vake Park"), apply all of these: only in Coached; ≥ 300 m and ≥ 20 s before the junction; speed ≤ 60 km/h; no other junction within 150 m; no recovery active; never two in a row within 60 s; no answer expected; off by default.

**Before the drive (parked, 60–90 s):** north-up whole-route preview; play the route fine-to-coarse; then ask the driver to recite the key decisions aloud or tap them (retrieval with immediate feedback). Mental rehearsal of the route is cheap and safe.

**After the drive (same day, ideally within 1 hour; review prompt on arrival):** replay the track against the best route; for each decision, first ask the driver to recall what they did and what they should have done, then reveal (retrieval with feedback). Failed decisions get a short drill (the J card plus its landmark). Add one pointing question at the destination while parked ("Point to home") as a survey-knowledge probe.

## Q5. When to suggest less help: numbers

**Basis.** The assistance dilemma (Koedinger & Aleven 2007) says help should depend on the learner's current state; desirable-difficulty work (Bjork) supports making retrieval effortful but successful.\[17\] FSRS at desired retention 0.90 already targets ~90% success. Navigation-specific thresholds do not exist; the values below are expert-judgement defaults to tune.

**Per decision (computed at route start, refreshed after each decision):**

- _Silent-eligible:_ card Known AND retrievability R ≥ 0.85 AND no failure (in-app or in-drive) in the last 14 days.
- _Coach:_ anything else.

**Per route suggestion (share S of silent-eligible decisions; min R over decisions):**

- Off: S ≥ 0.90 AND min R ≥ 0.75 AND at least one Quiet drive on this route (or 80% route overlap) with ≤ 1 recovery.
- Quiet: S ≥ 0.70.
- Coached: S ≥ 0.40.
- Guided: S < 0.40, or the destination area has fewer than 5 introduced J cards.

**Hysteresis.** Suggest one level less help only after 2 consecutive drives at the current level with stretch ≤ 1.25 and ≤ 1 recovery. Suggest one level more help after 2 drives at the level with stretch > 1.60 or ≥ 3 recoveries. Never move more than one level at a time. The driver can always pick more help; picking less help than suggested is allowed for at most one step.

**In-drive frustration guard (automatic, no touch).**

- 2 recoveries within 5 minutes, or a cumulative 3 minutes of added drive time vs the best route → switch the rest of the drive to Coached and say so once ("I'll guide the tricky turns for the rest of this drive").
- 3 recoveries in a drive at Coached → switch to Guided.
- In Off: no voice, by design. Offer a parked "Rescue" action: stop, tap once, get Guided to the destination; the drive is logged as "rescued" and decisions after the rescue are excluded.

**Target.** Aim for 80–90% unaided-correct decisions per drive. If the rolling median over 5 drives is above 95%, the ladder is too cautious: lower the Off threshold S to 0.85. If below 75%, raise thresholds by 0.05.

## Q6. Drive evidence into FSRS

**Should a correct unprompted decision count as a success?** Yes, with guards. A real-world retrieval that the driver acted on is a stronger test than a flash card (the testing effect works on retrieval, and here retrieval had consequences). Counting only failures biases intervals downward for cards that are reviewed in real life often.

**Rules.**

- Credit only decisions taken at Coached-silent, Quiet or Off, with no prompt for that decision and no recovery active within the previous 60 s.
- Grade: correct with no hesitation flag within 150 m before the junction → Good; correct with a hesitation flag → Hard; wrong (illegal or outside 1.25×) → Again (as today). Never Easy.
- Credit only if the card's current R ≤ 0.92 (due or close to due); otherwise log as "exposure, not reviewed". This avoids inflating stability with trivially easy, too-early reviews.
- At most one credited review per card per calendar day (keep the first; later failures that day still count).
- _Habitual corridors:_ if a J card has been passed ≥ 3 times in 14 days in the same direction, credit at most one success per 7 days; failures still always count.
- _Direction and viewpoint:_ route knowledge is strongly direction-dependent, so J cards must remain direction-specific (arrive on X at Y). Never credit the reverse direction from a forward success. When a habitual route is overlearned in one direction, schedule its reverse-direction J cards for introduction (they are new cards, not reviews).
- _Guided decisions:_ no credit, no penalty; log as exposure. A wrong move while Guided is logged as a "followed-guidance error", not a memory failure.
- _Recovery decisions:_ decisions made while the recovery voice is active are exposure only.

## Q7. Personal routes vs road-class order

**Evidence.** Memory benefits from self-relevance (the self-reference effect) and from matching learning and use contexts (encoding specificity; context-dependent memory). Practising on routes the driver will actually drive also gives free real-world retrieval (Q6). The risk is a city map made of a few corridors.

**Rule.** Cap personal pull-forward at 25% of new cards per day. A junction qualifies for pull-forward if it lies on a route driven ≥ 2 times in the last 14 days, or on the home/work route. When pulling forward a junction, also introduce the main road(s) it connects to, if not already introduced, so the personal card hangs on the skeleton. The remaining ≥ 75% follows strict road-class order. Measure: compare first-month retention of pulled-forward cards vs road-class cards and city coverage growth; if coverage growth falls below 80% of the pre-feature rate, lower the cap to 15%.

## Q8. Drive-log metrics and progress display

**Measures, ranked by validity for "can drive any A→B without GPS":**

1. _Unaided decision accuracy_ (share of decisions correct without a prompt, at Coached/Quiet/Off). Most direct; already graded per decision.
2. _Route stretch_ on Off drives (≤ 1.03 Perfect … as in recitals). Good summary; sensitive to closed roads and traffic, so use the median of 5.
3. _New destinations reached at Off_ (distinct destination cells, e.g. 300 m grid, first reached GPS-free). Best measure of transfer.
4. _Recoveries per 10 km_ (Quiet/Coached). Direct measure of help needed.
5. _U-turns per 10 km._ Good error signal, low noise.
6. _Hesitations per 10 km._ Noisy (traffic, parking searches); report only as a trend.
7. _Pointing error_ at destination (parked, "point to home"): the standard survey-knowledge measure in wayfinding research; collect once per new destination.

**Display without XP.** Competence feedback, not points: (1) a north-up city map that fills in as J cards and streets become Known, coloured by road class; (2) per frequent route, the current ladder level and its history ("Home → Work: Guided in March, Off since June"); (3) a weekly line: "This week: 3 drives without help, 1 new place, 92% of decisions on your own." Keep the Perfect/Great/Close/Miss tiers for drives. No streaks that reset.

## Q9. Habit

**Evidence.** Habit automaticity grows over a median 66 days, with wide variation, and one missed opportunity did not derail it (Lally et al. 2010).\[30\] Implementation intentions ("when I drive to X on Saturday, I'll go GPS-free") reliably increase follow-through.

**Rules.**

- Weekly floor: 2 Off drives per week (keep). Add: 1 drive per week to a destination never reached at Off.
- Count weeks, not days. One missed week does not break anything; show "back on track" after a miss, never a reset.
- Planning: on Sunday evening (or the user's chosen day), offer one implementation-intention prompt: pick the two drives this week that will be Off.
- Progression: new destinations should be adjacent to Known territory first (≥ 60% of the route's decisions silent-eligible), then farther. Suggest the "surprise" destination only when ≥ 70% of its route is silent-eligible.
- Review after 12 weeks: if ≥ 70% of active users hit the floor, raise it to 3 Off drives/week as an option; never default higher.

## Q10. Safety and law

**Georgia (the country), as of November 2026.**

- The Law of Georgia on Road Traffic tells drivers to avoid any action not related to driving and forbids using a mobile communication device while driving. The ban does not apply when the driver uses an earpiece or the loudspeaker (remote) function and has both hands free to drive.\[16\]
- Article 118² of the Code of Administrative Offences: using a mobile communication device while driving → fine of 50 GEL (raised from 30 GEL by amendments adopted 17 March 2026, in force 1 May 2026).\[31\] Unpaid fines attract a surcharge of double the fine (max 500 GEL), and continued non-payment can lead to a 6-month suspension.\[32\] Reporting on the penalty points is inconsistent (parliamentary coverage said 10 points; a secondary guide lists 15): check the consolidated Code on matsne.gov.ge before quoting it in the app.\[33\]\[34\]
- The law speaks about phones and hands, not about screens or holders. A phone in a holder with no touches while moving and voice through the car's audio fits the stated exception. Touching the phone while moving, even to dismiss a prompt, risks being "use" outside the exception. Where a holder may be placed (e.g. windscreen) was not checked; tell users not to block the view and to set up before moving.
- Context: Georgia had 469 road deaths and 8,191 injuries in 2025, according to Interior Ministry figures reported by JAMnews (the highest death toll since 2019; 43% of crashes were in Tbilisi).

**Glance and touch rules.**

- Zero touches while speed > 5 km/h. All in-drive changes (level switches, recovery, frustration guard) are automatic.
- Any screen element must be readable in one glance ≤ 1.5 s (well under NHTSA's 2 s cap); no feature may need more than one glance per decision.
- Destination entry, level choice and preview only while parked.

**Text and contrast for a portrait phone at 60–80 cm.**

- Minimum cap height 6 mm (≈ 26 arcmin at 80 cm) for anything read while moving; 8 mm for the one primary item (district name in Quiet; next street in Guided/recovery). In Flutter, with ~0.16 mm per logical pixel and cap height ≈ 0.7 × font size, that is ≈ 54 px and ≈ 71 px font size. Measure on real devices.
- For Georgian (Mkhedruli) script, which has no capitals, size by x-height: x-height ≥ 4.5 mm.
- Contrast ≥ 3:1 by day, ≥ 5:1 at night (ISO 15008:2017); aim for 7:1 for text.\[35\] ≤ 3 text items on screen while moving.
- Night look: dark background, light text, no white map tiles; drop screen brightness at night so the phone is not the brightest thing in the cabin; avoid saturated blue for text. Switch on sunset/sunrise times for Tbilisi or ambient light.

## Q11. Prior art

- **London Knowledge.** ~25,000 streets, 320 runs, ~20,000 points; students recite runs aloud in one-to-one "appearances" spaced 56, then 28, then 21 days apart.\[20\]\[21\] In Woollett & Maguire (2011), 39 of 79 trainees qualified after 3–4 years, and only qualifiers showed posterior hippocampal grey-matter growth.\[36\]\[37\] Lesson for Pindoro: recital under spaced, graded testing is the core; Pindoro's recitals already copy it.
- **Knowledge apps** (WizAnn tools, "Test your Knowledge", "Taxi Knowledge" for iOS, KnowledgeOfLondon.co.uk): random point-to-point runs, weighted points, recorded calling of runs, drawing runs.\[38\]\[39\]\[40\]\[41\] None has a published evaluation.
- **Back Of Your Hand** (2022): locate random street names on a map; players reported it is hard unless streets are numbered and that some prompts were not real streets.\[42\]\[43\] No learning evaluation. Lesson: validate pack data; name-location quizzes alone don't teach routes.
- **Research prototypes:** Brügger et al. 2019 (self-tagged landmarks worked; on-demand GPS alone did not); Gramann et al. 2017 and Wunderlich & Gramann (landmark instructions work in simulator and real streets, gains lasting weeks); Schwering/Löwen orientation maps (global features → survey knowledge); Parush et al. 2007 (position quizzes); Fabrikant 2024 (neuroadaptive proposal, untested).\[1\]\[22\]\[44\]\[45\]\[46\]\[47\]
- **Commercial "learning mode":** none found in major navigation apps.
- **What did not work:** help on demand without an active task; turn-by-turn on its own for survey knowledge.

## Proposed decisions

1. **Per-decision help.** `SILENT_MIN_R = 0.85`, `SILENT_NO_FAIL_DAYS = 14`, requires Known. Validate: unaided accuracy at silent-eligible decisions should be ≥ 85%; if lower, raise `SILENT_MIN_R` by 0.05.
2. **Route level thresholds.** `OFF_SHARE = 0.90`, `OFF_MIN_R = 0.75`, `QUIET_SHARE = 0.70`, `COACHED_SHARE = 0.40`, `MIN_J_CARDS_AREA = 5`. Validate: per level, median unaided accuracy 80–90%.
3. **Hysteresis.** `STEP_DOWN_DRIVES = 2` (stretch ≤ 1.25 and recoveries ≤ 1), `STEP_UP_DRIVES = 2` (stretch > 1.60 or recoveries ≥ 3), `MAX_STEP = 1`.
4. **Frustration guard.** `GUARD_RECOVERIES = 2` in `GUARD_WINDOW_MIN = 5`, or `GUARD_LOST_TIME_S = 180` → Coached; `GUARD_TO_GUIDED = 3` recoveries. Validate: share of drives abandoned or rescued < 5%.
5. **Recovery.** Trigger when a decision fails the 1.25× rule; `RECOVERY_EXIT_HOLD_S = 10` on a good path before going silent.
6. **Voice timing.** `PREPARE_M = 150`, `PREPARE_S = 10` (use the larger); `ACTION_M = 40`, `ACTION_S = 4`; `MAX_PROMPTS_PER_DECISION = 2`; `LANDMARK_MAX_DIST_M = 50`; `MAX_PROMPT_S = 3`.
7. **Orientation cues.** `DISTRICT_CUE_MIN_KM = 2`, `DISTRICT_CUE_MIN_MIN = 3`; Guided and Coached only.
8. **Confirmations.** Guided only, `CONFIRM_DELAY_S = 5–10`.
9. **No in-car questions.** `ANTICIPATION_CUE_ENABLED = false`. If ever tested: ≥ 300 m, ≥ 20 s, ≤ 60 km/h, no junction within 150 m, ≥ 60 s apart.
10. **FSRS credit.** Good if clean; Hard if `HESITATION_WINDOW_M = 150`; credit only if R ≤ `CREDIT_MAX_R = 0.92`; `MAX_CREDITS_PER_CARD_PER_DAY = 1`; habitual: ≥ `HABIT_PASSES = 3` in `HABIT_WINDOW_DAYS = 14` → ≤ 1 credit per `HABIT_CREDIT_DAYS = 7`. Validate: credited cards should keep ≥ 88% success at their next in-app review.
11. **Guided/recovery decisions.** Exposure only, `NO_CREDIT_AFTER_PROMPT_S = 60`.
12. **Personal pull-forward.** `PERSONAL_NEW_CARD_CAP = 0.25`, qualifies at ≥ 2 drives in 14 days; introduce connected main road first.
13. **Screen.** Quiet: heading arrow + cardinal letter, district name, status dot; no map/route/street labels. Guided/recovery: heading-up with north arrow. Preview/review: north-up.
14. **Legibility.** `MIN_CAP_MM = 6`, `PRIMARY_CAP_MM = 8`, `MIN_XHEIGHT_MM_KA = 4.5`, `MIN_CONTRAST_DAY = 3.0`, `MIN_CONTRAST_NIGHT = 5.0`, `TARGET_TEXT_CONTRAST = 7.0`, `MAX_TEXT_ITEMS_MOVING = 3`, `MAX_GLANCE_DESIGN_S = 1.5`.
15. **No touch while moving.** `TOUCH_LOCK_SPEED_KMH = 5`.
16. **Habit.** `WEEKLY_OFF_DRIVES = 2`, `WEEKLY_NEW_DESTINATIONS = 1`, `MISSED_WEEKS_GRACE = 1`, `NEW_DEST_MIN_SILENT_SHARE = 0.60`, `SURPRISE_MIN_SILENT_SHARE = 0.70`.
17. **Pre/post drive.** `PREVIEW_TARGET_S = 60–90`; debrief prompt on arrival, `DEBRIEF_WINDOW_H = 24` (best within 1 h); one pointing probe per new destination.

## What to log per drive

- Drive: id, start/end time, level suggested, level chosen, level changes (time, cause), destination type, route id, best-route length and time, actual length and time, stretch, rescue flag, night/day.
- Track: GPS points (1 Hz), speed, heading, map-matched edges.
- Per decision: J card id, direction, card state (Known, R, stability, last failure), help given (none / prepare / action / recovery), prompt times and distances, outcome (correct / wrong / illegal), distance-to-best ratio, hesitation flag (location, duration), U-turn flag, FSRS effect (credited Good/Hard/Again, exposure, excluded and why).
- Voice: each prompt's text, duration, type (landmark/distance/confirmation/district/recovery), whether music was ducked.
- Screen: screen state changes; any touches while speed > 5 km/h (should be zero; log for audit).
- Street-name exposures: street id, spoken or shown, level.
- Post-drive: preview completed (s), debrief completed (s), decisions reviewed, pointing error (degrees).

## Open questions

- Does Coached's cue-without-question help learning more than Quiet's silence for not-yet-Known decisions, or does it just shift effort? Run an A/B per decision in the log (randomly coach half of eligible non-Known decisions) and compare next-review success.
- Is orientation-based content (districts, cardinal direction) helpful for drivers? Evidence conflicts; compare pointing error between users with and without district cues.
- Can a steering-wheel media button (via the CarPlay/Bluetooth connection) serve as a safe, legal "help" signal without touching the phone? Needs legal and platform checks.
- Exact penalty points under the amended Article 118², and whether Georgian law limits phone-holder placement.
- How to separate traffic stops from hesitations without traffic data (e.g., only flag stops away from signals and junctions, as now, and test against dashcam-labelled drives).
- Whether name exposure during Guided drives speeds up street-name card learning.

## Caveats

Most of the spatial-learning evidence comes from pedestrians or virtual/simulated driving, single routes, and short retention intervals; real, repeated driving in one city over months is untested. The thresholds in Q5–Q6 are expert judgement built on general learning science, not navigation trials. The Georgian law summary is from the consolidated texts and news coverage, not legal advice.

## Sources

1. <https://link.springer.com/content/pdf/10.1186/s41235-019-0156-5.pdf>
2. [Google Scholar](https://scholar.google.com/scholar_lookup?hl=en&publication_year=2008&pages=74-82&author=T.+Ishikawa&author=H.+Fujiwarab&author=O.+Imaic&author=A.+Okabe&title=Wayfinding+with+a+GPS-based+mobile+navigation+system%3A+A+comparison+with+maps+and+direct+experience)
3. [Wayfinding with a GPS-based mobile navigation system: A comparison with maps and direct experience](https://researchgate.net/publication/223739400_Wayfinding_with_a_GPS-based_mobile_navigation_system_A_comparison_with_maps_and_direct_experience)
4. [Full article: Wayfinding Through Orientation](https://www.tandfonline.com/doi/full/10.1080/13875868.2017.1322597)
5. [Spatial Learning with Orientation Maps: The Influence of Different Environmental Features on Spatial Knowledge Acquisition](https://agris.fao.org/search/en/providers/122413/records/687a98a59d6e0577321f8196)
6. [Using a single map display both for navigational planning and for turn-by-turn vehicle guidance: configural spatial knowledge acquisition - PubMed](https://pubmed.ncbi.nlm.nih.gov/24188334)
7. [Effects of electronic map displays and individual differences in ability on navigation performance - PubMed](https://pubmed.ncbi.nlm.nih.gov/22908682/)
8. [The time course of spatial knowledge acquisition for different digital navigation aids - ScienceDirect](https://www.sciencedirect.com/science/article/pii/S0198971523000558)
9. [(PDF) Optimising landmark-based route guidance for older drivers](https://www.researchgate.net/publication/309628128_Optimising_landmark-based_route_guidance_for_older_drivers)
10. [Let Me be Your Guide: Physical Guidance Improves Spatial Learning for Older Adults with Simulated Low Vision - PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC8197446/)
11. [Talking to your car can drive you to distraction - PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC5256443/)
12. [Federal Register :: Visual-Manual NHTSA Driver Distraction Guidelines for In-Vehicle Electronic Devices](https://www.federalregister.gov/documents/2013/04/26/2013-09883/visual-manual-nhtsa-driver-distraction-guidelines-for-in-vehicle-electronic-devices)
13. [Federal Register :: Visual-Manual NHTSA Driver Distraction Guidelines for Portable and Aftermarket Devices](https://www.federalregister.gov/documents/2016/12/05/2016-29051/visual-manual-nhtsa-driver-distraction-guidelines-for-portable-and-aftermarket-devices)
14. [ISO 15008-2017 - PDFCOFFEE.COM](https://pdfcoffee.com/download/iso-15008-2017-pdf-free.html)
15. [Traffic Fines in Georgia: Speeding, Payment & Penalties](https://og.ge/blog/traffic-fines)
16. [საგზაო მოძრაობის შესახებ საქართველოს კანონი - შემოსავლების სამსახური - infohub.rs.ge](https://infohub.rs.ge/ka/workspace/document/a012b990-5772-4a55-835e-7e8fec2a774c?openFromSearch=true)
17. [ERIC - EJ785065 - Exploring the Assistance Dilemma in Experiments with Cognitive Tutors, Educational Psychology Review, 2007-Sep](https://eric.ed.gov/?id=EJ785065)
18. [Does It Really Take 66 Days to Form a Habit? What the Study Found](https://thenesttools.com/blog/how-long-to-form-a-habit-66-days/)
19. [How London Cabbies Are Mentally Superior To You](https://gizmodo.com/how-london-cabbies-are-mentally-superior-to-you-5866305)
20. [The Knowledge of London An introduction to learning the Knowledge of London](https://content.tfl.gov.uk/introduction-to-knowledge-booklet-march-2022.pdf)
21. [The Knowledge](https://www.levc.com/company/the-knowledge/)
22. [Degradation in spatial knowledge acquisition when using automatic navigation systems - Technion - Israel Institute of Technology](https://cris.technion.ac.il/en/publications/degradation-in-spatial-knowledge-acquisition-when-using-automatic/)
23. [Wayfinding with a GPS-based mobile navigation system: A comparison with maps and direct experience - ScienceDirect](https://www.sciencedirect.com/science/article/abs/pii/S0272494407000734)
24. [(PDF) Presence and Quality of Navigational Landmarks: Effect on Driver Performance and Implications for Design](https://www.researchgate.net/publication/6902858_Presence_and_Quality_of_Navigational_Landmarks_Effect_on_Driver_Performance_and_Implications_for_Design)
25. [Landmark-based navigation instructions improve incidental spatial knowledge acquisition in real-world environments](https://www.researchgate.net/publication/354196513_Landmark-based_navigation_instructions_improve_incidental_spatial_knowledge_acquisition_in_real-world_environments)
26. [(PDF) Pedestrian navigation aids: Information requirements and design implications](https://www.researchgate.net/publication/28576246_Pedestrian_navigation_aids_Information_requirements_and_design_implications)
27. [Talking to your car can drive you to distraction](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5256443/)
28. [Measuring Cognitive Distraction in the Automobile III:](https://newsroom.aaa.com/wp-content/uploads/2020/11/Hands-Free-Phase-III-Research-Report-Foundation-October-2015.pdf)
29. [Texting and Driving NHTSA Guidelines](https://www.doctorspracticinglaw.com/news/nhtsa-distracted-driving-guidelines/)
30. [How are habits formed: modelling habit formation in the real world · What It Shows (and Doesn't) · Steps](https://steps.org/sources/lally-2010-habit-formation/)
31. [Parliament approves MIA’s traffic rule enforcement amendments in third reading - 1TV](https://1tv.ge/lang/en/news/parliament-approves-mias-traffic-rule-enforcement-amendments-in-third-reading/)
32. [მუხლი 118²: მექანიკური სატრანსპორტო საშუალების მართვის დროს მძღოლის მიერ მობილური კომუნიკაციის საშუალებით სარგებლობა | საქართველოს ადმინისტრაციულ სამართალდარღვევათა კოდექსი](https://legal.ge/ka/law/28216-sakartvelos-administratsiul-samartaldarghvevata-kodeksi/118-2)
33. [Fines for traffic violations to increase as parliament backs amendments - Georgia Today](https://georgiatoday.ge/fines-for-traffic-violations-to-increase-as-parliament-backs-amendments/)
34. [Traffic Rules and Fines in Georgia 2026: Speed Limits, Cameras and Checking Debts](https://worldwalk.app/en/blog/tbilisi/georgia-traffic-rules-fines/)
35. [ISO 15008:2017 - Ergonomic Standards for In-Vehicle Visual Displays](https://standards.iteh.ai/catalog/standards/iso/d07adfe7-f551-4557-bb09-7236d8491cf6/iso-15008-2017)
36. [How acquiring The Knowledge changes the brains of London cab drivers](https://blogs.discovermagazine.com/notrocketscience/2011/12/08/acquiring-the-knowledge-changes-the-brains-of-london-cab-drivers)
37. [Changes in London taxi drivers' brains driven by acquiring 'the Knowledge', study shows](https://medicalxpress.com/news/2011-12-london-taxi-drivers-brains-driven.html)
38. [Taxi Knowledge - App Store - Apple](https://apps.apple.com/gb/app/taxi-knowledge/id6787505073)
39. [London taxi Knowledge students face a staggering possibility of 40 MILLION different questions during Knowledge exam process](https://www.taxi-point.co.uk/post/london-taxi-knowledge-students-face-a-staggering-40-million-different-question-possibility-during-kn)
40. [Revision app for The Knowledge London taxi driver exams](https://testyourknowledge.co.uk/)
41. [KnowledgeOfLondon.co.uk](https://www.knowledgeoflondon.co.uk/)
42. [Hi HN, I made Back Of Your Hand, a map-based game where you're given random stre...](https://news.ycombinator.com/item?id=30733344)
43. [Show HN: A game that tests how well you know your local area](https://news.ycombinator.com/item?id=30733339)
44. [Landmark-Based Navigation Instructions Improve Incidental Spatial Learning in Real-Life Environments](https://www.biorxiv.org/content/10.1101/789529v2.full)
45. [Landmark-Based Navigation Instructions Improve Incidental Spatial Knowledge Acquisition in Real-World Environments](https://www.biorxiv.org/content/10.1101/789529.full.pdf)
46. [Towards neuroadaptive navigation assistance to reduce spatial de-skilling](https://link.springer.com/article/10.1007/s10339-024-01209-w)
47. [(PDF) The effect of orientation instructions on the recall and reuse of route and survey elements in wayfinding descriptions](https://www.researchgate.net/publication/339562490_The_effect_of_orientation_instructions_on_the_recall_and_reuse_of_route_and_survey_elements_in_wayfinding_descriptions)
