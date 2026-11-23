# TODO after Milestone 1

## Placeholders to replace

- **Georgian translation** — `apps/mobile/lib/l10n/app_ka.arb` is a draft; it needs a native
  review.
- **Left out of the 2026-11-07 design pass (area picker, city pack download), on purpose:**
  - Download progress in the City row: tapping a city opens the Area picker at once, so the row is
    gone before a bar could show. The wait shows in the Area picker's panel instead.
  - Area chips that step aside instead of hiding: MapLibre only shifts text labels
    (`text-variable-anchor`). Martin now serves FiraGO glyphs (street and place names are map
    text), so the area picker's chips could be redrawn as map text too.
  - A city outline on the empty map while the pack downloads: the catalog has only a bbox, so it
    would need the boundary in the manifest, the API and the app, for a wait of 1–2 s.
  - A "Free up space" button and a free-space check before downloading: native code (Android
    `StorageManager.getAllocatableBytes`, `ACTION_MANAGE_STORAGE`) for a 1 MB pack. A full phone
    is caught when saving fails and gets its own copy.
  - A red bar on failure: the bar goes when a download fails; Pindo and the copy carry it. The
    done moment is the city scene's (Pindo cheers, the star lands), not a check on the bar.
  - A minimum time on screen for a Try again that fails at once, and an exit transition from the
    city scene into the screen behind it (the screens swap as soon as the pack opens).
- Area names and the distance chip are images drawn by `MapChip`; street, place, neighbourhood
  and river names are the basemap's own text (FiraGO glyphs from Martin).

## Gameplay

- Offline maps: the city's tiles (zoom 10–15, about 1 500 tiles for Tbilisi) download in the
  background once a downloaded pack opens, as a MapLibre offline region. The region is never
  refreshed; delete it when `georgia.pmtiles` updates (no tiles version to compare yet).
- The offline toast probes the API's `/health`; there is no live connectivity listener.
- Keyboard and D-pad focus: the design system's custom controls (`Tappable` in pindoro_design)
  take taps and screen-reader taps but can't be focused from a keyboard; `color.focus.ring` is
  unused. Build `Tappable` on `FocusableActionDetector` with a focus-ring outline when needed.
- Streak (R2), left out on purpose:
  - The reminder is fixed at 19:00 (the board has no time picker).
  - The Streak calendar shows the current month only (the board has no month arrows).
  - The pill doesn't turn "at risk" at 18:00 while the app stays open; it updates on the next
    resume or progress change.
  - Days before the R2 update aren't backfilled: streaks start with it. Days counted under the
    old XP goal stay counted.
  - iOS: the reminder has never run on a device; foreground presentation
    (`UNUserNotificationCenter` delegate in `AppDelegate`) isn't set up.
- Tabs and Me, left out on purpose:
  - Only Best streak opens something (Streak); the lists behind the other tiles don't exist yet.
  - A played city whose pack isn't on the phone is left out of Me's cities.
- Hear the name shows only where the device has a voice for the name's language (often not for
  Georgian, especially on iOS); there is no recorded fallback.

- Badges, left out on purpose:
  - No badge detail screen, no sharing, and the earned date shows nowhere.
  - Explorer is "know streets in 5 districts", not the design's "3 cities": the catalog has one
    city. Navigator's sheet says the condition, not the district ("you mastered Vake").
  - Badges are awarded on Explore's Results only; one earned in a session gets its sheet at the
    next Results. The launch award is quiet and only runs while the player has no badges.
  - City memory milestones are reached on the open city only.
  - Badge stats count only cities whose pack is on the phone (as Me does).
  - Chests, the design's other reward moment: nothing in the app is a chest.

