# TODO after Milestone 1

## Placeholders to replace

- **Georgian translation** — `apps/mobile/lib/l10n/app_ka.arb` is a draft; it needs a native
  review.
- **Designed in text, not drawn** — the 2026-11-07 design pass (map greys, 104-area picker, city
  pack download, Miss directions) lives in `tokens.json` and `docs/design/v1-screens.md`; the
  claude.ai canvas has no boards for it yet (chips at both zoom bands, district names along
  outlines, narrow with Undo, All areas, pack download and failure, offline Vake). The pack
  download's city scene, Connecting state and server-failure copy (2026-11-13) are local only:
  bring them to the canvas (26–30) and the design system's `v1-screens.md`, and add
  `color.illustration.block-alt` and `color.illustration.park` (in `app.json`) to `tokens.json`.
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
  - A red bar on failure: the bar goes when a download fails; Pindo and the copy carry it. The
    done moment is the city scene's (Pindo cheers, the star lands), not a check on the bar.
  - A minimum time on screen for a Try again that fails at once, and an exit transition from the
    city scene into the screen behind it (the screens swap as soon as the pack opens).
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
  - Today has no Turns tile (M5).
  - `StatChip`, `NextReviewChip` and `IntroSheet` have widget tests but no goldens yet.
- v3 progress and settings (M2), left out on purpose until the milestone named:
  - Progress district: no Gateways solid or Landmarks tiles (M5); neighbourhood rows open no
    detail. Its Mastered definition line says only "3 months or more".
  - Learning settings: no Turns and routes or Speak your answers toggles (M5, M6).
  - The home and work picker shows the map and the nearest neighbourhoods as chips, without the
    "More" list and search of the design's area selector.
  - Today has no "Now learning" and gateway rows (M5).
- v3 replacing the old game (M3), left out on purpose:
  - Explore keeps its own known-street counts (best tier in Explore and the old lessons); the
    rest of the app counts from the cards.
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
  - Today has no "Now learning" and gateway rows; the full Tbilisi format 5 pack isn't published
    (`just pack tbilisi` on the server).

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

- v3 street photos (M7), left out on purpose:
  - No "The view from the other end" card on the S1 result (the board's): photos are taken only
    driving in to a junction item, so the other way usually has none.
  - The credit is text ("© Mapillary · CC BY-SA 4.0 · author", opening the photo's page), with no
    Mapillary logo: the design system has none.
  - A newer photo pack installs only when Street photos is turned on again; the background pack
    refresh doesn't fetch it (a few hundred MB).

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

## Designed, not scheduled

In the design system but in no release on the canvas Roadmap:

- Onboarding illustration scenes and illustrated empty states. The pack download's city scene is
  the first illustration (`features/pack/ui/widgets/city_scene.dart`).
- Fuel (lives).
- Pindo as one rigged Rive or Lottie file instead of static expressions.

## Next release candidates (design on claude.ai first)

The v3 learning plan (`docs/learning/PLAN.md`) holds the route work (one-way streets, junctions,
landmarks, recitals and drives) and the curriculum order.

- Accounts beyond one backup (the Roadmap's R5 card: not designed yet). Built without a design
  (2026-11-13), with a recovery code instead of an email reset. Left out on purpose: one phone at
  a time (a sign-in elsewhere signs the old phone out, which then says so; no merging of two
  phones' progress); the account token sits in the progress database, so Android Auto Backup and
  iCloud device backups carry it; the snapshot is gzipped on the UI isolate; no
  cap on the number of accounts or their total backup size; the username and password fields
  lose their screen-reader name once typed in (SearchField's hint), parked with the other
  screen-reader work.
- A second city, or a Roadmap MVP card that no longer promises "any city or town from
  OpenStreetMap".

## Data / pipeline

- Neighbourhoods come from OSM `place=quarter|neighbourhood`; `curation/neighbourhoods.geojson` is
  empty and only needed for areas OSM lacks.
- 11 Tbilisi streets fall in gaps between raion polygons and belong to no district.
- A retired street id is never revived; a street that reappears in OSM gets a new id.
- Old pack versions are never pruned from `PACKS_DIR` (the app keeps its 2 newest).
- Downloads stream to disk, but a street pack is gunzipped in memory; stream that too if packs
  grow past a few MB.
- Decide a refresh cadence for the Georgia tiles (Protomaps daily builds); in production only a
  Deploy run with the tiles box ticked downloads them again.
- Street photos (M7): no photo pack is built yet; it needs the `MAPILLARY_TOKEN` secret and a
  Deploy run with `photos` set (`docs/deploy.md` § 8). The coverage report then answers SPEC §15's
  Mapillary question. Panoramas are reprojected assuming a level horizon (no pitch/roll from the
  source), and only junction-item approaches are photographed, so a tier A/B street with none gets
  no S1 photo.

## Infra / CI

- CI runs on GitHub Actions (kume1a/pindoro); `act` reproduces it locally.
- Flutter is pinned to 3.47.9 in CI and `just goldens`; the bootstrap machine ran a 3.41.2 checkout
  (Dart 3.13). Align local Flutter with the pinned version, and bump both together later.
- Production server: live since 2026-11-11 behind the host's shared tunnel; the Deploy workflow on
  its self-hosted runner deploys `prod`, builds missing packs and refreshes them monthly
  (`docs/deploy.md`).
- The private Panoramax (profile `panoramax`) hasn't run on the server yet; its pictures volume is
  not in the nightly backup (`docs/deploy.md` § 8). Blurring runs on the CPU.
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
