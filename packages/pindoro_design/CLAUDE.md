# pindoro_design

Flutter design system: generated tokens, `buildPindoroTheme`, `PindoroTheme` extension and the
Signpost widgets (`PindoroButton`, `StreetPlate`, `FeedbackBadge`).

## Tokens

- Source of truth: `tokens/tokens.json` (flat dot-named keys; `color.*` hex, `motion.*`
  `{duration_ms, curve}`, other numbers = dp). Intent lives in `docs/design/*.md`.
- `tool/generate_tokens.dart` writes `lib/src/generated/pindoro_tokens.dart`. **Never hand-edit
  generated code** — edit `tokens.json`, then run `just gen` and commit both. CI runs
  `just tokens-check` (regenerate + `git diff --exit-code`).
- No literal colours, radii, spacing or durations in widgets: use `PindoroTokens` / `PindoroTheme`.

## Rules

- Never uppercase UI strings. FiraGO (OFL, `fonts/OFL.txt`) everywhere; the theme turns on tabular
  figures for all text styles.
- Tier → colour + icon: perfect yellow star, great aqua check-circle, close orange target,
  miss red reroute. Map roles: yellow = truth, cobalt = you, ink = measurement.
- `StreetPlate`: max 2 lines, shrink 2 dp steps down to 20 dp, then wrap — never truncate.

## Tests

`flutter test` from this package. Goldens live in `test/goldens/` and are **Linux-only** (glyph
rasterisation differs per OS): they are skipped elsewhere and compared on Linux CI with a 1.5 %
tolerance for Flutter stable drift (`test/flutter_test_config.dart`, which also loads the real
fonts). After an intended visual change run `just goldens` (regenerates them in a Linux Flutter
container) and commit the PNGs.