- v3 session (M1), left out on purpose until the milestone named:
  - The Mix-up sentence names the hit street and the way to the answer, but not the contrast line
    ("The 4th is the next lane west, before the bend").
  - The intro's "where" sentence doesn't place a lane on its parent ("the 4th lane off 26 May
    Street, counting from the west"), and the plate doesn't add the district for a shared name.
  - Known-street chips use the full name, not the short form ("Chavchavadze Ave", "1st").
  - The Mix-up reveal paints both streets at once (no cobalt-then-yellow paint), and Session done
    shows City memory as a number, without the card-size memory bar.
  - `StatChip`, `NextReviewChip` and `IntroSheet` have widget tests but no goldens yet.
- v3 progress and settings (M2), left out on purpose until the milestone named:
  - Progress district: no Gateways solid or Landmarks tiles (M5); neighbourhood rows open no
    detail. Its Mastered definition line says only "3 months or more".
  - Learning settings: no Turns and routes or Speak your answers toggles (M5, M6).
  - The home and work picker shows the map and the nearest neighbourhoods as chips, without the
    "More" list and search of the design's area selector.
- v3 replacing the old game (M3), left out on purpose:
  - Results' "+n streets known" pill and the Explorer and Navigator badges still count Explore's
    own known streets (best tier in Explore and the old lessons); every tab counts City memory
    (v3.1 decision 2; the Explorer rule is left as built on the canvas).
  - The Georgian draft of the new strings needs the native review like the rest.
- v3 name, ends and drills (M4), left out on purpose:
  - The sweep's lanes are traced like known streets (grey, solid), not dashed, and its sockets
    have a solid outline; drill chips and sockets show full street names.
  - Bearings point from the city centre, not a landmark, until M5 brings landmarks.
  - The bearing sheet's title reads the tier label as elsewhere ("Great! · 18° off").
  - No goldens for the session's task views; `BearingDial` has goldens.
- v3 route items (M5), left out on purpose:
  - Personal landmarks get L cards but don't take over the OSM landmark on J cards (SPEC §9
    "always preferred on their junction").
  - Way-via turn restrictions are left out of the pack.
  - The J card names no sibling junction it's confused with; the gateway, bridge and landmark
    cards use existing widgets (the design system has no components for them).

- v3.1 tabs, filled (canvas page "v3.1 · Tabs, filled"), left out on purpose:
  - Only Explore's map is a live MapLibre map; Today's neighbourhood map and Progress's district
    map are painted (no basemap), so a tab never holds more than one platform view. The district
    map hides a name wider than its district.
  - Explore offline doesn't dim the districts outside the pack: the bundled Vake pack has no
    others. Tapping the open Explore tab doesn't scroll its sheet up. The screen keeps its
    `HomeScreen` name (the canvas renames it ExploreScreen).
  - After a round Explore counts City memory up with a "+n" pill; the district fills don't fade
    in. The figure starts from City memory replayed to the round's start.
  - "Watch out for" says "Mixed up yesterday" without the board's "back today side by side": the
    planner doesn't pair mix-ups. Recall's empty state says "Shows after your first reviews",
    not "after 7 days": the rate shows as soon as reviews exist.

