# Accessibility

Pindoro is a visual map game, so accessibility is designed in rather than bolted on: every game element has a non-colour signal, a screen-reader label and a large target.

## Touch and reach

- Every interactive element has a 48 × 48 dp minimum target (`size.tap.min`), including map controls, exit buttons, chips (40 dp face inside a 48 dp target) and icon buttons.
- Primary actions (Confirm, Next, Continue, Start, Catch up) are full-width 48 dp buttons (`size.button.md`, since app 2.8) at the bottom of the screen, in the thumb zone; the search field is 48 dp too. Destructive or leaving actions are never in that position.
- Adjacent targets are at least 8 dp apart.

## Colour and contrast

- All text pairs pass WCAG AA in both themes (140 checked, most AAA); control borders, icons, the focus ring and every map overlay pass 3:1 against what they sit on (88 checked).
- **Never colour alone.** Answer tiers have icon + label + sound + haptic as well as colour; memory states have a legend with names and counts; Mastered districts carry a check on their label; progress segments for a Miss use the miss colour *and* the question count is announced.
- Tier fills were chosen to stay apart under deuteranopia, protanopia and tritanopia simulation (worst-case ΔE 16+); see Feedback tiers.

## Text scaling

- Every text style scales with the system setting up to 200 %. Test at 100 %, 130 %, 160 % and 200 %.
- The street plate's name starts at `title.lg` (20) and steps down to `size.plate.name-floor` (16) × the text scale before it takes a third line; the plate grows downward, and its sub-line stays on one line. At 200 % the sub-line moves into the reveal sheet if the plate would cover more than 45 % of the map.
- The reveal sheet scrolls internally at large sizes; **Next** stays pinned and visible.
- Never ellipsize a street name except in the compact plate during the reveal (the full name is in the sheet).
- Use `MediaQuery.textScalerOf(context)`; don't clamp text scale below 2.0.

## Screen readers (TalkBack, VoiceOver)

| Element | Label |
| --- | --- |
| Street plate | Heading: "Find: Harbour View Boulevard, Riverside." Focus moves here when a new street loads. |
| Map | "Map. Double-tap to drop your pin at the centre. Drag with two fingers to move the map." |
| Player's pin | "Your pin. Double-tap and hold to move." After a drop: "Pin dropped, 3 blocks north of the river." |
| Confirm | "Confirm answer" (disabled: "Confirm. Drop a pin first.") |
| Question bar | "Question 5 of 10" (a session: "Today’s session, 5 of 12") |
| Round pill | "Round 1 of 3" (only when the day has more than one round) |
| Place intro | Heading: "New place, 1 of 3. Tbilisi Concert Hall." "Can't find it? Hide this place" opens the "Hide {place}?" dialog. |
| Reveal sheet | One live announcement: "Great. 84 metres away. Next review in 12 days." Focus moves to Next. |
| Today card | "Today’s session: 24 reviews, 10 new streets and 6 turns, in 3 rounds." Then Start as its own button. Done: "Today’s goal done. 14-day streak kept, 22 reviews due tomorrow." |
| Bottom nav | "Today, tab, 1 of 4, selected." |
| Streak pill | "12-day streak." |
| District | "Market. In progress, 6 of 10 streets." |
| City memory | Today's row: "City memory 1 284 of 3 216 streets, plus 8 since yesterday. Opens Progress." Progress's card: "City memory: 1 284 of 3 216 streets you’d place today, 8 more than yesterday." |
| Pindo | Decorative by default (excluded from semantics); in empty states, describe the moment. |

Use Flutter `Semantics` with `header`, `button`, `liveRegion` (reveal, toasts) and `excludeSemantics` for decoration. Group a stat chip's icon and text into one node.

## Keyboard, switch and alternative input

- All controls are focusable in a logical order; the focus ring is a solid 3 dp `color.focus.ring`, 2 dp outside.
- The pin can be placed without dragging: arrow keys / switch scanning move it 8 dp (Shift: 40 dp); Enter confirms.
- An optional **list answer mode** (accessibility setting) shows four candidate areas as large buttons for players who can't use the map precisely; it awards the same tiers by distance.

## Motion and sensory

- Reduce motion is honoured everywhere (see Motion, sound & haptics).
- Sound and haptics have separate toggles; neither carries information that isn't also on screen.
- No flashing above 3 times per second; the big-celebration edge glow pulses once.

## Language

- English (`Locale('en')`) is the default; every string is externalised and each further locale is a translation written natively, not machine-translated.
- Never uppercase UI strings (some scripts have capitals FiraGO doesn't draw); use weight and colour for emphasis.
