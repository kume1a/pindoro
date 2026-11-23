# Design docs

Everything here except this file is copied verbatim from the
[Pindoro design system](https://claude.ai/artifact/5hFQnWQ3hn8o7G4Fjy6y7K) on claude.ai, the source of
truth for design. Edit there, then pull: overwrite these files and
`packages/pindoro_design/tokens/tokens.json` with the artifact's copies and run `just gen`.

| File                      | Artifact path                     |
| ------------------------- | --------------------------------- |
| `signpost.md`             | `project/README.md`               |
| `v1-screens.md`           | `project/v1-screens.md`           |
| `flutter-handoff.md`      | `project/flutter-handoff.md`      |
| `accessibility.md`        | `project/accessibility.md`        |
| `motion-sound-haptics.md` | `project/motion-sound-haptics.md` |

Per-component specs (`project/components/<Name>/README.md`) and the screens canvas stay on claude.ai;
read them from there when building a component or screen. The image assets (icons, logos, mascot,
app icon, splash) come from the design system's asset store; see `packages/pindoro_design/CLAUDE.md`.

## Keeping the two in sync

The design system's `README.md` (here `signpost.md`) has an "App sync" section: the app version
last folded in and the deliberate differences. The screens canvas keeps the app as built on its page
"Current app (Nov 2026)" and a sync log on board C-99. When the app changes ahead of the design,
the change goes in `docs/TODO.md` under "Changed in the app, not yet on claude.ai", any new token in
`packages/pindoro_design/tokens/app.json` (`opacity.building-raised` since 2026-11-23), and the next sync sends
both to claude.ai as a `design-gaps.md` plus the token file.

## Where the app deliberately differs

- **Map stack.** The design system's fallback is CARTO raster tiles in `flutter_map`. The app uses
  self-hosted Protomaps vector tiles in MapLibre (`docs/adr/0001-architecture.md`) and the attribution
  reads "© OpenStreetMap contributors, Protomaps". The vector basemap's palette (`color.map.vector.*`)
  and landmark icon colours (`color.map.poi.*`, Maki icons in `pindoro_design/assets/map_icons`) are
  design-system tokens since the 2026-11-20 sync.
- **Generated Dart.** `lib/src/generated/pindoro_tokens.dart` is generated from both token files by
  `tool/generate_tokens.dart`; the artifact's `handoff/pindoro_tokens.dart` is not used. Type roles
  all carry tabular figures and skip the Noto fallback (the system font covers missing glyphs).
