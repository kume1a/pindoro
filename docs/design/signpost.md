# Signpost — Pindoro visual language (PLACEHOLDER)

> Placeholder written during Milestone 0 bootstrap; replace with the real design spec.
> All values live in `packages/pindoro_design/tokens/tokens.json`; this file explains intent only.

- **Road-sign plates.** Street names appear on a cobalt plate with a white inset border and white
  FiraGO text (`StreetPlate`). Max two lines; the font shrinks in 2 dp steps down to a 20 dp floor
  and never truncates.
- **Chunky, tactile buttons.** Flat surface with a solid darker bottom lip; on press the face moves
  down onto the lip (`PindoroButton`, variants primary / secondary / ghost).
- **Colour roles on the map.** Yellow = truth (the real street), cobalt = you (your pin), ink =
  measurement (dashed distance line). Never swap them.
- **Feedback tiers.** perfect = yellow star, great = aqua check-circle, close = orange target,
  miss = red reroute.
- **Unlabelled map.** Basemap without any text/symbol layers; the player must know the city.
- **Type.** FiraGO for Georgian and Latin, tabular figures for every number.
  Never uppercase UI strings (Georgian has no case; consistency for Latin too).
- **Shape.** Radius 16 for cards and buttons, 10 for plates.
