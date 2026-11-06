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
| Points count-up | Digits roll up, tabular | `count-up`, ease-out cubic | final value at once | soft rising ticks | none |
| XP bar | Grows | `slow` `ease.standard` | instant | none | none |
| Streak increase | Flame pops; number rolls up by one | 420 ms `ease.overshoot`; roll 300 ms | number cross-fades | streak whoosh + ding | `mediumImpact()` |
| Streak milestone (7/30/100/365) | Big celebration | `celebrate.big` | static | streak fanfare | `heavyImpact()`, `mediumImpact()` +90 ms |
| Level up | Big celebration; XP bar fills and resets; shield pops | `celebrate.big` | static takeover | level-up fanfare (4 notes) | `heavyImpact()`, `mediumImpact()` +120 ms, `lightImpact()` +240 ms |
| Badge unlock | Scale from 0.4 with −8° turn; 12-dash burst | `spring.bouncy`; burst `celebrate.medium` | fade + scale 0.96 → 1 | unlock chime | `mediumImpact()` |
| Stop unlock (path) | Lock drops; pin fills and pops; lane dashes drive to it | 600 ms `ease.linear`; pop `spring.bouncy` | instant swap | unlock tick | `lightImpact()` |
| District fill | Fill wipes from the centroid; outline thickens; label checks | 2 × `slow` `ease.standard` | cross-fade 200 ms | district fanfare (short) | `heavyImpact()` |
| Current stop | Floats ±4 dp | 1 600 ms loop | still | none | none |
| Sheet / dialog | In: rise or fade + 0.96 → 1; out: reverse | `base` in, `fast` out | fade | none | none |
| Toast | Slide 16 dp + fade | `base` in, `fast` out | fade | none | none |
| Error | Shake 6 dp × 2 on the failed control | 300 ms | colour flash only | soft error tone | `HapticFeedback.vibrate()` (Android) / `heavyImpact()` |

## Celebration sizes

- **Small** (Close): badge wiggle ±6° and one ring pulse from the pin.
- **Medium** (Great, badges, unlocks): badge pop, 12 lane-dash pieces burst radially, Pindo hops 12 dp, points count up.
- **Big** (first Perfect in a round, level up, streak milestones, first mastered district): medium plus 28 pieces (dashes and stars) showering from the top and a 10 dp lane-yellow glow pulsing around the screen edge; Pindo jumps.
- At most one big celebration per round (except level up); repeated Perfects use medium with a "Perfect ×2" counter; from the fifth Great in a row the burst drops to a pop.

## Reduce motion

Read `MediaQuery.of(context).disableAnimations` (iOS Reduce Motion, Android "Remove animations"). When true: replace every movement with a ≤ 200 ms cross-fade or an instant change, drop confetti, glows, floats, squash and wipes, and show final numbers immediately. Sound and haptics still follow their own toggles.

## Sound

- A small set of short, warm, melodic sounds (≤ 600 ms, celebrations ≤ 1.8 s), all in one key so sequences sound musical. No harsh buzzers; the Miss sound is soft and descending.
- Preload all sounds at launch (`just_audio` or `audioplayers` with a low-latency player); play the tap and pin-drop sounds with < 30 ms latency.
- **Global Sound toggle** in Settings mutes every game sound; it is independent of the Haptics toggle. On iOS use the ambient audio session so the silent switch mutes Pindoro and the player's music keeps playing.

## Haptics

- Use `HapticFeedback` only: `selectionClick` for taps and steps, `lightImpact` for small physical moments, `mediumImpact` for confirmations and medium rewards, `heavyImpact` for big moments. Sequences are spaced 60–120 ms apart.
- **Global Haptics toggle** in Settings; also respect the OS setting. Never vibrate continuously.
