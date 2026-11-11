# TODO after Milestone 1

## Placeholders to replace

- **Sound kit** — the design's 14 sounds don't exist yet; the Sound toggle and `GameFeedback`
  are in place, so add an audio player there once the files are designed.
- **Georgian translation** — `apps/mobile/lib/l10n/app_ka.arb` is a draft; it needs a native
  review.
- **Designed in text, not drawn** — the 2026-11-07 design pass (map greys, 104-area picker, city
  pack download, Miss directions) lives in `tokens.json` and `docs/design/v1-screens.md`; the
  claude.ai canvas has no boards for it yet (chips at both zoom bands, district names along
  outlines, narrow with Undo, All areas, pack download and failure, offline Vake).
- **Left out of that pass, on purpose:**
  - Download progress in the City row: tapping a city opens the Area picker at once, so the row is
    gone before a bar could show. The wait shows in the Area picker's panel instead.
  - Chips that step aside instead of hiding: MapLibre only shifts text labels
    (`text-variable-anchor`), and the map style has no fonts, so chips are images. It would need
    FiraGO map glyphs generated and served, and every chip redrawn as map text.
  - A city outline on the empty map while the pack downloads: the catalog has only a bbox, so it
    would need the boundary in the manifest, the API and the app, for a wait of 1–2 s.
  - A "Free up space" button and a free-space check before downloading: native code (Android
    `StorageManager.getAllocatableBytes`, `ACTION_MANAGE_STORAGE`) for a 1 MB pack. A full phone
    is caught when saving fails and gets its own copy.
  - The progress bar's finishing touches from the research (red on failure, a check when done):
    the panel goes away as soon as the pack opens.
- Map labels (area names, the distance chip) are images drawn by `MapChip`, because the self-hosted
  map style has no glyphs.

## Gameplay

- Offline maps: the city's tiles (zoom 10–15, about 1 500 tiles for Tbilisi) download in the
  background once a downloaded pack opens, as a MapLibre offline region. The region is never
  refreshed; delete it when `georgia.pmtiles` updates (no tiles version to compare yet).
- The offline toast probes the API's `/health`; there is no live connectivity listener.
- Keyboard and D-pad focus: the design system's custom controls (`Tappable` in pindoro_design)
  take taps and screen-reader taps but can't be focused from a keyboard; `color.focus.ring` is
  unused. Build `Tappable` on `FocusableActionDetector` with a focus-ring outline when needed.
- Streak (R2), left out on purpose:
  - The streak sound ("whoosh + ding") waits for the sound kit.
  - The reminder is fixed at 19:00 (the board has no time picker).
  - The Streak calendar shows the current month only (the board has no month arrows).
  - The pill doesn't turn "at risk" at 18:00 while the app stays open; it updates on the next
    resume or progress change.
  - Days before the R2 update aren't backfilled: streaks start with it.
  - iOS: the reminder has never run on a device; foreground presentation
    (`UNUserNotificationCenter` delegate in `AppDelegate`) isn't set up.
- Pit stop (R3), left out on purpose:
  - Answers from before the R3 update don't enter the Pit stop (it starts empty).
  - The Results chip "n to your Pit stop" isn't tappable; the Pit stop tab is the way in.
  - Review items of a retired street stay in the table; readers skip them (`dueIn`).
- Tabs and Me (R4a), left out on purpose:
  - Only Best streak opens something (Streak); the lists behind the other tiles don't exist yet.
  - A played city whose pack isn't on the phone is left out of Me's cities.
  - After a Pit stop round, Done still lands on Free play (with the Home intro), not the Pit stop
    tab.
- Course and lessons (R4b), left out on purpose:
  - Cities without district polygons get no course (units by rings from the centre).
  - Lesson titles and where sentences are generated; no editorial text per district.
  - The course is rebuilt from the pack each time: a pack update that reorders a raion's streets
    changes its lessons (results keep their lesson numbers).
  - The locked-stop bubble always sits centred under the stop's row, not on the stop.
- Road trips (R4c), left out on purpose:
  - The tier sheet's detour sentence ("Turning north for the main road added 212 m") and its ink
    chip at the detour.
  - The lane loader while checking: the best route is computed at once.
  - One-way streets are ignored. The graph holds the pack's named streets only, so unnamed links and
    ramps are missing and some best drives detour around them.
  - B pops when reached but has no ring pulse.
  - Units have no titles: the locked unit's sheet, Unit complete's signpost and the Unit guide
    show the district.
  - A killed Final drive keeps its passed trips but drops the trip in progress.
  - A raion with no 800–2 500 m trip gets lesson-length ones (500–1 500 m) in its Final drive, so
    its unit can still be passed; the design only has the longer drive.
  - R4b progress isn't carried over: a unit opened by its lesson 6 locks again until the Final
    drive before it passes.
  - Jump ahead and the R4-61 storyboard have no widget test (the bundled fixture has one raion);
    pindoro_core tests the rules and the emulator check covered them.
  - Packs grew to about 2.3 MB gzipped (a street UUID on each of about 16 000 edges); reference
    streets by row number if pack size starts to matter.
