# Motion, sound & haptics

Springy and fast. Things the player touches use springs; things the app moves use curves. Nothing on the critical path takes longer than 300 ms, celebrations never block input, and every animation has a calm alternative.

## Tokens

| Token | Value | Flutter |
| --- | --- | --- |
| `motion.duration.instant` | 80 ms | `Duration(milliseconds: 80)` |
| `motion.duration.quick` | 120 ms | `Duration(milliseconds: 120)` |
| `motion.duration.fast` | 200 ms | `Duration(milliseconds: 200)` |
| `motion.duration.base` | 280 ms | `Duration(milliseconds: 280)` |
| `motion.duration.slow` | 420 ms | `Duration(milliseconds: 420)` |
| `motion.pin-drop` | 520 ms | `Duration(milliseconds: 520)` |
| `motion.count-up` | 900 ms (max 1 400) | `Duration(milliseconds: 900)` |
| `motion.celebrate.small` / `.medium` / `.big` | 700 / 1 400 / 2 600 ms | `Duration(milliseconds: …)` |
| `motion.stagger` | 40 ms | offset between list items and burst pieces |
| `motion.ease.standard` | cubic-bezier(0.2, 0, 0, 1) | `Cubic(0.2, 0, 0, 1)` |
| `motion.ease.decelerate` | cubic-bezier(0.05, 0.7, 0.1, 1) | `Cubic(0.05, 0.7, 0.1, 1)` |
| `motion.ease.accelerate` | cubic-bezier(0.3, 0, 0.8, 0.15) | `Cubic(0.3, 0, 0.8, 0.15)` |
| `motion.ease.overshoot` | cubic-bezier(0.34, 1.56, 0.64, 1) | `Cubic(0.34, 1.56, 0.64, 1)` |
| `motion.ease.press` | cubic-bezier(0.4, 0, 1, 1) | `Cubic(0.4, 0, 1, 1)` |
| `motion.spring.snappy` | mass 1, stiffness 700, damping 34 | `SpringDescription(mass: 1, stiffness: 700, damping: 34)` |
| `motion.spring.bouncy` | mass 1, stiffness 520, damping 20 | `SpringDescription(mass: 1, stiffness: 520, damping: 20)` |
| `motion.spring.gentle` | mass 1, stiffness 220, damping 28 | `SpringDescription(mass: 1, stiffness: 220, damping: 28)` |

## Every event

| Event | Motion | Timing | Reduce motion | Sound | Haptic |
| --- | --- | --- | --- | --- | --- |
| Tap (any control) | Pressed state | `instant` | same | tap (primary buttons only) | `HapticFeedback.selectionClick()` |
| 3D button press | Face drops onto its 4 dp lip; springs back | in `instant` + `ease.press`; out `spring.snappy` | same | tap | `selectionClick()` |
| Pin drop | Falls 24 dp, squash 14 %, one bounce, shadow grows, ring ripple at the tip | `pin-drop`, `spring.bouncy` | fade in at rest, 120 ms | pin drop (soft wooden "tok") | `HapticFeedback.lightImpact()` |
| Pin drag | Lifts 12 dp above the finger, shadow widens | `spring.gentle` follow | no lift | none | none |
| Confirm | Press + halo pulse around the pin | 400 ms `ease.standard` | no pulse | confirm click | `HapticFeedback.mediumImpact()` |
| Street plate in / out | Slide 24 dp + fade in; slide up 16 dp + fade out | `base` decelerate / `fast` accelerate | cross-fade 150 ms | none | none |
| Reveal sheet | Rises; map fits pin + street; badge pops 80 ms later | `base` decelerate; badge `spring.bouncy` | fade; map jumps | tier sound | tier haptic |
| Perfect | Big celebration | `celebrate.big` | static badge | bright three-note rise + bell | `heavyImpact()`, `mediumImpact()` +90 ms |
| Great | Medium celebration | `celebrate.medium` | static badge | two-note rising chime | `mediumImpact()` |
| Close | Small celebration | `celebrate.small` | static badge | single soft blip | `lightImpact()` |
| Miss | Badge appears; Pindo encourages | `base` | same | low, soft two-note fall (never a buzzer) | `selectionClick()` ×2, 60 ms apart |
| Question segment fill | Fills left to right | `fast` `ease.standard` | instant | none | none |
| Count-up | Digits roll up, tabular (City memory on Session done) | `count-up`, ease-out cubic | final value at once | soft rising ticks | none |
| Streak increase | Flame pops; number rolls up by one | 420 ms `ease.overshoot`; roll 300 ms | number cross-fades | streak whoosh + ding | `mediumImpact()` |
| Streak milestone (7/30/100/365) | Big celebration | `celebrate.big` | static | streak fanfare | `heavyImpact()`, `mediumImpact()` +90 ms |
| Badge unlock | Scale from 0.4 with −8° turn; 12-dash burst | `spring.bouncy`; burst `celebrate.medium` | fade + scale 0.96 → 1 | unlock chime | `mediumImpact()` |
| District fill | Fill wipes from the centroid; outline thickens; label checks | 2 × `slow` `ease.standard` | cross-fade 200 ms | district fanfare (short) | `heavyImpact()` |
| Sheet / dialog | In: rise or fade + 0.96 → 1; out: reverse | `base` in, `fast` out | fade | none | none |
| Toast | Slide 16 dp + fade | `base` in, `fast` out | fade | none | none |
| Error | Shake 6 dp × 2 on the failed control | 300 ms | colour flash only | soft error tone | `HapticFeedback.vibrate()` (Android) / `heavyImpact()` |