- v3 recitals and drives (M6), left out on purpose:
  - Speech (SPEC §11): no Speak mode, transcript chips, Vosk model download or self-grade
    fallback. The one plugin claiming iOS, `vosk_flutter_service` 0.1.3, downloads a prebuilt
    `libvosk.xcframework` from its maintainer's GitHub release (`dart run vosk_flutter_service
    install -t ios`); try it on a phone first. The design's TranscriptChips and the 104 dp mic
    button come back with it, and DriveScreen's "Plan it out loud first".
  - The recital result paints no offending segment in Miss red (a chip names it), the decisions
    list has no "See all turns", and "Practise that turn" is automatic: failed turns join the
    session as relearns.
  - A drive's track is drawn as the dashed player route, not solid cobalt with a halo, and its
    U-turn is a map chip, not the u-turn marker. The track is kept in memory only.
  - Hesitations are counted in the drive review's sentence but not marked on the map.

- v3 tuning (M8), waiting for real reviews:
  - Fit weights once the log has about 1 000 reviews that moved a card (`just fsrs-fit`, then
    Learning settings → Memory model), check the calibration bins, and revisit SPEC §13.
  - Tier C relief applies to session answers only; Explore answers keep 90 %.
  - The Memory model's bars show the share recalled per bin without the predicted line beside
    them (the design system's bars have none); the rows give both numbers.

## Gaps found 2026-11-11 (design vs code)

Not left out on purpose: found by comparing the app with `docs/design/*.md`, the claude.ai canvas
and the specs after R5. Fix them in roughly this order.

- Accessibility (`docs/design/accessibility.md`):
  - No list answer mode (four candidate areas as buttons); Accessibility has only Choose turns
    from a list.
  - The pin can't be moved without touch (arrows 8 dp, Shift 40 dp, Enter confirms).
  - The area rectangle's handles have no arrow-key 50 m steps.
  - At 200 % text the compact plate cuts the name with "…" and the reveal sheet never shows the
    full name.
  - Parked, not a priority (2026-11-11: nobody playing uses a screen reader): the pin's label and
    "Pin dropped, …" announcement; focus moving to the plate on a new street and to Next after
    the reveal; a screen-reader node for the area rectangle's handles; the map's "Drag with two
    fingers" hint, a district's state word and descriptions of Pindo in empty states.
- Motion and celebrations (`docs/design/motion-sound-haptics.md`):
  - No district-mastered moment: no fill wipe, outline and check, no heavy haptic, no big
    celebration for the first mastered district.
  - A round can get two big celebrations: Results also goes big on a flawless round (not in the
    design).
  - Streak milestones (7, 30, 100, 365) play the medium celebration, not the big one.
  - The pin can't be dragged (lift 12 dp, follow the finger); taps only.
  - Missing details: the pin drop's squash, shadow and tip ripple; Confirm's halo; Close's ring
    pulse at the pin; Pindo's hop and jump (Pindo is static, `sleepy` unused) and Pindo's sticker
    outline.
  - Reduce motion still animates the map camera and the question bar's fill.
  - No haptic on Next; the error haptic is `heavyImpact` rather than `vibrate()` on Android.
  - Sound kit: brighter and glassier than the design's "warm and wooden" (synthesized FM plucks and
    bells in C major, pitch-glide pops, a ComfyUI wooden tok under the pin drop) for a more
    polished game feel. One WAV for both platforms, not OGG + CAF, at -18 LUFS rather than -16
    (measured over 4 s, since EBU R128 gates sub-second clips out). Events the kit has no sound for reuse one: the city pack arriving and badges
    play `unlock`.
    No new-street chime, replay whoosh, streak-milestone or district fanfare.
- Smaller:
  - Upgrade maplibre_gl 0.27.1 → 0.28.0 (Flutter 3.44+, iOS 15.5, SwiftPM; Android points become
    logical pixels, calls throw instead of returning false, channel mocks need a fake
    `MapLibrePlatform`).
- Ops for sideloading:
  - No crash reporting (`FlutterError.onError`, `PlatformDispatcher.onError`); without paid cloud,
    the API's log could take the reports.
  - Rate limits are in memory and cover signups and renames only; `/v1/catalog`
    (reads every manifest per request) and `/health` have none, and the Cloudflare cache rule for
    tiles and packs is optional in `docs/deploy.md`.
  - Little alerting: GitHub emails a failed Deploy run, but a failed nightly backup only logs and
    a down server tells nobody. Backups stay on the same machine and a restore has never been
    tried.
- Accepted divergences: the Home Pit stop card became the Pit stop tab's badge (R4); the cold start
  is a Flutter overlay (about 1.9 s) rather than `FlutterNativeSplash.preserve()` with the wordmark
  on the native splash.
- Changed in the app, not yet on claude.ai, since the 2026-11-20 sync (the design system's "App
  sync" section, the canvas's board C-99). List new changes here, and new tokens in
  `packages/pindoro_design/tokens/app.json`, for the next sync.
  - **Drive screens (M9 step 3b, 2026-11-21)**, built from the design system's drive components;
    where they differ from boards V32-20 to V32-41:
    - Recovery shows the next turn's DriveGlyph at 220 dp over the street, not the canvas's
      painted junction with the car on its disc.
    - The Guided map draws the route yellow on ink, puts no landmark badge at the corner, and
      dims under a veil while GPS is lost (the car stays as it is, no accuracy ring).
    - The stopped bar's Route button is left out at Off (SPEC §16.23 item 128). Off's Rescue offer
      is a card with the text and a 56 dp button, without the rescue glyph.
    - Roundabout glyphs and "Exit 3 onto" are unused: the road graph doesn't know roundabouts.
      Forks under 45° use keep left and right.
    - A word wider than the plate's line breaks between letters: Flutter doesn't hyphenate.
    - The bottom bar's trip block shrinks under 54 dp when the rescued mark, a camera and the sign
      share a narrow phone.
    - Coached's speaking bars move in a fixed wave while the voice speaks, not with its level.
    - "Now Coached" is a plate-coloured chip in `type.drive.read` for 4 s.
    - `PindoroButton` gained `large` (56 dp) and `iconOnly`, for the stopped bar.
  - **Drive setup, Route and learning (M9 steps 3c–5, 2026-11-21)**:
    - Where to (V32-10 `search`) is a SearchField over the pack's streets and places with the
      quick rows and Recent as ListRows; there is no "outside the pack" state: an offline app
      only knows the pack, so a place outside it can't be found at all (item 125's "found but not
      chosen" needs a geocoder).
    - Home and Work have their own picker (Settings → Driving and Where to's "Set your home").
    - The chosen destination is a ListRow with an edit button; the stopped bar's Route opens a
      parked screen with the destination left and a new one to search.
    - LevelSuggestion's reason shrinks when it doesn't fit beside the level.
  - **Preview, debrief, Past drives, Today and Progress (M9 steps 3c–5, 2026-11-21)**, from the
    design system's parked parts (synced 2026-11-21); where they differ from boards V32-10 to
    V32-71 and the parts' READMEs:
    - The plan and review map is the app's PindoroMap with the route in its answer paint
      (8 dp with chevrons, not 7 dp), the track a 4 dp solid line, and the start ring, flag,
      numbers and marks as Flutter widgets over it.
    - The debrief's offer shows only the start ring and the flag (no track or marks: they'd
      give the recall away). Each recalled turn is on the north-up map with the way in in
      cobalt and the ways on as ExitButtons in the sheet, not the canvas's heading-up card.
      "Show me" replaces the buttons when two ways on share a direction.
    - The summary keeps the reveal sheet's tier for every drive; only the Past drives list
      shows "No tier" for Guided. "Next time: try Quiet" has no button (the setup suggests it
      anyway).
    - Streets you drove says "Learned · Solid" or "Not yet", without "comes with the secondary
      roads".
    - Point to home has no "compass needs a moment" state: `flutter_compass` gives no accuracy
      here, so the arrow drags until the first heading arrives.
    - The preview opens from the setup only (not from the stopped bar's Route screen).
    - Today's nudge ("Home → Work can go Quiet") has no "Try Quiet next time" button: the
      setup suggests the level anyway. "Pick your two drives" lists the frequent routes at
      their suggested level (no new places yet) and shows until answered that week.
    - The route stair takes a month's last drive (SPEC §16.23 item 128), not the README's level
      most of its drives used.
    - The answer tray has no 1–6 or arrow keys and doesn't move focus to the first choice; the
      goal line's just-met dot doesn't bounce. In the sweep, a tap on a placed label doesn't send
      it back to the tray (another label dropped on its lane does).
  - **The Drive tab (SPEC §16.23 item 129, 2026-11-22)** was built in the app, not on the canvas:
    the canvas needs a Drive tab board and the five-tab bar. Home and Work are `StatTile`s (the
    minutes as the value, else the place's name; "Set your home" when unset), the rest is V32-10's
    Where to and V32-71's drives moved off Today. Choose on the map is Add landmark's map and
    panel (V3-32) with a destination's words.
  - **The setup's routes and the stepped preview (item 129, 2026-11-22)**, built in the app:
    - The setup is the plan map (routes: the picked one yellow, the others grey) over a panel
      with the destination, a `ListRow` per route (time · length, Fastest / Most familiar, the
      turns you know, a tick on the picked one), the level and the rules; V32-10 has no map and
      one route. The canvas and design system need a route card.
    - The preview steps (Show the turns, Back, Next) instead of V32-11's Pause and timed play.
    - The StoppedBar lost its grab handle: it suggested a sheet to drag, and there is none. The
      design system's StoppedBar still draws it.
    - With approximate location (item 131) the setup shows a `ListRow` "Precise location is off"
      (the `locate` glyph, a note on why, a tap asks for precise) under the destination.
  - **Guided, compact and movable (SPEC §16.23 items 116, 118 and 130, 2026-11-22/23)**, after
    test drives, with the player's own navigator as the model; boards V32-01 and V32-20 still
    draw the full-width 54/72 dp plate:
    - TurnPlate is a card in the top left (`radius.lg`, at most 55 % of the screen wide): the
      44 dp glyph beside the distance in `headline.lg`, the street in `title.lg`, a `label.lg`
      note with a 24 dp badge (the landmark, the heading), the lanes, and "then" as a chip under
      the card. The approach bar is gone (the distance counts down).
    - New: `LaneArrows` (`DriveLane`: a lane's arrows as turn angles and the one to take), 28 ×
      36 dp per lane, the arrow to take in `drive.plate.glyph`, the rest in
      `drive.plate.text-2` at `opacity.hatch`; and `turnArrowHeadPng`, the head of the turn arrow
      the map draws at the next decision (line `drive.plate.text` on a `drive.plate` casing).
    - DriveBottomBar floats over the map (`radius.xl`, 12 dp in from the edges): "3.4 km",
      "12:41" and "9 min" in `headline.sm` over a 4 dp progress line (`drive.plate.glyph` on
      `drive.plate.line`); stopped, a 48 dp `DriveBarButton` (End drive, ✕) at its right end.
      Coached, Quiet and Off keep StoppedBar.
    - Buttons at a touch (2026-11-23): new `DriveMapButton`, a 48 dp round on `drive.surface`
      in a `drive.surface-line` rim, in a right-hand column that pops in (scale + fade,
      `duration.base`) and goes 10 s after the last touch: routes (new DriveGlyph `routes`, a
      fork with one dim branch), Mute, the level (its icon) and `DriveCompass` (a 12 × 32 dp
      needle, north `drive.sign.ring`, south `drive.text`, a hole cut at its pivot) or
      `DriveRecentre` (the DriveGlyph `recentre` leaning 45° right). New `LevelPickerCard`
      and `RouteOptions` (rows of minutes, kilometres and "+3 min", a swatch in the line's
      colour, Change destination under them) over the bar. The canvas's StoppedControls row is
      gone.
    - New `SpeedNow` (the car's speed on a 64 dp ink disc) beside SpeedLimitSign (64 dp, figures
      32, three figures 26) in the top right, the camera badge under them. DistrictChip became
      `StreetChip`: the street driven, a 36 dp pill (`title.sm`, one line, ellipsis) centred
      above the bar. Coached, Quiet, Recovery and Off keep `type.drive.*`.
    - LaneArrows to one scale: a lane without a straight arrow bends near the top, its head
      level with a straight arrow's; with one, its turns branch half way up.
    - The map drags and pinches at any speed, and returns 10 s after the last touch; the
      compass turns it north up. The car sits on its road, the road ahead straight
      up, 70 % down the map (map padding), the route drawn ahead of it only (the canvas greys
      the road behind; here it is gone); until the car is on a road the route picked at setup
      shows.
    - New `ArrowMark`, the car as a navigation arrow (36 × 40 dp, `map.player.pin` with its
      right half in `map.player.pin-lip`, a 3 dp `map.player.halo` rim), laid flat on the map;
      the default, with `CarMark` a choice in Settings → Driving.
  - **Places, pins anywhere and the side of the road (SPEC §16.23 item 132, 2026-11-23)**, built
    in the app:
    - The setup's sheet opens short with a `SheetHandle` (tap or pull up for the suggestion,
      the level's note, the rules and the week). Its routes are `ListRow(dense: true)`, new:
      one 48 dp line, the title and the subtitle (the side, "+2 min", Fastest) each cut short
      past half the row, no tile.
    - Choose on the map's sheet: the place's `RowTile` glyph, name, "kind · district · km · min",
      then 16 dp `pin` and `timer` lines for the address and opening hours, and Call and
      Website as secondary buttons (no phone glyph in the set). A picked area is filled like the
      area picker's chosen area (`map.area.stroke`).
    - The navigation maps' generic place icon is Maki's `marker` on a civic disc (`poi-other`).
    - Route lines: 6 dp in a 2 dp casing on the plan maps, 8 dp in a 2 dp casing on Guided's
      map (the canvas draws 8 dp with a 4 dp casing).
  - **Guided's map like a car navigator's (SPEC §16.23 item 133, 2026-11-23)**, built in the
    app:
    - Tilt 55°, zoom 17, the car 75 % down; buildings raised from zoom 15 at half height in
      `map.vector.building` at the new app-only `opacity.building-raised` (0.5, `app.json`);
      house numbers in `map.vector.label` from zoom 16.5.
    - A traffic-light mark on each junction with lights: DriveGlyph `lights` at 24 dp in
      `drive.plate` with `drive.plate-glyph` lamps (new `driveGlyphPng`).
    - Route 10 dp in a 2 dp casing, the turn arrow 10 dp in a 3 dp casing; the car (`ArrowMark`,
      `CarMark`) and the arrow's head drawn 1.5× and facing the screen; the destination a
      `PinMark` in `map.answer.line` with a `map.answer.casing` lip, rim and dot.
    - `RouteOptions` gains `selected` (that row on `drive.surface-line`, its swatch
      `map.answer.line`, the rest `drive.plate-text-2`) and a primary Take this route button
      over Change destination; "Same time" when the minutes match.
    - Not done here, as they are design-system colours (claude.ai first, if wanted): the
      player's navigator's navy night map and grey turn card.
- Lakes are not named (Protomaps gives them no label point); Lisi Lake is the only one.
- Left out of the road-class pass, on purpose:
  - A "Your streets" round left half-way is not offered as Continue on Explore (Continue matches
    the chosen area).
- Left out of the field-feedback pass, on purpose:
  - No hard stop at the day's minutes: the relearn cap keeps sessions short instead.
  - Name it, both ends, drills and the other route cards keep their maps as they were (no place
    names, no Street View).
  - The player's own landmarks are not in the map data, so the map never names them.
- Navigation, left as it is on purpose (2026-11-23):
  - End drive still map-matches on the UI thread: with `RoadGraph.edgesNear` (a grid of about
    220 m cells) 2,000 fixes on a city-sized graph look up their edges in about 10 ms instead of
    800, so it no longer needs an isolate. Move it to one if long drives still stall End.
  - A coarse fix (item 131) is dropped, not down-weighted: a phone stuck on approximate location
    drives with "GPS lost" until precise is turned on.
- Places, left as they are on purpose (item 132, 2026-11-23):
  - Named buildings with no shop, amenity or office tag (a business centre, a residential
    complex) are not places; nor are OSM addresses without a name.
  - A tap inside a mall away from its icon drops a pin there (the stop is still by the nearest
    road); only the icon or its name picks the place.
  - Opening hours show as OSM tags them ("Mo-Fr 09:00-18:00"), with no "Open now".
  - The stop is by the road nearest the place, not its entrance (OSM entrances aren't loaded).
  - The bundled Vake fixture is still format 7 (no `poi`): `just fixture` rebuilds it from the
    server's live ids.

## Designed, not scheduled

In the design system but in no release on the canvas Roadmap:

- Onboarding illustration scenes and illustrated empty states. The pack download's city scene is
  the first illustration (`features/pack/ui/widgets/city_scene.dart`).
- Fuel (lives).
- Pindo as one rigged Rive or Lottie file instead of static expressions.

## Next release candidates (design on claude.ai first)

The v3 learning plan (`docs/learning/PLAN.md`) holds the route work (one-way streets, junctions,
landmarks, recitals and drives) and the curriculum order.

Both parked by the player on 2026-11-23 until they are designed on claude.ai:

- Accounts beyond one backup (the Roadmap's R5 card: not designed yet). Built without a design
  (2026-11-13), with a recovery code instead of an email reset. Left out on purpose: one phone at
  a time (a sign-in elsewhere signs the old phone out, which then says so; no merging of two
  phones' progress); the account token sits in the progress database, so Android Auto Backup and
  iCloud device backups carry it; the snapshot is gzipped on the UI isolate; no
  cap on the number of accounts or their total backup size; the username and password fields
  lose their screen-reader name once typed in (SearchField's hint), parked with the other
  screen-reader work.
- A second city (Tbilisi only for now), so the Roadmap MVP card should no longer promise "any
  city or town from OpenStreetMap": in the design hand-off.

## Data / pipeline

- Neighbourhoods come from OSM `place=quarter|neighbourhood`; `curation/neighbourhoods.geojson` is
  empty and only needed for areas OSM lacks.
- 11 Tbilisi streets fall in gaps between raion polygons and belong to no district.
- A retired street id is never revived; a street that reappears in OSM gets a new id.
- Old pack versions are never pruned from `PACKS_DIR` (the app keeps its 2 newest).
- Pack downloads hold the whole `.gz` in memory; stream to disk if packs grow past a few MB.
- Decide a refresh cadence for the Georgia tiles (Protomaps daily builds); in production only a
  Deploy run with the tiles box ticked downloads them again.
- Speed data (pack format 7) reads only `maxspeed` and `GE:*` zones: `maxspeed:forward/backward`,
  conditional limits and average-speed sections (`type=enforcement` relations) are left out, and a
  camera tagged `direction=forward/backward` counts as both ways.
- Lane arrows (pack format 8) come from the `turn:lanes` of the way into a junction, carried on
  every edge of that way: where a long way crosses minor junctions before the one its lanes are
  for, a decision there can show them (`laneMatchDeg` drops most such cases). `turn:lanes` on
  `*_link` approaches and `change:lanes` are not read.

## Infra / CI

- CI runs on GitHub Actions (kume1a/pindoro); `act` reproduces it locally.
- Flutter is pinned to 3.47.9 in CI and `just goldens`; the bootstrap machine ran a 3.41.2 checkout
  (Dart 3.13). Align local Flutter with the pinned version, and bump both together later.
- Production server: live since 2026-11-11 behind the host's shared tunnel; the Deploy workflow on
  its self-hosted runner deploys `prod`, builds missing packs and refreshes them monthly
  (`docs/deploy.md`).
- **No App Store or Play Store release is planned** (decided 2026-11-11): friends sideload the APK.
  Create the Android signing key and `key.properties` once, then
  `just release apk <public host>` (`docs/deploy.md` § 7).
- Parked, store-only, not a priority: a privacy policy, `PrivacyInfo.xcprivacy`,
  `CFBundleLocalizations` and a Georgian location prompt, the iPad device family and
  `DEVELOPMENT_TEAM`, a release workflow (fastlane, Play/TestFlight upload), the Play data-safety
  form and Android auto-backup of the account token.
- iOS is built unsigned in CI (macOS runner) and has run on the simulator (iPhone 16, iOS 18.6),
  never on a device. The iOS release workflow publishes a sideload IPA and a SideStore source
  (`docs/deploy.md` § 7) but has never run; the first SideStore install is the first device check,
  reminder included.
- `flutter_tts` has no Swift package, so iOS builds add CocoaPods for it on the fly (`Podfile`,
  Pods in the Xcode project); none of that is committed. Commit it, or swap the plugin, if a
  signed release needs a reproducible Pods setup.
- Move `drizzle-kit` to 1.0 once it is stable: it drops `@esbuild-kit`, which brings in the old
  esbuild behind the dismissed Dependabot alert #1.
- Dependabot ignores Node and PostGIS major versions: bump those by hand (PostGIS needs a dump and
  restore).