- First launch (R4d), left out on purpose:
  - The start district can't be changed later. A new city's course starts at the raion of its last
    Free play area, without the picker.
  - Placement covers the open city when What's new shows; other cities' courses start unplaced.
  - The picker describes a district by its direction from the centre, not a hand-written line
    ("old town hills").
  - The "Start here" coach mark has no seen flag: it shows on each launch until the city has a
    lesson result.
  - A city without raions never gets a course row: What's new would show on every launch there and
    a new player would return to Welcome. No catalog city lacks raions today.
  - "Show me my path" shows nothing while placement is worked out (about a second for Tbilisi).
  - The Path builds every unit so it can scroll to a current stop far down; fine for about 10
    units, a city with many more needs a jump to an estimated offset first.

- Finishing v2.0 (R4e), left out on purpose:
  - Starting a lesson doesn't cache its streets, road graph and tiles (zoom 14–17): it needs the
    connection the Path had.
  - Hear the name shows only where the device has a voice for the name's language (often not for
    Georgian, especially on iOS); there is no recorded fallback.
  - A pack update between an app kill and the next launch starts the killed lesson over.
  - The Unit guide's tip comes from the streets' main direction; no hand-written tip per district.

- Leagues (R5), left out on purpose:
  - No sign-in and no progress sync across devices: a new phone or a reinstall starts a new player.
  - League names aren't moderated and can't be reported.
  - The server trusts the app's XP; there is no cheat detection.
  - XP synced after Monday 00:00 (Tbilisi) for the week before is lost; so is XP earned offline
    that week and synced only after it ends.
  - No "You moved up" moment at the week's end; the header just shows the new league.
  - The token sits in the app's database, not the keychain.
  - The Results chip shows after Free play rounds only (as designed); lessons don't show a move.
  - A league week only fills from players syncing; with few players, leagues stay small (no
    demotion zone below 26 players).

- Badges, left out on purpose:
  - The "unlock chime" waits for the sound kit.
  - No badge detail screen, no sharing, and the earned date shows nowhere.
  - Explorer is "know streets in 5 districts", not the design's "3 cities": the catalog has one
    city. Navigator's sheet says the condition, not the district ("you mastered Vake").
  - Pit crew counts streets cleared from the update on: clearings weren't recorded before.
  - A badge earned on a screen that was killed, or in a Final drive left before Unit complete,
    gets its sheet at the next end screen. The launch award is quiet and only runs while the
    player has no badges.
  - Badge stats count only cities whose pack is on the phone (as Me does).
  - Chests, the design's other reward moment: nothing in the app is a chest.

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
    fingers" hint, a district's state word, a locked stop's "Finish lesson n to unlock" and
    descriptions of Pindo in empty states.
- Motion and celebrations (`docs/design/motion-sound-haptics.md`):
  - No district-mastered moment: no fill wipe, outline and check, no heavy haptic, no big
    celebration for the first mastered district.
  - A round can get two big celebrations: Results also goes big on a flawless round (not in the
    design).
  - Streak milestones (7, 30, 100, 365) play the medium celebration, not the big one; Lesson
    complete plays no milestone or streak haptic.
  - The pin can't be dragged (lift 12 dp, follow the finger); taps only.
  - Missing details: the pin drop's squash, shadow and tip ripple; Confirm's halo; Close's ring
    pulse at the pin; Pindo's hop and jump (Pindo is static, `sleepy` unused); the level-up
    shield stamp (0.92 → 1.22, −6°) and Pindo's sticker outline; the round XP pill counting up;
    the Path stop unlock's lock drop.
  - Reduce motion still animates the map camera and the question bar's fill.
  - No haptic on Next; the error haptic is `heavyImpact` rather than `vibrate()` on Android.
- Smaller:
  - The map makes room for the road-trip tier sheet when the replay starts, not with a 60 dp pan
    after it.
  - Upgrade maplibre_gl 0.27.1 → 0.28.0 (Flutter 3.44+, iOS 15.5, SwiftPM; Android points become
    logical pixels, calls throw instead of returning false, channel mocks need a fake
    `MapLibrePlatform`).
