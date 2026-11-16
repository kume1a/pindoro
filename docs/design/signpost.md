Pindoro is a mobile game for learning the streets and routes of any town or city. Version 1 is a map quiz: the player sees a street name and drops a pin where they think it is on an unlabelled map. v3, **Learn the whole city**, turns it into a learning system: one spaced-repetition model schedules every street and key turn, a daily session on the Today tab is sized in minutes, City memory (how many streets the player would place right now) is the headline number, and route recitals and GPS-free drives are the tests. Daily streaks and badges stay; XP, levels, leagues, the lesson path, the Pit stop tab and the daily XP goal are gone. It ships in Flutter (Material 3) on Android and iOS.

The visual direction is **Signpost**: cobalt road-sign plates, lane-yellow rewards, asphalt roads with dashed centre lines, chunky 3D buttons and one hero shape, the map pin.

## Personality

- **Playful, confident, encouraging.** A game you want to open every day, never a navigation utility.
- **Bold and tactile.** Flat saturated colour, chunky rounded shapes, big friendly type, buttons that physically press, generous but proportionate celebration.
- **The pin is the hero.** It is the logo, the app icon, the tap marker, the mascot and the star of every reward moment.
- **Roads all the way down.** Road-marking yellow, dashed lane lines, street plates and signposts are the recurring motifs.
- **Any city.** Nothing in the interface belongs to one place: no landmarks, flags or local motifs. City and street names in examples are placeholders.
- **Original.** No owl, no Duolingo green, no borrowed typefaces or illustration style.

## Voice

Speak like a friend in the passenger seat: quick, warm, a little cheeky, never sarcastic.

- Second person, present tense, short sentences: "Drop a pin on…", "So close to perfect.", "You know this city."
- Celebrate effort as much as accuracy. After a miss, point the way rather than scold: "Not this time. It runs along the river, east of the old bridge." Never "Wrong" or "Incorrect".
- Numbers are the reward, so show them plainly: "84 m", "+8 since yesterday", "12-day streak".
- Sentence case everywhere. **Never all caps** (see Every language, equally).
- Buttons are verbs: Confirm, Next, Start, Catch up, Keep going. Never "OK".
- No emoji in UI copy; icons and Pindo carry the emotion.

### Driving vocabulary

Use it where it is clearer or more fun, never where it confuses.

| Concept | Say |
| --- | --- |
| Lives, if added | Fuel |
| Route drill | Road trip |

### Copy examples

| Moment | Copy |
| --- | --- |
| Quiz prompt | Drop a pin on · Harbour View Boulevard |
| Perfect | Perfect! On the street. You know this city. |
| Great | Great! 84 m away. So close to perfect. |
| Close | Close. 240 m away. You're in the right neighbourhood. |
| Miss | Not this time. 1.2 km away. It runs along the river, east of the old bridge. |
| Mix-up (v3) | Mix-up. You placed 26 May 5th Lane. The 4th is the next lane west, before the bend. |
| Next review (v3) | Next review in 12 days · Back in this session |
| Today, ready | Today’s drive. About 20 min · saves as you go |
| Catching up | 186 reviews waiting. New streets are paused until you catch up. |
| Session done | Session done. 19 min · everything due today is cleared |
| Streak reminder | Your 12-day streak is running on fumes. Today’s session keeps it going. |

## Every language, equally

- English is the default UI language; every other language is a translation of the same strings, and none gets its own design. Design every text component so any language and script can follow.
- The wordmark is always "pindoro", in every language.
- Show street names as the city writes them; when the city's script differs from the UI language, add the transliteration beneath in `body.sm`.
- Localised strings often run longer than English: components wrap street names rather than truncating them. Test with long names, e.g. "Grand Union Canal Embankment North".
- **No uppercase transforms.** Some scripts have capital forms FiraGO doesn't draw, and caps read as shouting in any language. Never call `toUpperCase()` on UI strings; emphasise with weight and colour.
- Counts, distances, City memory and timers use tabular figures.

## Colour

Primitives (`color.cobalt.*`, `color.yellow.*`, `color.aqua.*`, `color.orange.*`, `color.red.*`, `color.asphalt.*`) feed semantic tokens, which feed component tokens. Components only use semantic or component tokens.

- Screens on `color.surface.base`; cards, pills and the nav bar on `color.surface.raised`; sheets and dialogs on `color.surface.overlay`; tracks on `color.surface.sunken`.
- Text is `color.text.primary`; metadata `color.text.secondary`. Both pass 4.5:1 on every surface and every `*.soft` tint in both themes.
- **Cobalt** (`color.primary.base`) is the one most important action per screen, "selected", and anything that means "you" on the map. Labels on it are `color.primary.on`.
- **Lane yellow** means earned (`color.reward.*`: badges, gold, completed progress) or decoration (`color.accent.*`: lane dashes, highlights). Text on yellow is always `color.reward.on` (asphalt ink).
- Status: `color.success.*` (aqua), `color.warning.*` (orange), `color.error.*` (red), `color.info.*` (cobalt). Each has `base`, `lip`, `on`, `soft` and `text`.
- Answer tiers have their own set: `color.feedback.{perfect|great|close|miss}.{fill|lip|on|bg|ink}`. Fills keep the same value in light and dark; tier colours were chosen to stay distinguishable under deuteranopia, protanopia and tritanopia, and every tier also has its own icon, label, sound and haptic.
- **Saturated fills keep their daylight value at night** (buttons, plates, tier fills, rewards); surfaces, text, soft tints and coloured text adapt. Street plates stay `color.cobalt.500` in both themes, like real signs.
- Focus: a solid 3 dp `color.focus.ring`, 2 dp outside the control.
- Every text pair in both themes passes WCAG AA (140 pairs checked); every control border, icon and map overlay passes 3:1 (88 pairs). See Semantic colour and Map overlays.

