# apps/mobile (Flutter app `pindoro`, org app.pindoro)

Offline-first: progress in Drift (SQLite), city data from read-only SQLite packs.

```
lib/main.dart                  open AppDatabase (openDatabase), pick the initial route, runApp; a
                               restart (restartProvider) boots again on a restored database
lib/app/                       shell: PindoroApp, router (the only place that imports screens),
                               TabShell (bottom navigation)
lib/core/                      shared by every feature: routes (paths + RoundSummary), config, format,
                               labels, settings, feedback (`feedbackProvider`: haptics and sounds per game event,
                               the end screens' count-up ticks), dialogs (`askChoice`), google_maps (Maps and Street
                               View links), location (+ the drive's background track), online, toast,
                               page scaffold, launch overlay, clock (clockProvider), hold (`ref.hold` keeps an
                               auto-dispose provider alive while a controller awaits it),
                               api_client (ApiClient + apiClientProvider, ApiException), restart, database/ (Drift tables,
                               migrations, .drift trigger, SettingsDao, database_file: the file, openDatabase,
                               swapInDatabase)
lib/features/<feature>/data/   DAOs, repositories, stores and providers over the database or packs
lib/features/<feature>/ui/     screens and controllers (Riverpod notifiers), their parts in ui/widgets/;
                               never Drift
                               features: progress (ProgressDao: Explore rounds, the answer log,
                               counted days, badges, legacy_known; streakProvider, Reminders, the
                               top bar and streak pill), pack (+ the road graph), map (the map, the
                               area picker map, the pin-drop view, the route draw layer of
                               the recital's Draw mode), learning (LearningDao: the v3 cards, review log,
                               mix-up pairs, learn_city and the player's landmarks
                               (`landmark_personal`, `personalLandmarksProvider`, the kind glyphs); pindoro_learning decides, it only
                               stores; the open city's cards, curriculum and placement (`cards.dart`), today's and Learn 10 more plans, carry-over, Progress data,
                               day marking and the reminder, Explore answers into cards, the route
                               book (`routeBookProvider`: the pack's J/G/B/C/L items and your
                               landmarks' L cards), recital runs (`runsProvider` makes route-book runs and weekly
                               random pairs, `todayRunProvider`), `drivingGraphProvider` (the
                               graph with the moves the player reported as legal: recitals and
                               drives grade on it), the evidence and runs tables; ui/: the City memory card, junction names), account (AccountApi, AccountDao, BackupSync, the
                               sign-in screen and Settings group), badges (stats, awards, the
                               shelf tile, the reward sheet and BadgeMoments), home (Explore),
                               setup (welcome, area, difficulty), quiz (Explore round),
                               results (results, street), settings (+ learning settings, the Memory model
                               screen: calibration, fitted FSRS weights, tier C relief; the
                               home/work picker and your landmarks: list, add on the map
                               snapped to a junction), streak, me, session (SessionController plays
                               today's plan and Learn 10 more round by round (Round done between
                               them, no timer), or the city's placement; each step's
                               SessionTask: a pin, Name it, both ends, the family sweep, the
                               crossings drill, a bearing, a route card (RouteView: the
                               turn on the heading-up map, gateway, bridge, connection, landmark) or a
                               recital (RecitalView: typed or drawn A → B, graded with the turns'
                               evidence and "Report this turn"), with their views over TaskScaffold;
                               intro (a leech's with its mix-up and note), reveal, Session done,
                               the placement result), today (the Today tab, "Drive this run today"), memory (the Progress
                               tab: overview and a district), drive (`/drive`: DriveController and
                               DriveScreen: setup, a background recording with no map, the matched
                               and graded review)
lib/features/quiz/ui/round_controller.dart   Explore round state machine; resumes from round_question + answers;
                               questions are NamedStreets (cityStreetsProvider); retries set round.retry_of;
                               each pin also feeds the learning cards (learnFromExplore)
lib/features/pack/data/pack_store.dart       catalog download + sha256/size check -> <docs>/packs/<city>/<version>.sqlite (2 kept)
assets/packs_fixture/          Vake fixture pack (built by `just fixture`, do not edit by hand)
assets/map_styles/             pindoro_{light,dark}.json (generated by `pipeline tiles`)
drift_schemas/                 committed schema dumps, one per schemaVersion
test/drift/                    generated schema helpers + migration test
```

## Conventions

