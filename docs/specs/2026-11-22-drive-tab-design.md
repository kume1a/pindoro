# Drive tab: start a drive from the first page

## Goal

The user drives with Pindoro as their main navigation app, with the phone in a holder and no CarPlay.
Today a drive starts from Me → Drives → Drive, or from Today's run card on days with a run. This
design puts driving on the first page: open the app, tap Home, tap Start.

## Decisions (the user's, 2026-11-22)

- **A Drive tab, first in the bar, and the app opens on it.** Learning stays one tap away on Today.
- **Big buttons, no map.** The tab opens instantly; the map comes once a drive starts.
- **Every drive card moves from Today to the Drive tab.** Today goes back to learning only.

## Tabs and launch

- The bar becomes **Drive · Today · Explore · Progress · Me**. Drive uses `PindoroGlyph.car` and
  the existing `driveTitle` label ("Drive").
- `startLocation` sends a player who used to open on Today (one who played or has a saved round) to
  the Drive tab. Anyone else still starts at Welcome, and Welcome's Start learning still goes to
  Today and its placement.
- Back on any other tab goes to the Drive tab first; back on the Drive tab leaves the app.
- Paths: the tab is `/drive` (`Routes.driveTab`). The drive flow (setup, recording, debrief) moves
  from `/drive` to `/drive/go` (`Routes.drive`), so code that pushes `Routes.drive` keeps meaning
  "the flow". `?to=run` stays.

## The Drive tab

Top to bottom:

1. **Where to?** The existing `DestinationSearch` field. Typing lists streets and places inline, as
   now.
2. **Home and Work**, two `StatTile`s in a `TileGrid` of two columns.
   - Set: the glyph, "Home" or "Work", and the minutes there by the route a drive would take
     (`planNav`, the same cost as the drive). Minutes show only when location is already allowed
     and a fix arrives; otherwise the tile shows the place's name. The tab never asks for location.
   - Not set: "Set Home" or "Set Work", opening the existing picker (`/drive/place`).
3. **Today's run** (only on a day with one) and **Surprise me**, as the rows they are today.
4. **Recent**, the existing recent destinations.
5. The drive cards moved from Today, each only when it applies, as today:
   - the drive waiting for its debrief (`SuggestionCard`);
   - the week's goal (`DriveWeekCard` with what was planned and "from your drives"), then the
     step-down nudge;
   - "Pick your two drives" (`PlanChecklist`).
6. **Past drives**, the row that was in Me, with its count.

With text typed into Where to, only the search results show (items 2–6 hide), as the search does
now with its quick rows.

Picking anything opens the drive flow on that destination: Home, Work, the run and Surprise me by
`?to=home|work|run|surprise`, a searched or recent street or place as the route's `extra` (the
`DriveDest` record). The flow shows the destination, time
and suggested level, then Preview or Start. When the drive or its debrief ends, the flow pops back
to the Drive tab (its fallback is the Drive tab, not Today).

## What moves out

- **Today** loses `TodayDrives` (its widget file moves to the drive feature). "Drive this run
  today" stays: the run is part of the day's plan.
- **Me** loses its Drives section (the Drive row and Past drives); both live on the Drive tab now.
- The flow's own Where to page (`DriveSetup` with no destination) stays for the stopped bar's Route
  button and for `/drive/go` opened without `?to=`.
- Settings → Driving is unchanged.

## Design system and docs

- No new design-system parts: `SearchField`, `StatTile`, `TileGrid`, `ListRow`, `SuggestionCard`,
  `GoalLine`/`DriveWeekCard`, `PlanChecklist` and `PindoroNavBar` already exist.
- The canvas has no Drive tab board; `docs/TODO.md` notes the carry-back (as with v3.1's quick-start
  cards).
- SPEC §16.23 gets item 129 with these decisions. `apps/mobile/CLAUDE.md` updates the tab list,
  routes and where the drive cards live.

## Testing

- Router: a played player opens on the Drive tab; back from another tab goes to Drive.
- Drive tab: Home and Work tiles (set, unset, with and without minutes), tapping Home opens the
  flow's setup on Home, a search pick opens it on that street, the drive cards show here (the
  Today drives test moves here).
- Today no longer shows the drive cards; Me no longer shows the Drives section.
- Existing tests that assume Today is the first tab or the start page are updated.

## Not in this change

- App icon shortcuts ("Drive home", "Drive to work" on a long press of the icon).
- Resuming a drive after the OS kills the app mid-drive (today the drive is lost).
- A map on the Drive tab.
