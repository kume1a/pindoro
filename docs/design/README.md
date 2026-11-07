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

## Where the app deliberately differs

- **Map stack.** The design system assumes CARTO raster tiles in `flutter_map`. The app uses
  self-hosted Protomaps vector tiles in MapLibre (`docs/adr/0001-architecture.md`), so the basemap is
  coloured from `color.map.basemap.*` and the attribution reads "© OpenStreetMap contributors,
  Protomaps".
- **App-only tokens** would live in `packages/pindoro_design/tokens/app.json`; it is empty now that
  the design system defines the vector basemap layers, the area mask and the camera framing.
- **Generated Dart.** `lib/src/generated/pindoro_tokens.dart` is generated from both token files by
  `tool/generate_tokens.dart`; the artifact's `handoff/pindoro_tokens.dart` is not used. Type roles
  all carry tabular figures and skip the Noto fallback (the system font covers missing glyphs).