## v3 events

The events added by v3 (Learn the whole city). Durations and curves come from the tokens above; reduce motion follows the rule below.

| Event | Motion | Sound · haptic |
| --- | --- | --- |
| Mix-up reveal | Both streets paint, cobalt then yellow (280 ms each) | Miss sound · Miss haptic |
| Next-review chip | Pops in after the tier title (celebrate small) | none |
| Speech token resolved | Chip slides in from the transcript | light tick |
| Drive start / end | Timer fades in / out | medium impact |
| Session done | Celebrate big; City memory counts up | results sound · success haptic |

In Flutter: the light tick is `selectionClick()` with no sound; medium impact is `mediumImpact()`; the success haptic is `heavyImpact()`, then `mediumImpact()` 90 ms later; the Miss haptic is `selectionClick()` twice, 60 ms apart.

### v3 progress motion

Today, the Progress tab, Session done and the placement result. Quiet: no sound or haptic of their own, once per visit, and calm under reduce motion.

| Event | Motion | Timing | Reduce motion | Sound | Haptic |
| --- | --- | --- | --- | --- | --- |
| Memory bar (card) first shown | Segments grow from the left edge to their widths, together | `slow` `ease.standard` | final widths at once | none | none |
| Memory chart, Progress opened | Line draws left to right; then the area fades in and today's dot pops | line 2 × `slow` `ease.standard`; area `base`; dot `spring.bouncy` | finished chart at once | none | none |
| Forecast bars, Progress opened | Bars grow up from the bottom, today first | `base` `ease.decelerate`, each `stagger` after the last | final bars at once | none | none |
| City memory, Session done | Number counts up from the session's start value | `count-up`, ease-out | final value at once | results sound (with Session done) | success haptic (with Session done) |
| Placement result | Stat tiles stagger in (fade + 8 dp rise) | `base`, `stagger` apart | at once | none | none |
| Explore, back from a round (app 2.8) | City memory counts up from its value replayed to the round's start, with a "+n" pill; the district fills change without fading in | `count-up`, ease-out | final value at once | none | none |
| Session bar, between rounds (app 2.8) | Round done replaces the round's last reveal; the round pill steps to the next round when Next round starts. No timer runs | sheet `base` | fade | none | none |

Compact memory bars in list rows never animate. Progress never animates backwards: a drop is drawn at its new size.

## Celebration sizes

- **Small** (Close): badge wiggle ±6° and one ring pulse from the pin.
- **Medium** (Great, badges): badge pop, 12 lane-dash pieces burst radially, Pindo hops 12 dp.
- **Big** (first Perfect in a session or round, Session done, streak milestones, first district Mastered): medium plus 28 pieces (dashes and stars) showering from the top and a 10 dp lane-yellow glow pulsing around the screen edge; Pindo jumps.
- At most one big celebration per session or round, plus the one on Session done; repeated Perfects use medium with a "Perfect ×2" counter; from the fifth Great in a row the burst drops to a pop.

## Reduce motion

Read `MediaQuery.of(context).disableAnimations` (iOS Reduce Motion, Android "Remove animations"). When true: replace every movement with a ≤ 200 ms cross-fade or an instant change, drop confetti, glows, floats, squash and wipes, and show final numbers immediately. Sound and haptics still follow their own toggles.

## Sound

- A small set of short, warm, melodic sounds (≤ 600 ms, celebrations ≤ 1.8 s), all in one key so sequences sound musical. No harsh buzzers; the Miss sound is soft and descending.
- Preload all sounds at launch (`just_audio` or `audioplayers` with a low-latency player); play the tap and pin-drop sounds with < 30 ms latency.
- **Global Sound toggle** in Settings mutes every game sound; it is independent of the Haptics toggle. On iOS use the ambient audio session so the silent switch mutes Pindoro and the player's music keeps playing.

## Haptics

- Use `HapticFeedback` only: `selectionClick` for taps and steps, `lightImpact` for small physical moments, `mediumImpact` for confirmations and medium rewards, `heavyImpact` for big moments. Sequences are spaced 60–120 ms apart.
- **Global Haptics toggle** in Settings; also respect the OS setting. Never vibrate continuously.