- **Layers, lowest first:** `l10n` → `core` → `features/progress` → `features/pack` →
  `features/map` → `features/learning` (v3 cards, plans, Progress data) → `features/account` →
  `features/badges` → screen features (`home`, `setup`, `quiz`, `results`, `settings`, `streak`,
  `me`, `session`, `today`, `memory`) → `app` → `main.dart`. A file imports its own slice or a
  lower layer only; screen features never import each other. Something two features need moves
  down (to `core`, or to `progress`/`pack`/`map`/`learning`). `test/architecture_test.dart`
  enforces this, and that `ui/` never imports Drift; a new feature gets a layer there. Imports are
  `package:pindoro/...` (lint `always_use_package_imports`), so every import names its layer.
  `pindoro_core` and `pindoro_learning` are the domain layer, so features have no `domain/` folder.
- **Riverpod 3, no codegen.** Plain `Provider` / `FutureProvider` declared next to what they
  provide. `databaseProvider` is overridden in `main()` and in tests. Widgets read with
  `ref.watch` in build, `ref.read` in callbacks.
- **Routing:** go_router, paths in `Routes`. The tabs are a `StatefulShellRoute` (`TabShell`, a
  `FadeIndexedStack` of one page per branch): `/today` Today, `/` Explore (Home), `/progress`
  Progress, `/me` Me (design system Bottom nav); `go` to one of them switches tab, back on another
  tab goes to Today first, and each tab page gets its own `PrimaryScrollController` (a tap on the
  open tab scrolls it up). Every other route sits on the root navigator, over the bar:
  `/welcome`, `/area`,
  `/difficulty`, `/round` (`?round=` resumes, `?retry=` retries, `?learned=1` plays "Your
  streets": only streets with a P card), `/results`, `/streak`,
  `/settings`, `/settings/credits`, `/session` (`?placement=1` places, `?more=1` learns 10 more),
  `/progress/district?id=`, `/settings/learning`, `/settings/learning/anchor?which=`,
  `/settings/learning/landmarks`, `/settings/learning/landmarks/add`, `/settings/learning/memory`
  and `/drive`.
  `startLocation`: a player who placed a city (`learn_city`), finished a round or left one saved
  opens Today (Explore offers to continue the saved round); anyone else gets Welcome, whose Start
  learning leads to Today and its placement. The app is portrait only (Android manifest, iOS
  Info.plist). Footers end 12 dp above the bar on a tab (`bottomActionGap`).
- **Learning (v3, docs/learning/SPEC.md):** pindoro_learning decides everything; the app stores
  (`LearningDao`) and shows. Today plans with `todayPlanProvider` (curriculum candidates from
  `newCandidatesProvider(count)`, anchors from `learn_city`, log-median time estimates); placement
  and Learn 10 more are `SessionController.start` modes. Every learning answer (session, placement,
  Explore) calls `markDayIfCounts`, which writes `goal_day` once the day counts (SPEC §8).
  Explore pins go through `learnFromExplore` (§16.16). `carryOverProvider` turns the old game's
  knowledge (Explore answers and `legacy_known`, kept from the dropped lesson tables) into cards
  once per opened pack. Stream providers over Drift hang in widget tests' fake async: learning
  providers read with futures and writers invalidate them.
- **Account and backup** (`features/account`, rules in pindoro_core `progress/account.dart`):
  optional, for a lost or reset phone. Settings → Account (`AccountGroup`) opens `/account`
  (Sign in, Create account, or Forgot password? with the recovery code) and, signed in, Change
  password (`/account/password`), Sign out and Delete account. Create and a reset show the new
  recovery code once (`showRecoveryCodeDialog`). The `account` row is this phone's sign-in:
  username, token (null once a sign-in on another phone took over: Settings says so and the
  username prefills), `backedUpAt`, and `changedAt` (the first write the backup lacks).
  `BackupSync` (started by the app root) watches `tableUpdates()` while signed in: a minute after
  the last write it uploads `snapshot` (`VACUUM INTO` a copy beside the database file, the
  `account` row deleted from it, gzipped) to `PUT /v1/accounts/me/backup`; going to the background
  flushes a waiting upload, a launch uploads a set `changedAt`, offline/5xx/disk failures retry a
  minute later (a refused backup does not), and Settings' row backs up on a tap. Sign-in and reset
  only check the credentials; `AccountActions.takeOver` then restores a backup (asking first when
  `ProgressDao.hasPlayed`; Keep uploads this phone's over it): `stageRestore` streams the gzip
  into `pindoro.sqlite.restore` (refused past 64 MiB, a newer `user_version` or a failed
  `quick_check`), opens it with drift (migrating it) to save the account row, then
  `restartProvider` closes the database and `swapInDatabase` moves it in and boots again, putting
  the old file back if that boot fails. Tests
  override `apiClientProvider` and `databaseFileProvider`.
- **Badges** (`features/badges`): pindoro_learning `badgeProgress` and the City memory milestones
  are the rule (SPEC §16.8); stored ids are `BadgeId` names or `cityMemory<n>`.
  `readBadgeStats` reads the stats fresh from `ProgressDao` (`badgeCounts`, counted days), the
  learning cards and log, and the installed packs of played cities (`readInstalledPack`, never a
  download). `awardBadgesProvider` saves newly earned badges (`badge`, insert or ignore) and
  returns them. End screens (Results) mix in `BadgeMoments`: they award as they open and show a
  reward sheet per new badge after the arrival (`showBadgesAfter`). The app root awards quietly
  at launch only while there are no badges (past play). Me's shelf reads `badgesProvider`: the
  live badges, retired ones only when earned (a Retired pill), the highest City memory milestone
  and the next one locked; its New pills come from `newBadgesProvider` (taken and marked seen when
  the Me tab opens; the tab shell invalidates it); closing a reward sheet marks that badge seen.
  Badge tests override `packStoreProvider` with a temp-dir store; app tests without one get no
  awards.
- **Hear the name:** `speechProvider` (`core/speech.dart`, `flutter_tts`) reads a new street's name
  in `speechLanguage(name)`; the button shows only when `canSpeakProvider` finds a voice. Tests
  override `speechProvider`.
- **Strings:** every UI string comes from `lib/l10n/app_{en,ka}.arb` (gen-l10n, `context.l10n`);
  `just gen` writes `app_localizations*.dart` (not committed). Georgian is a draft awaiting native
  review.
  Numbers through `formatNumber` (narrow no-break space groups), distances through
  `formatDistance`. Never uppercase.
- **Settings** (`user_settings`, watched by `settingsProvider`): language (null = device),
  street names, theme, sound, haptics, zoom buttons (Map), minutes a day, reminder, the account (plus the first
  Home's coach-mark flag); they apply immediately. Learning settings (`/settings/learning`) hold
  the minutes, home and work, street names and the reminder. `feedbackProvider` plays haptics and sounds per game
  event behind the Haptics and Sound toggles. The kit is `assets/sounds/*.wav`
  (`core/sounds.dart`, audioplayers low-latency, ambient/no focus so other audio keeps playing),
  synthesized (FM plucks and bells in C major, a ComfyUI wooden tok under the pin drop) and
  finished with `just sounds DIR`; hero buttons play `tap`
  through `PindoroButton.onHeroPress`. `Sounds` stays silent until loaded, so tests need no override.
- **Streak:** only counted days are stored (`goal_day`, written by `markDayIfCounts` after a
  learning answer once nothing is due or the day's minutes are spent). `streakProvider` derives
  the streak, freezes and pill state with pindoro_core `streakOf`; the app root refreshes it on
  resume. One reminder is scheduled at a time (`reminderProvider` in `features/learning` →
  `Reminders`, listened to at the app root): 19:00 on a day that hasn't counted, only when reviews
  are due by its end. Learning settings turn it off and cancel it. Tests override
  `remindersProvider`: the notifications plugin has no platform side there.
- **Drift defaults are literals** (`Constant('local')`): drift copies them into the generated
  migration steps, which can't see app enums. No Flutter imports in `database.dart` either.
- **Database:** `database.dart` holds only tables and migrations. Queries live in Drift DAOs
  (`@DriftAccessor`, built without `daos:` so `core` never imports a feature): `SettingsDao`
  (`core/database/`, `settingsDaoProvider`) owns the settings row with typed writes
  (`chooseCity` clears another city's area, `chooseArea`, `chooseDifficulty`, `setTheme`, …);
  `ProgressDao` (`features/progress/data/`, `progressDaoProvider`) owns rounds, planned questions,
  the answer log, counted days and badges, and the rules read from them (saved round, retry set,
  recent streets); `LearningDao` owns the cards, the review log, mix-ups and `learn_city`.
  Screens call these providers, never `databaseProvider`. Client ids are UUIDv7 (`newId()`).
  `answer` is an append-only log, enforced by the `answer_immutable` trigger; so is `review_log`
  (`review_log_no_update` / `review_log_no_delete`, docs/learning/SPEC.md §2.2). Changing a table: bump `schemaVersion`, add a migration, run
  `just gen` (it runs `drift_dev make-migrations`, then build_runner) and commit the new dump in
  `drift_schemas/`. Generated Dart (`*.g.dart`, `database.steps.dart`, `test/drift/**/generated/`)
  is never committed: `just gen` rebuilds it from the dumps, and `just gen-check` fails in CI
  when a dump is missing.
- **Config** only via `--dart-define` (`AppConfig`): `API_BASE_URL`, `TILES_BASE_URL` (pack
  URLs come absolute from the API catalog). Dev defaults use 10.0.2.2 (Android emulator → host);
  on the iOS simulator pass `http://localhost:3000` / `:3001` and start the API with
  `PACKS_PUBLIC_URL=http://localhost:8080`.
  Cleartext HTTP is allowed only in the debug/profile manifests.
- **Updates:** sideloaded installs never update themselves. `appUpdateProvider`
  (`features/pack/data/app_update.dart`) compares the catalog's `app.build` with this build
  (`package_info_plus`); the app root offers the download once per launch and Settings → About
  shows the version. That offer is the Android APK, so iOS skips it: SideStore shows iOS updates
  from the source the iOS release workflow publishes. Bump `version` in `pubspec.yaml` for every
  build handed out.

## Map

- Flutter widgets that sit on map points (the sweep's sockets, the crossings' rings, "End 1") go
  in a `GeoAnchors` over the map, fed by `PindoroMap.onCamera`'s projection.
- `PindoroMap`, the area picker and Explore's map share `MapHost` (`map_host.dart`: the controller,
  the style per theme brightness, `mapProjection`); the area levels (`detailAt`, `areaAt`,
  `nearestAreas`) are pure, in `features/map/data/area_levels.dart`.
- `PindoroMap` loads the bundled style, injects `{TILES_BASE_URL}` (Martin source `georgia` and its
  FiraGO glyphs) and `{NAME_KEY}` (`name`, or `name:en` with English street names), and always
  shows "© OpenStreetMap contributors, Protomaps". Never point it at public OSM tile servers.
- The basemap draws no text but its name layers (pipeline `tiles.ts` `NAME_LAYERS`): `road-names`,
  and `poi-names`, `area-names` (neighbourhoods) and `water-names` (rivers), which go together as
  the places. They stay hidden until `PindoroMap.names` (`MapNames`, `map_style.dart`) shows them
  (SPEC §16.22 item 111). Intros, reveals and maps that are no question show every name. Other
  questions show places through `MapNames.asking(street)`, whose `placesNot` stems hide a place
  named after the asked street. A place question shows Known streets only, and a drill only its
  own streets. Its landmark icons (the style's `pois` layer) are `poi-<kind>` images, and its
  always-on `oneway-arrows` (from z16) use the `oneway` image (`onewayArrowPng`). `addBasemapImages`
  (`features/map/ui/poi_icons.dart`) adds both after the overlays, in `PindoroMap`, the area
  picker and Explore's map. A kind added to the pipeline's `POI_KINDS` needs an entry in
  `poiIcons`.
- GeoJSON source names: `you-pin` (a symbol of the `PinMark` rendered to PNG, anchored at its tip),
  `truth-street` (8 dp yellow over a 12 dp ink casing), `truth-point` (a place as the answer:
  yellow dot, ink ring), `measure` (dotted ink) + `measure-end` (ring), `area-mask` (dims outside
  the round's area), `trace` (a drill's streets, grey), `hit-street` (a Mix-up's, dashed cobalt).
  Lines go under the basemap's names (`NameLayers.lowest`), points over them. The map owns its
  controls (my location, recentre, and zoom only with Settings → Map → Zoom buttons) and the
  attribution chip, placed above `bottomInset`.
- Street View is a link only (`core/google_maps.dart`: `GoogleMaps.streetView`, `streetSpot`,
  `placeSpot`; `StreetViewButton`), on intros and reveals.
- **Round screens** (`features/quiz`, `features/results`): `/round` is one Explore route for setup
  states, question and reveal; Results (`results_data.dart` gathers everything) and the per-answer
  street view.
- Colour rule: **yellow = truth, cobalt = you, ink = measurement.** Never swap them.
- Screens get the map through `pindoroMapBuilderProvider`; tests override it to capture the
  `PindoroMap` config instead of building the platform view. Explore's city map (`ExploreMap`:
  district fills by City memory, the play area dashed) comes through `exploreMapBuilderProvider`;
  any test that opens Explore overrides it. The other tab maps are painted (`DistrictMap`,
  `AreaMiniMap`), never a platform view.
- Map insets are measured, never guessed: overlays go in `MapLayout` (`features/map/ui`: `top`,
  `bottom`, `behind`, `front`; the map is built with their heights), or a panel in a Scaffold's
  `bottomNavigationBar` with `extendBody` and `MediaQuery.paddingOf(body).bottom` (area, home and
  work, Add landmark, result street). A constant inset hides the attribution once text wraps.
- Overlay layers are added with `enableInteraction: false`: maplibre_gl turns taps on interactive
  layers into feature taps, and no pin would drop.

## Commands

```sh
flutter test                 # from apps/mobile
just gen                     # tokens + drift codegen
just run-mobile              # needs `just dev` running for tiles
```