- Ops for sideloading:
  - Committing the monthly street ids back to git is still by hand (`docs/deploy.md` § 6); the
    timer only copies them to `infra/backups`.
  - No crash reporting (`FlutterError.onError`, `PlatformDispatcher.onError`); without paid cloud,
    the API's log could take the reports.
  - Rate limits are in memory and cover signups, renames and the XP sync only; `/v1/catalog`
    (reads every manifest per request) and `/health` have none, and the Cloudflare cache rule for
    tiles and packs is optional in `docs/deploy.md`.
  - No alerting: the systemd services have no `OnFailure=`, a failed backup only logs, and a down
    server tells nobody. Backups stay on the same machine and a restore has never been tried.
- Accepted divergences: the Home Pit stop card became the Pit stop tab's badge (R4); the cold start
  is a Flutter overlay (about 1.9 s) rather than `FlutterNativeSplash.preserve()` with the wordmark
  on the native splash.

## Designed, not scheduled

In the design system but in no release on the canvas Roadmap:

- Onboarding illustration scenes and illustrated empty states ("no league yet", "city not
  downloaded").
- A player profile behind a tapped league row.
- Fuel (lives).
- Pindo as one rigged Rive or Lottie file instead of static expressions.

## Next release candidates (design on claude.ai first)

From the product plan ("Learning Every Tbilisi Route"), which the course only partly follows:

- Free point-to-point road trips: a random A → B anywhere in the city, the plan's daily drill.
  Road trips exist only inside lessons and Final drives.
- One-way streets and turn bans in road trips (edges are undirected today); the plan calls the Old
  Town and Sololaki one-ways the hardest part.
- A skeleton unit before the districts: the bridges in order and the main roads that feed them.
- Landmarks (metro stations, malls, bus and railway stations) as targets and trip ends; packs have
  none.
- Course order: centre outward, alternating river banks, rather than nearest-first from the picked
  district.
- Accounts and sync across devices (the Roadmap's R5 card: not designed yet).
- A second city, or a Roadmap MVP card that no longer promises "any city or town from
  OpenStreetMap".

## Data / pipeline

- Neighbourhoods come from OSM `place=quarter|neighbourhood`; `curation/neighbourhoods.geojson` is
  empty and only needed for areas OSM lacks.
- 11 Tbilisi streets fall in gaps between raion polygons and belong to no district.
- A retired street id is never revived; a street that reappears in OSM gets a new id.
- Old pack versions are never pruned from `PACKS_DIR` (the app keeps its 2 newest).
- Pack downloads hold the whole `.gz` in memory; stream to disk if packs grow past a few MB.
- The API's `city`/`district`/`street`/`street_district`/`pack` tables exist but nothing fills
  them yet (`publish` only writes files).
- Decide a refresh cadence for `infra/tiles/georgia.pmtiles` (Protomaps daily builds).

## Infra / CI

- CI runs on GitHub Actions (kume1a/pindoro); `act` reproduces it locally.
- Flutter is pinned to 3.47.9 in CI and `just goldens`; the bootstrap machine ran a 3.41.2 checkout
  (Dart 3.13). Align local Flutter with the pinned version, and bump both together later.
- Production server: the stack sits behind the host's shared tunnel and deploys from `prod` on a
  self-hosted runner. Once the routes, runner and variables exist, push `prod` and run
  `just server-setup` once (`docs/deploy.md` §§ 2–4).
- **No App Store or Play Store release is planned** (decided 2026-11-11): friends sideload the APK.
  Create the Android signing key and `key.properties` once, then
  `just release apk <public host>` (`docs/deploy.md` section 9).
- Parked, store-only, not a priority: a privacy policy, `PrivacyInfo.xcprivacy`,
  `CFBundleLocalizations` and a Georgian location prompt, the iPad device family and
  `DEVELOPMENT_TEAM`, a release workflow (fastlane, Play/TestFlight upload), the Play data-safety
  form and Android auto-backup of the league token.
- iOS is built unsigned in CI (macOS runner) and has run on the simulator (iPhone 16, iOS 18.6),
  never on a device. A reminder after notifications are allowed hasn't been checked there.
- `flutter_tts` has no Swift package, so iOS builds add CocoaPods for it on the fly (`Podfile`,
  Pods in the Xcode project); none of that is committed. Commit it, or swap the plugin, if a
  signed release needs a reproducible Pods setup.
- Move `drizzle-kit` to 1.0 once it is stable: it drops `@esbuild-kit`, which brings in the old
  esbuild behind the dismissed Dependabot alert #1.
- Dependabot ignores Node and PostGIS major versions: bump those by hand (PostGIS needs a dump and
  restore).