## Type

**FiraGO** (SIL OFL) for everything: Latin, Greek, Cyrillic, Georgian and more in six weights (400–900), with tabular figures. Display and headlines run at 800–900; roundness comes from shapes, not the font, so every script keeps the same face. Fallback: Noto Sans → system.

Use roles, not sizes: `display.*` for celebration moments (one line), `headline.lg` for tier labels, `headline.md` for the street name on the plate, `title.*` for headers, `body.*` for copy, `label.*` for controls (`label.button` for button labels), `numeric.*` for counts, distances, City memory and timers (always tabular figures). Letter-spacing is 0 everywhere; line heights are generous so scripts with tall ascenders and deep descenders fit.

## Shape, space and depth

- 4-pt spacing (`space.1` … `space.16`); 16 dp screen gutters (`space.4`).
- Generous, signboard-like radii: `radius.lg` (16) for buttons, plates, cards and signposts; `radius.xl` for large cards and dialogs; `radius.2xl` for sheets; `radius.full` for pills. Nested shapes go one step smaller.
- **Flat with a solid lip.** Depth is a bottom lip in the element's own `*.lip` colour (`elevation.1` 2 dp, `elevation.2` 4 dp, `elevation.3` 6 dp), never a blur. Pressing removes the lip and moves the face down by the same amount. The only soft shadow (`shadow.float`) is for elements floating over the map.
- Strokes: `stroke.base` (2) for borders, `stroke.thick` (3) for the focus ring and the plate's inner rule, `stroke.icon` (2.5) in icons.

## The pin

One geometry everywhere: a rounded pin on a 40 × 48 grid: a round head (radius 16), a short point (tip 26 from the head centre, slightly rounded) and a 4 dp lip. It replaced the taller 40 × 56 teardrop in November 2026. Cobalt with a yellow dot as the brand mark; cobalt with a white dot and white halo as the player's pin; with a face as Pindo. The tip is always the exact point.

## The map

The basemap is unlabelled and low-saturation (CARTO light_nolabels / dark_nolabels style). Overlays follow one rule: **yellow paint is the truth** (answer street, correct route: `color.map.answer.*`), **cobalt is you** (pin, drawn route: `color.map.player.*`), **ink is measurement** (distance line and chip: `color.map.measure.*`). Districts are outlined when not started, yellow in progress and cobalt when Mastered (`color.map.district.*`); nothing is locked. Never show the answer street before Confirm. In v3 the intro and the reveal also name the streets the player already knows (grey trace, white chip), never the answer; a Mix-up draws the street the pin hit in cobalt, dashed.

## Iconography

One custom set of 76 rounded, filled icons on a 24 dp grid with 2.5–3.4 dp round-capped strokes (see Icons). Icons take `currentColor`; two-tone icons use a second tone and surface-coloured cut-outs. Game icons have fixed meanings: `star` Perfect, `check-circle` Great, `target` Close, `reroute` Miss, `flame` streak, `fuel` lives. The tabs: `road` Today, `map` Explore, `chart` Progress, `user` Me. Icon-only controls always have a screen-reader label and a 48 dp target.

## Mascot and illustration

**Pindo** is the pin, alive. Six expressions (happy, cheering, thinking, encouraging, sleepy, proud) cover onboarding, empty states, celebrations and notifications. Pindo never looks disappointed in the player. Illustrations are flat and chunky, built from city tiles, roads with lane dashes, pins and icons, every fill a token. See Mascot and Illustration.

## Motion, sound and haptics

Springy and fast: press 80 ms, cards 280 ms, the pin drop 520 ms with one bounce. Three celebration sizes (small for Close, medium for Great and badges, big for Perfect and Session done) keep rewards special. Every animation has a calm alternative when reduce motion is on. Every key event has a sound and a haptic, behind separate Sound and Haptics toggles. Full spec in the Motion, sound & haptics section and the Motion and Celebrations cards.

## Layout

- Phone-first, 360 dp reference width; content scales to tablets with a 600 dp max column for sheets and lists.
- Primary actions sit at the bottom in the thumb zone: Confirm, Next, Continue are full-width 56 dp buttons 26 dp above the safe area.
- Four tabs in the bottom nav: **Today · Explore · Progress · Me** (see Bottom nav).
- A v3 session's top bar is Leave · 12-block session bar · time left. The Explore quiz top bar is Leave · 10-step question bar · Fuel; until Fuel exists that slot stays empty (Explore has no points). Today's top bar: city switcher · streak; Explore's: city switcher · settings.
- Every map screen shows the map attribution chip ("© OpenStreetMap contributors, © CARTO").
- The MVP screens (welcome, home, city, area, difficulty, quiz, reveal, results with retry, settings), the earlier release plan (R2–R5) and their Flutter notes are in the MVP screens section, kept as a record; v3 replaces the learning mechanics of R3–R5.
- Minimum touch target 48 dp (`size.tap.min`) for everything interactive, including map controls and exit buttons.

## Files

- `tokens.json`: every token (primitive, semantic, component; light and dark), dot-named for direct mapping to Dart.
- `handoff/pindoro_tokens.dart`: Dart constants generated from tokens.json (see Flutter handoff).
- Asset groups: **Logos** (wordmark, mark), **App icon** (iOS light/dark/tinted, Android adaptive layers and themed icon, Play Store), **Splash**, **Mascot**, **Icons** (76 SVGs).
- `components/bundle.css` and `components/bundle.js` only power the previews on this page (web stand-ins for the Flutter widgets); they are not shipped in the app.
